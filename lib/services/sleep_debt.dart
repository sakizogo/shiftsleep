// N198：睡眠負債（直近 4 週間の 1 日平均の不足）
// - 1 日ごと（起床の日付）の合計は recentDailySleepTotals（メイン＋昼寝。記録中は除く。記録のない日は数えない）
// - 1 日ごとに「合計 − 目標（7 時間）」を出す。寝すぎた日の余りは +1 時間までしか差し引かない（取り戻せる量には限りがあるため）
// - 記録のある日が 7 日未満なら計算しない（null）
// - しきい値は N202（医師への相談のすすめ）でも使う
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/sleep_record_kind.dart';

/// 1 日の睡眠の目標
const Duration sleepDebtTarget = Duration(hours: 7);

/// 寝すぎた日の余りを差し引く上限（1 日あたり。ちょうどはそのまま）
const Duration sleepDebtSurplusCap = Duration(hours: 1);

/// 判定に必要な、記録のある日の数（ちょうどを含む）
const int sleepDebtMinDays = 7;

/// 1 日平均の不足がこれ以上なら「改善推奨」（ちょうどを含む）
const Duration sleepDebtImproveShortage = Duration(minutes: 30);

/// 1 日平均の不足がこれ以上なら「要注意」（ちょうどを含む）
const Duration sleepDebtAlertShortage = Duration(minutes: 60);

/// 1 日平均の睡眠がこれより短ければ、国の睡眠ガイドの目安（6 時間以上）の一言を出す
const Duration nationalGuideMinAverage = Duration(hours: 6);

/// 睡眠負債の評価の段階
enum SleepDebtLevel {
  /// 計算できない（記録のある日が足りない）
  notJudgeable,

  /// 不足なし（1 日平均の不足が 1 分未満）
  enough,

  /// 少し不足（1〜29 分）
  slight,

  /// 改善推奨（30〜59 分）
  improve,

  /// 要注意（60 分以上）
  alert,
}

/// 直近 4 週間の睡眠負債
class SleepDebtSummary {
  /// 記録のある日の数
  final int days;

  /// 1 日平均の睡眠（averageDailySleep と同じ）
  final Duration averageSleep;

  /// 上限なしの合計（Σ（合計 − 目標）。ログ用）
  final Duration rawTotal;

  /// 上限ありの合計（余りは 1 日 +1 時間まで。ログ用）
  final Duration cappedTotal;

  const SleepDebtSummary({
    required this.days,
    required this.averageSleep,
    required this.rawTotal,
    required this.cappedTotal,
  });

  /// 1 日平均の差（上限あり。マイナスが不足）。画面に大きく出す値
  Duration get dailyBalance => cappedTotal ~/ days;

  /// 1 日平均の差（上限なし）＝ 1 日平均 − 目標（画面の「1日平均」と「目標」から読める値）
  Duration get rawDailyBalance => averageSleep - sleepDebtTarget;

  /// 1 日平均の不足（不足がなければ 0）
  Duration get shortage => dailyBalance.isNegative ? -dailyBalance : Duration.zero;

  /// 評価の段階（不足は分の切り捨てで比べる）
  SleepDebtLevel get level {
    final minutes = shortage.inMinutes;
    if (minutes >= sleepDebtAlertShortage.inMinutes) return SleepDebtLevel.alert;
    if (minutes >= sleepDebtImproveShortage.inMinutes) return SleepDebtLevel.improve;
    if (minutes >= 1) return SleepDebtLevel.slight;
    return SleepDebtLevel.enough;
  }

  /// 上限のために、大きい数字と「1日平均 − 目標」の表示が違うか（「※」の一言を出すか）
  bool get showsSurplusCapNote =>
      formatSignedSleepDuration(dailyBalance) != formatSignedSleepDuration(rawDailyBalance);

  /// 1 日平均が国の睡眠ガイドの目安（6 時間以上）より短いか
  bool get belowNationalGuide => averageSleep < nationalGuideMinAverage;

