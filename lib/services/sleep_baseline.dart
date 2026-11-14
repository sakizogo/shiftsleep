// 睡眠のベースライン（A-1 2/2）
//
// 次のシフトに合わせた睡眠プラン（A）のもとになる「ふだんの睡眠」を、睡眠記録と勤務から出す
// - メイン睡眠：短い目覚めをはさんだ記録をまとめた 1 回分で、寝ていた時間が 5 時間以上のもの
// - 平均の睡眠時間（6〜9 時間に収める。記録が少なければ 7 時間）
// - 入眠・起床・真ん中の時刻の円周平均（23:30 と 0:30 の平均が 0:00 になる）
// - 寝方のタイプ用の値：勤務の終わり→入眠（勤務明け）、起床→出勤（出勤前）。タイプの判定は A-2 で行う
// - メイン睡眠に入らなかった睡眠（30 分以上 5 時間未満）の件数と合計（分割睡眠の人を A-2 で見分けるため）
// SleepRole は見ない（v8 の移行のあとは決め直されず、ほぼすべて primary のため。実際の長さで決める）
// DB・アラームには依存しない
import 'dart:math' as math;

import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/next_shift.dart';
import 'package:shiftsleep/services/sleep_record_validation.dart';

/// メイン睡眠とみなす、寝ていた時間の下限（5 時間ちょうどを含む）
const Duration mainSleepMinAsleep = Duration(hours: 5);

/// メイン睡眠に入らなかった睡眠として数える下限（30 分ちょうどを含む）
const Duration shortSleepMinAsleep = Duration(minutes: 30);

/// 1 回の睡眠にまとめる、記録どうしの間の上限（60 分ちょうどはまとめる）
const Duration sleepMergeMaxGap = Duration(minutes: 60);

/// ベースラインに使う期間（起床が now − 28 日〜now の睡眠）
const Duration baselineWindow = Duration(days: 28);

/// これより少ないメイン睡眠しかなければ「記録が少ない」（平均は 7 時間、円周平均は null）
const int baselineMinSamples = 5;

/// 平均の睡眠時間を収める範囲の下限
const Duration averageAsleepMin = Duration(hours: 6);

/// 平均の睡眠時間を収める範囲の上限
const Duration averageAsleepMax = Duration(hours: 9);

/// 記録が少ないときの平均の睡眠時間
const Duration defaultAverageAsleep = Duration(hours: 7);

/// 勤務明けの睡眠とみなす、勤務の終わりから入眠までの上限（ちょうどを含む）
const Duration afterShiftMaxGap = Duration(hours: 6);

/// 出勤前の睡眠とみなす、起床から出勤までの上限（ちょうどを含む）
const Duration beforeShiftMaxGap = Duration(hours: 12);

/// 円周平均のそろい具合（R）がこれより小さければ、平均の時刻は意味がないので null
const double circularMinConcentration = 0.1;

const int _minutesPerDay = 24 * 60;

/// 1 回分の睡眠（短い目覚めをはさんだ記録はまとめる）
class MainSleep {
  /// 最初の記録の入眠
  final DateTime start;

  /// いちばん遅い起床
  final DateTime end;

  /// 寝ていた時間の合計（間の目覚めは入れない。重なった部分は 1 回だけ数える）
  final Duration asleep;

  /// まとめた元の記録の ID（入眠の早い順）
  final List<String> recordIds;

  const MainSleep({
    required this.start,
    required this.end,
    required this.asleep,
    required this.recordIds,
  });

  /// 入眠と起床の真ん中（間の目覚めも含めた時計の上の真ん中）
  DateTime get midpoint => start.add(end.difference(start) ~/ 2);

  @override
  String toString() => 'MainSleep(start: $start, end: $end, asleep: $asleep, recordIds: $recordIds)';
}

/// 時刻の円周平均
class CircularTimeMean {
  /// 平均の時刻（0:00 からの分。0〜1439）
  final int minuteOfDay;

  /// そろい具合 R（0〜1。1 に近いほど時刻がそろっている）
  final double concentration;

  const CircularTimeMean({required this.minuteOfDay, required this.concentration});

  @override
  String toString() => 'CircularTimeMean(minuteOfDay: $minuteOfDay, concentration: $concentration)';
}

/// 勤務明け・出勤前の睡眠 1 件分
class ShiftSleepGap {
  /// メイン睡眠
  final MainSleep sleep;

  /// 前の勤務（勤務明け）または次の勤務（出勤前）
  final WorkShift shift;

  /// 勤務明け：勤務の終わり→入眠。出勤前：起床→出勤
  final Duration gap;

  /// A-4 1/3（D79 C）：勤務明けのとき、その勤務のパターンのいつもの残業（gap は登録どおりの終わりから測る）
  final Duration overtime;

  const ShiftSleepGap({required this.sleep, required this.shift, required this.gap, this.overtime = Duration.zero});

  @override
  String toString() => 'ShiftSleepGap(sleep: ${sleep.start}〜${sleep.end}, shift: ${shift.startAt}, gap: $gap)';
}

/// 睡眠のベースライン
class SleepBaseline {
  /// 使ったメイン睡眠の件数
  final int sampleCount;

