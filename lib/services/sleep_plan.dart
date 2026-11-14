// 次のシフトに合わせた睡眠プラン（A-2）
//
// 1/4：場面の分け方（SleepScene）と、寝方のタイプ（帰ってすぐ寝る／出勤ギリギリまで寝る）の決め方
// 目安の時刻（buildSleepPlan）・文言・設定の保存は 2/4〜4/4 で作る
// DB・アラームには依存しない
import 'package:shiftsleep/services/next_shift.dart';
import 'package:shiftsleep/services/sleep_baseline.dart';

/// 場面で見る「前の勤務」の範囲（now の 24 時間前以後に終わった勤務。ちょうどを含む）
const Duration sleepScenePreviousLookback = Duration(hours: 24);

/// 前の勤務の終わりから次の勤務の始まりまでがこれより短ければ「間が短い」（ちょうど 11 時間は入らない）
const Duration quickReturnMaxGap = Duration(hours: 11);

/// 寝方のタイプを記録から決めるのに要る件数（夜勤の組の件数。ちょうどを含む）
const int sleepStyleMinSamples = 3;

/// 寝方のタイプとみなす gap の中央値の上限（ちょうどを含む）
const Duration sleepStyleMaxMedianGap = Duration(hours: 3);

/// S8：寝方のタイプが設定でも記録でも決まらないときの既定
const SleepStyle defaultSleepStyle = SleepStyle.immediate;

/// 次の勤務に向けた場面
enum SleepScene {
  /// 日勤前（前は日勤・準夜勤）
  beforeDay,

  /// 準夜勤前（前はなし・日勤・準夜勤）
  beforeEvening,

  /// 夜勤前（前の勤務なし）
  beforeNight,

  /// 間が短い（前の終わり→次の始まりが 11 時間未満。日勤→深夜・準夜勤→日勤・深夜→準夜勤など）
  quickReturn,

  /// 連続夜勤のあいだ（前も次も夜勤）
  betweenNights,

  /// 夜勤明け→休み（前が夜勤で、48 時間以内に次の勤務がない）
  nightToOff,

  /// 夜勤→日勤の切り替え（前が夜勤、次が日勤・準夜勤）
  nightToDay,

  /// 日勤→夜勤の切り替え（前が日勤・準夜勤、次が夜勤）
  dayToNight,

  /// 休み明け（前の勤務なし、次が日勤）
  afterRest,

  /// 勤務なし（48 時間以内に次の勤務がなく、前も夜勤でない）
  noShift,
}

/// 次の勤務に向けた場面を決める
/// - 次の勤務：nextWorkShift（now から 48 時間以内に始まる。勤務中は除く）
/// - 前の勤務：previousWorkShift（now の 24 時間前〜now に終わった。勤務中は除く）
/// - 当てはまる最初のものにする：
///   noShift → quickReturn → betweenNights → nightToDay → dayToNight → nightToOff
///   → beforeNight → beforeEvening → afterRest → beforeDay
/// - noShift は「次がなく、前も夜勤でない」とき（前が夜勤なら nightToOff）
SleepScene classifySleepScene({
  required DateTime now,
  required List<WorkShift> shifts,
}) {
  final next = nextWorkShift(now, shifts);
  final previous = previousWorkShift(now, shifts, lookback: sleepScenePreviousLookback);
  final previousIsNight = previous?.kind == ShiftKind.night;

  if (next == null && !previousIsNight) return SleepScene.noShift;
  if (previous != null && next != null && next.startAt.difference(previous.endAt) < quickReturnMaxGap) {
    return SleepScene.quickReturn;
  }
  final nextIsNight = next?.kind == ShiftKind.night;
  if (previousIsNight && nextIsNight) return SleepScene.betweenNights;
  if (previousIsNight && next != null) return SleepScene.nightToDay;  // 次は日勤・準夜勤
  if (previous != null && !previousIsNight && nextIsNight) return SleepScene.dayToNight;
  if (previousIsNight) return SleepScene.nightToOff;  // 次がない
  if (nextIsNight) return SleepScene.beforeNight;  // 前がない
  if (next?.kind == ShiftKind.evening) return SleepScene.beforeEvening;
  if (previous == null) return SleepScene.afterRest;
  return SleepScene.beforeDay;
}

/// 寝方のタイプ
enum SleepStyle {
  /// 帰ってすぐ寝る（勤務明けすぐに寝て、出勤までは起きている）
  immediate,

  /// 出勤ギリギリまで寝る
  lastMinute,
}

/// 設定で選ぶ寝方のタイプ（auto は記録から決める）
enum SleepStylePreference { auto, immediate, lastMinute }

/// 寝方のタイプをどこから決めたか
enum SleepStyleSource {
  /// 設定で選んだ
  setting,

  /// 記録から決めた
  records,

  /// 決まらず既定（defaultSleepStyle）にした
  fallback,
}

Duration? _median(List<Duration> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) ~/ 2;
}

/// 記録から寝方のタイプを決める。決まらなければ style は null
/// - 使うのは夜勤の組だけ（勤務明け：前の勤務が夜勤、出勤前：次の勤務が夜勤）
/// - 帰ってすぐ寝る：勤務明けの gap が 3 件以上で、中央値が 3 時間以下
/// - 出勤ギリギリまで寝る：出勤前の gap が 3 件以上で、中央値が 3 時間以下
/// - 両方に当てはまれば中央値の小さいほう（同じなら帰ってすぐ寝る）
({SleepStyle? style, int afterSamples, int beforeSamples}) detectSleepStyle(SleepBaseline baseline) {
  final after = [
    for (final gap in baseline.afterShift)
      if (gap.shift.kind == ShiftKind.night) gap.gap,
  ];
  final before = [
    for (final gap in baseline.beforeShift)
      if (gap.shift.kind == ShiftKind.night) gap.gap,
  ];

  Duration? qualifyingMedian(List<Duration> gaps) {
    if (gaps.length < sleepStyleMinSamples) return null;
    final median = _median(gaps)!;
    return median <= sleepStyleMaxMedianGap ? median : null;
  }

  final afterMedian = qualifyingMedian(after);
  final beforeMedian = qualifyingMedian(before);

  final SleepStyle? style;
  if (afterMedian != null && beforeMedian != null) {
    style = beforeMedian < afterMedian ? SleepStyle.lastMinute : SleepStyle.immediate;
  } else if (afterMedian != null) {
    style = SleepStyle.immediate;
  } else if (beforeMedian != null) {
    style = SleepStyle.lastMinute;
  } else {
    style = null;
  }
  return (style: style, afterSamples: after.length, beforeSamples: before.length);
}

/// 使う寝方のタイプを決める（順番：設定 → 記録 → 既定）
/// - 設定が auto 以外ならそれ
/// - auto なら detectSleepStyle。決まらなければ defaultSleepStyle（帰ってすぐ寝る）
({SleepStyle style, SleepStyleSource source}) resolveSleepStyle(
  SleepStylePreference preference,
  SleepBaseline baseline,
) {
  switch (preference) {
    case SleepStylePreference.immediate:
      return (style: SleepStyle.immediate, source: SleepStyleSource.setting);
    case SleepStylePreference.lastMinute:
      return (style: SleepStyle.lastMinute, source: SleepStyleSource.setting);
    case SleepStylePreference.auto:
      final detected = detectSleepStyle(baseline).style;
      if (detected != null) return (style: detected, source: SleepStyleSource.records);
      return (style: defaultSleepStyle, source: SleepStyleSource.fallback);
  }
}