  @override
  String toString() => 'SleepDebtSummary(days: $days, averageSleep: $averageSleep, '
      'rawTotal: $rawTotal, cappedTotal: $cappedTotal)';
}

/// 日ごとの合計から睡眠負債を出す。記録のある日が minDays 未満なら null
SleepDebtSummary? summarizeSleepDebt(
  Map<DateTime, Duration> totals, {
  int minDays = sleepDebtMinDays,
}) {
  if (totals.isEmpty || totals.length < minDays) return null;
  var rawTotal = Duration.zero;
  var cappedTotal = Duration.zero;
  for (final total in totals.values) {
    final diff = total - sleepDebtTarget;
    rawTotal += diff;
    cappedTotal += diff > sleepDebtSurplusCap ? sleepDebtSurplusCap : diff;
  }
  return SleepDebtSummary(
    days: totals.length,
    averageSleep: averageDailySleep(totals)!,
    rawTotal: rawTotal,
    cappedTotal: cappedTotal,
  );
}

/// 直近 4 週間（today − 27 〜 today）の睡眠負債。記録のある日が 7 日未満なら null
SleepDebtSummary? recentSleepDebt(Iterable<SleepRecord> records, DateTime now) =>
    summarizeSleepDebt(recentDailySleepTotals(records, now));

/// N202：医師への相談をすすめるのに見る週の数（今日を含む 7 日・その前の 7 日）
const int medicalConsultWeeks = 2;

/// N202：1 週ごとに判定に必要な、記録のある日の数（ちょうどを含む）
const int medicalConsultMinDaysPerWeek = 4;

/// N202：直近 2 週を 1 週ずつ（today − 6 〜 today、today − 13 〜 today − 7）summarizeSleepDebt で判定し、
/// 両方の週とも「要注意」（1 日平均の不足 60 分以上）なら true
/// - 記録のある日が 4 日未満の週があれば false（出さない）
/// - SRI・SJL は見ない（交代勤務では構造的に悪い値が出るため）
bool shouldSuggestMedicalConsult(Iterable<SleepRecord> records, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  for (var week = 0; week < medicalConsultWeeks; week++) {
    final lastDay = DateTime(today.year, today.month, today.day - 7 * week);
    final firstDay = DateTime(lastDay.year, lastDay.month, lastDay.day - 6);
    final summary = summarizeSleepDebt(
      dailySleepTotals(records, firstDay: firstDay, lastDay: lastDay),
      minDays: medicalConsultMinDaysPerWeek,
    );
    if (summary == null || summary.level != SleepDebtLevel.alert) return false;
  }
  return true;
}

/// 評価の文言
String sleepDebtEvaluationText(SleepDebtLevel level) {
  switch (level) {
    case SleepDebtLevel.notJudgeable:
      return '判定できません';
    case SleepDebtLevel.enough:
      return '十分睡眠が取れています';
    case SleepDebtLevel.slight:
      return '少し不足（30分未満）';
    case SleepDebtLevel.improve:
      return '改善推奨（1日平均30分以上の不足）';
    case SleepDebtLevel.alert:
      return '要注意（1日平均60分以上の不足）';
  }
}

/// 大きく出す 1 日平均の差（例：-1h 5m／日、+0h 40m／日）
String formatDailySleepDebt(Duration dailyBalance) => '${formatSignedSleepDuration(dailyBalance)}／日';

/// 国の睡眠ガイドの一言（1 日平均が 6 時間未満のときだけ、睡眠負債のアドバイスの文に入れる）
String nationalGuideNote(Duration averageSleep) =>
    '直近4週間の1日平均は${formatSleepDuration(averageSleep)}で、国の睡眠ガイドが目安とする「6時間以上」より短めです。'
    '必要な睡眠時間には個人差があります。眠りたくても眠れない日が続くときは、無理をせず休める時間を少しずつ確保してみてください。';
