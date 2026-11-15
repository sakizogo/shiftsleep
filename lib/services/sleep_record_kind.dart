// N184：睡眠記録を 1 件ずつ、長さでメイン睡眠と補助睡眠（昼寝・仮眠）に分ける
// - 保存された SleepRole は見ない（v8 の移行のあとは決め直されず、ほぼすべて primary のため）
// - 5 時間以上（ちょうどを含む）がメイン、5 時間未満が補助（境目は sleep_baseline の mainSleepMinAsleep）
// - 記録中・途中で終わった記録（durationMinutes == 0）は、どちらにも入れない
// - 短い目覚めをはさんだ記録はまとめない（sleep_baseline の mainSleepsFrom とは違う）
// N184 2/2：睡眠負債・1 日平均は、起床の日付で 1 日ごとに足して出す
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/sleep_baseline.dart' show mainSleepMinAsleep;

/// ホームの「睡眠の内訳」で見る期間（終わりが now − 24 時間〜now の記録）
const Duration recentSleepWindow = Duration(hours: 24);

/// 記録中、または途中で終わった記録か（終わりは仮の時刻なので、長さに意味がない）
bool isUnfinishedSleepRecord(SleepRecord record) => record.durationMinutes == 0;

/// 記録の終わり（終わりが始まりより前なら +1 日。sleep_baseline と同じ）
DateTime sleepRecordEnd(SleepRecord record) {
  final end = record.sleepEndTime;
  return end.isBefore(record.sleepStartTime) ? end.add(const Duration(days: 1)) : end;
}

/// 記録の長さ（終わり − 始まり）
Duration sleepRecordLength(SleepRecord record) =>
    sleepRecordEnd(record).difference(record.sleepStartTime);

/// メイン睡眠か：記録中でなく、長さが 5 時間以上
bool isMainSleepRecord(SleepRecord record) =>
    !isUnfinishedSleepRecord(record) && sleepRecordLength(record) >= mainSleepMinAsleep;

/// 補助睡眠（昼寝・仮眠）か：記録中でなく、長さが 5 時間未満
bool isNapSleepRecord(SleepRecord record) =>
    !isUnfinishedSleepRecord(record) && sleepRecordLength(record) < mainSleepMinAsleep;

/// 直近 24 時間の睡眠の内訳
class RecentSleepBreakdown {
  /// メイン睡眠の合計（なければ null。2 件あれば足す）
  final Duration? main;

  /// 補助睡眠の合計（なければ 0）
  final Duration naps;

  const RecentSleepBreakdown({required this.main, required this.naps});

  /// 合計（いつもメイン＋補助）
  Duration get total => (main ?? Duration.zero) + naps;
}

/// 終わりが now − 24 時間〜now（両端を含む）の記録から、メインと補助の合計を出す
RecentSleepBreakdown recentSleepBreakdown(List<SleepRecord> records, DateTime now) {
  final from = now.subtract(recentSleepWindow);
  Duration? main;
  var naps = Duration.zero;
  for (final record in records) {
    if (isUnfinishedSleepRecord(record)) continue;
    final end = sleepRecordEnd(record);
    if (end.isBefore(from) || end.isAfter(now)) continue;
    final length = sleepRecordLength(record);
    if (isMainSleepRecord(record)) {
      main = (main ?? Duration.zero) + length;
    } else {
      naps += length;
    }
  }
  return RecentSleepBreakdown(main: main, naps: naps);
}

/// 睡眠負債・1 日平均で見る期間（今日を含む 28 日＝直近 4 週間）
const int recentSleepDays = 28;

/// 1 日の区切り：起床の日付（夜勤明けに朝から寝ても、0:00 をまたいで寝ても、起きた日に数える）
DateTime sleepRecordWakeDay(SleepRecord record) {
  final end = sleepRecordEnd(record);
  return DateTime(end.year, end.month, end.day);
}

/// 起床の日付が firstDay〜lastDay（両端を含む）の記録を、日ごとに足す（メイン＋昼寝。記録中は除く）
/// 記録のない日は入れない（押し忘れの日を 0 時間と数えないため）
Map<DateTime, Duration> dailySleepTotals(
  Iterable<SleepRecord> records, {
  required DateTime firstDay,
  required DateTime lastDay,
}) {
  final totals = <DateTime, Duration>{};
  for (final record in records) {
    if (isUnfinishedSleepRecord(record)) continue;
    final day = sleepRecordWakeDay(record);
    if (day.isBefore(firstDay) || day.isAfter(lastDay)) continue;
    totals[day] = (totals[day] ?? Duration.zero) + sleepRecordLength(record);
  }
  return totals;
}

/// 直近 4 週間（today − 27 〜 today）の日ごとの合計
Map<DateTime, Duration> recentDailySleepTotals(Iterable<SleepRecord> records, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final firstDay = DateTime(today.year, today.month, today.day - (recentSleepDays - 1));
  return dailySleepTotals(records, firstDay: firstDay, lastDay: today);
}

/// 暦の今月（1 日〜今日）の日ごとの合計
Map<DateTime, Duration> thisMonthDailySleepTotals(Iterable<SleepRecord> records, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return dailySleepTotals(records, firstDay: DateTime(now.year, now.month, 1), lastDay: today);
}

/// 1 日あたりの平均（日がなければ null）
Duration? averageDailySleep(Map<DateTime, Duration> totals) {
  if (totals.isEmpty) return null;
  final sum = totals.values.fold(Duration.zero, (a, b) => a + b);
  return sum ~/ totals.length;
}

/// 睡眠時間の表示（7h 30m の形。マイナスなら -0h 2m）
String formatSleepDuration(Duration duration) {
  if (duration.isNegative) return '-${formatSleepDuration(-duration)}';
  return '${duration.inHours}h ${duration.inMinutes % 60}m';
}

/// 睡眠負債の表示（0 以上なら +、マイナスなら -）
String formatSignedSleepDuration(Duration duration) =>
    duration.isNegative ? formatSleepDuration(duration) : '+${formatSleepDuration(duration)}';