  /// 記録が少なく（baselineMinSamples 件未満）、平均を 7 時間にしたか
  final bool usedDefault;

  /// 平均の睡眠時間（6〜9 時間に収めたもの。記録が少なければ 7 時間）
  final Duration averageAsleep;

  /// 収める前の平均（メイン睡眠がなければ null）
  final Duration? rawAverageAsleep;

  /// 入眠の円周平均（記録が少ない・そろっていなければ null）
  final CircularTimeMean? bedtime;

  /// 起床の円周平均（記録が少ない・そろっていなければ null）
  final CircularTimeMean? wakeTime;

  /// 真ん中の時刻の円周平均（記録が少ない・そろっていなければ null）
  final CircularTimeMean? midpoint;

  /// 勤務明けのメイン睡眠（入眠の早い順）
  final List<ShiftSleepGap> afterShift;

  /// 出勤前のメイン睡眠（入眠の早い順）
  final List<ShiftSleepGap> beforeShift;

  /// メイン睡眠に入らなかった睡眠（まとめたあと 30 分以上 5 時間未満）の件数
  final int shortSleepCount;

  /// メイン睡眠に入らなかった睡眠の、寝ていた時間の合計
  final Duration shortSleepTotal;

  const SleepBaseline({
    required this.sampleCount,
    required this.usedDefault,
    required this.averageAsleep,
    required this.rawAverageAsleep,
    required this.bedtime,
    required this.wakeTime,
    required this.midpoint,
    required this.afterShift,
    required this.beforeShift,
    required this.shortSleepCount,
    required this.shortSleepTotal,
  });
}

/// 期間内の睡眠を、短い目覚めをはさんだ記録をまとめて 1 回ずつにする（メイン睡眠かどうかは問わない）
/// - 使わない記録：durationMinutes が 0（記録中・途中で終わった記録）、10 分以下、20 時間を超える、起床が now より後
/// - 終了が開始より前の記録は、終了を +1 日として扱う（N35 と同じ）
/// - 間が mergeGap 以下（重なりを含む）ならまとめる。寝ていた時間は重なった部分を 1 回だけ数える
/// - まとめたあとの起床が now − window 以後のものだけ（ちょうどを含む）
List<MainSleep> _sleepSessions(
  List<SleepRecord> records,
  DateTime now,
  Duration window,
  Duration mergeGap,
) {
  final usable = <({String id, DateTime start, DateTime end})>[];
  for (final record in records) {
    if (record.durationMinutes == 0) continue;
    final start = record.sleepStartTime;
    var end = record.sleepEndTime;
    if (end.isBefore(start)) end = end.add(const Duration(days: 1));
    final length = end.difference(start);
    if (length <= SleepRecordValidation.minDurationExclusive) continue;
    if (length.inMinutes > SleepRecordValidation.maxSleepDuration.inMinutes) continue;
    if (end.isAfter(now)) continue;
    usable.add((id: record.id, start: start, end: end));
  }
  usable.sort((a, b) => a.start.compareTo(b.start));

  final sessions = <MainSleep>[];
  for (final record in usable) {
    final last = sessions.isEmpty ? null : sessions.last;
    // 入眠が「今の起床 + mergeGap」以前ならまとめる（重なっているときも含む）
    if (last != null && !record.start.isAfter(last.end.add(mergeGap))) {
      // 重なった部分は数えない（入眠の早い順なので、今の起床より後の分だけを足す）
      final countFrom = record.start.isAfter(last.end) ? record.start : last.end;
      final added = record.end.isAfter(countFrom) ? record.end.difference(countFrom) : Duration.zero;
      sessions.last = MainSleep(
        start: last.start,
        end: record.end.isAfter(last.end) ? record.end : last.end,
        asleep: last.asleep + added,
        recordIds: [...last.recordIds, record.id],
      );
    } else {
      sessions.add(MainSleep(
        start: record.start,
        end: record.end,
        asleep: record.end.difference(record.start),
        recordIds: [record.id],
      ));
    }
  }

  final from = now.subtract(window);
  return sessions.where((s) => !s.end.isBefore(from)).toList();
}

/// 期間内のメイン睡眠（まとめたあと、寝ていた時間が 5 時間以上の 1 回分）。入眠の早い順
/// - 使わない記録・まとめ方は _sleepSessions のとおり（SleepRole は見ない）
List<MainSleep> mainSleepsFrom(
  List<SleepRecord> records,
  DateTime now, {
  Duration window = baselineWindow,
  Duration mergeGap = sleepMergeMaxGap,
}) {
  return _sleepSessions(records, now, window, mergeGap)
      .where((s) => s.asleep >= mainSleepMinAsleep)
      .toList();
}

/// 時刻（0:00 からの分）の円周平均。空・そろい具合が circularMinConcentration より小さければ null
/// - 例：23:30 と 0:30 の平均は 0:00（ふつうの平均の 12:00 にはならない）
CircularTimeMean? circularMeanOfMinutes(Iterable<int> minutesOfDay) {
  var sumCos = 0.0;
  var sumSin = 0.0;
  var count = 0;
  for (final minutes in minutesOfDay) {
    final angle = 2 * math.pi * minutes / _minutesPerDay;
    sumCos += math.cos(angle);
    sumSin += math.sin(angle);
    count++;
  }
  if (count == 0) return null;
  final concentration = math.sqrt(sumCos * sumCos + sumSin * sumSin) / count;
  if (concentration < circularMinConcentration) return null;
  final meanMinutes = (math.atan2(sumSin, sumCos) * _minutesPerDay / (2 * math.pi)).round();
  return CircularTimeMean(
    minuteOfDay: ((meanMinutes % _minutesPerDay) + _minutesPerDay) % _minutesPerDay,
    concentration: concentration,
  );
}

int _minuteOfDay(DateTime time) => time.hour * 60 + time.minute;

/// A-4 1/3：勤務のパターンのいつもの残業（設定がなければ 0）
Duration overtimeOfShift(Map<String, Duration> overtimeByPattern, WorkShift shift) =>
    overtimeByPattern[shift.pattern.id] ?? Duration.zero;

/// 睡眠記録と勤務から、睡眠のベースラインを出す
/// - メイン睡眠が baselineMinSamples 件未満なら、平均は 7 時間・円周平均は null（usedDefault）
/// - そうでなければ、平均を 6〜9 時間に収める（収める前の値は rawAverageAsleep）
/// - 勤務明け：入眠の前に終わった直近の勤務（previousWorkShift。終わりから 6 時間以内。ちょうどを含む）
/// - 出勤前：起床の後に始まる最初の勤務（nextWorkShift。12 時間以内。ちょうどを含み、起床と同時に始まる勤務は除く）
/// - 1 回の睡眠が勤務明けと出勤前の両方に入ってもよい。半休の日の出勤も勤務として数える（workShiftsFromMap）
/// - メイン睡眠に入らなかった睡眠（30 分以上 5 時間未満）は件数と合計だけを出す
/// - A-4 1/3（D79 C）：いつもの残業（overtimeByPattern）があるパターンの勤務明けは、6 時間にその残業を足す
///   （gap は登録どおりの終わりから測り、ShiftSleepGap.overtime に残業を入れる）
SleepBaseline computeSleepBaseline({
  required List<SleepRecord> records,
  required List<WorkShift> shifts,
  required DateTime now,
  Map<String, Duration> overtimeByPattern = const {},
}) {
  final sessions = _sleepSessions(records, now, baselineWindow, sleepMergeMaxGap);
  final mains = sessions.where((s) => s.asleep >= mainSleepMinAsleep).toList();
  final shorts = sessions
      .where((s) => s.asleep >= shortSleepMinAsleep && s.asleep < mainSleepMinAsleep)
      .toList();

  Duration? rawAverage;
  if (mains.isNotEmpty) {
    final total = mains.fold<int>(0, (sum, s) => sum + s.asleep.inMicroseconds);
    rawAverage = Duration(microseconds: total ~/ mains.length);
  }

  final usedDefault = mains.length < baselineMinSamples;
  final Duration averageAsleep;
  if (usedDefault || rawAverage == null) {
    averageAsleep = defaultAverageAsleep;
  } else if (rawAverage < averageAsleepMin) {
    averageAsleep = averageAsleepMin;
  } else if (rawAverage > averageAsleepMax) {
    averageAsleep = averageAsleepMax;
  } else {
    averageAsleep = rawAverage;
  }

  final afterShift = <ShiftSleepGap>[];
  final beforeShift = <ShiftSleepGap>[];
  final maxOvertime = overtimeByPattern.values.fold(Duration.zero, (max, d) => d > max ? d : max);
  for (final sleep in mains) {
    final previous = previousWorkShift(sleep.start, shifts, lookback: afterShiftMaxGap + maxOvertime);
    if (previous != null) {
      final overtime = overtimeOfShift(overtimeByPattern, previous);
      final gap = sleep.start.difference(previous.endAt);
      if (gap <= afterShiftMaxGap + overtime) {
        afterShift.add(ShiftSleepGap(sleep: sleep, shift: previous, gap: gap, overtime: overtime));
      }
    }
    final next = nextWorkShift(sleep.end, shifts, within: beforeShiftMaxGap);
    if (next != null) {
      beforeShift.add(ShiftSleepGap(sleep: sleep, shift: next, gap: next.startAt.difference(sleep.end)));
    }
  }

  return SleepBaseline(
    sampleCount: mains.length,
    usedDefault: usedDefault,
    averageAsleep: averageAsleep,
    rawAverageAsleep: rawAverage,
    bedtime: usedDefault ? null : circularMeanOfMinutes(mains.map((s) => _minuteOfDay(s.start))),
    wakeTime: usedDefault ? null : circularMeanOfMinutes(mains.map((s) => _minuteOfDay(s.end))),
    midpoint: usedDefault ? null : circularMeanOfMinutes(mains.map((s) => _minuteOfDay(s.midpoint))),
    afterShift: afterShift,
    beforeShift: beforeShift,
    shortSleepCount: shorts.length,
    shortSleepTotal: shorts.fold(Duration.zero, (sum, s) => sum + s.asleep),
  );
}
