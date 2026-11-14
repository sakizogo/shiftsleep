// ホームの睡眠プランのカードの表示の形（A-3 1/3）
//
// 読んだもの（SleepPlanInputs）＋睡眠記録＋now＋プレミアムかどうか＋advicePromoVisible＋sleepingSince から、
// ベースライン → プラン → 文言 → 表示の形を作る純粋な関数
// - 無料：プレミアムの部分（理由・追加の睡眠・3 日分）は中身を入れない（D60）。🔒 の案内は advicePromoVisible のときだけ
// - ⚠️ の行：設定を読めなかった（30 分で計算。D61）、睡眠記録を読めなかった（7 時間で計算。D63）
// - 記録が少ない行は無料にも出す（D70）
// DB・画面には依存しない
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/sleep_baseline.dart';
import 'package:shiftsleep/services/sleep_plan.dart';
import 'package:shiftsleep/services/sleep_plan_loader.dart';
import 'package:shiftsleep/services/sleep_plan_text.dart';

/// カードの状態
enum SleepPlanCardState {
  /// 目安を出す
  ready,

  /// 48 時間以内に勤務がない（1 行の小さなカード。D65）
  noShift,

  /// 勤務・パターンを読めなかった（目安は出さず ⚠️ と［再読み込み］。D62）
  failed,
}

/// 勤務・パターンを読めなかったときの文
const String sleepPlanShiftsFailedText = '⚠️ シフトを読み込めなかったため、目安を出せません';

/// 設定を読めなかったときの文
const String sleepPlanSettingsFailedText = '⚠️ 設定を読めなかったため、出勤 $defaultAlarmMinutesBefore 分前で計算しています';

/// 睡眠記録を読めなかったときの文
const String sleepPlanRecordsFailedText = '⚠️ 睡眠の記録を読めなかったため、7 時間の目安です';

/// 記録が少ないときの文（D70）
const String sleepPlanFewRecordsText = 'ℹ️ 記録がまだ少ないため、7 時間・7:00 起きで出しています';

/// 🔒 の案内の文（D60）
const String sleepPlanPremiumTeaserText = '理由・仮眠・3 日分の目安が見られます';

/// カードの表示の形
class SleepPlanCardModel {
  final SleepPlanCardState state;

  /// 文言（failed のときは null）。プレミアムの部分は下の premium* を使う
  final SleepPlanText? text;

  /// プラン（ready のときだけ）
  final SleepPlan? plan;

  /// ⚠️ の行（失敗の知らせ。failed のときは sleepPlanShiftsFailedText）
  final List<String> warnings;

  /// 記録が少ない行（ready で記録が少ないときだけ）
  final String? fewRecordsLine;

  /// 勤務中に開いた（目安はその勤務の終わりの時点。D40）
  final bool inShift;

  /// 無料なのでプレミアムの部分を見せない
  final bool premiumLocked;

  /// 🔒 の案内を出す（無料・advicePromoVisible・ready のとき）
  final bool showPremiumTeaser;

  /// プレミアム：理由の文（無料なら空）
  final List<String> premiumReasonLines;

  /// プレミアム：仮眠・明けの睡眠・その夜の行（無料なら空）
  final List<String> premiumExtraLines;

  /// プレミアム：3 日分（無料なら空）
  final List<SleepDayText> premiumDays;

  const SleepPlanCardModel({
    required this.state,
    required this.text,
    required this.plan,
    required this.warnings,
    required this.fewRecordsLine,
    required this.inShift,
    required this.premiumLocked,
    required this.showPremiumTeaser,
    required this.premiumReasonLines,
    required this.premiumExtraLines,
    required this.premiumDays,
  });
}

/// カードの表示の形を作る
/// - recordsFailed：SleepProvider で睡眠記録を読めなかった（記録は使わず 7 時間で計算する）
/// - sleepingSince：記録中の入眠時刻（SleepProvider.sleepStartTime。D66）
SleepPlanCardModel buildSleepPlanCardModel({
  required SleepPlanInputs inputs,
  required List<SleepRecord> records,
  required bool recordsFailed,
  required DateTime now,
  required bool isPremium,
  required bool advicePromoVisible,
  DateTime? sleepingSince,
}) {
  final shifts = inputs.shifts;
  if (shifts == null) {
    return SleepPlanCardModel(
      state: SleepPlanCardState.failed,
      text: null,
      plan: null,
      warnings: const [sleepPlanShiftsFailedText],
      fewRecordsLine: null,
      inShift: false,
      premiumLocked: !isPremium,
      showPremiumTeaser: false,
      premiumReasonLines: const [],
      premiumExtraLines: const [],
      premiumDays: const [],
    );
  }

  final baseline = computeSleepBaseline(
    records: recordsFailed ? const [] : records,
    shifts: shifts,
    now: now,
  );
  final plan = buildSleepPlan(
    now: now,
    shifts: shifts,
    baseline: baseline,
    preference: inputs.preference,
    options: SleepPlanOptions(alarmMinutesBefore: inputs.alarmMinutesBefore),
    sleepingSince: sleepingSince,
  );
  final text = sleepPlanText(plan, now: now, sleeping: sleepingSince != null);

  final warnings = [
    if (inputs.settingsFailed) sleepPlanSettingsFailedText,
    if (recordsFailed) sleepPlanRecordsFailedText,
  ];

  if (plan == null) {
    return SleepPlanCardModel(
      state: SleepPlanCardState.noShift,
      text: text,
      plan: null,
      warnings: warnings,
      fewRecordsLine: null,
      inShift: false,
      premiumLocked: !isPremium,
      showPremiumTeaser: false,
      premiumReasonLines: const [],
      premiumExtraLines: const [],
      premiumDays: const [],
    );
  }

  final fewRecords = !recordsFailed && (baseline.usedDefault || baseline.wakeTime == null);
  return SleepPlanCardModel(
    state: SleepPlanCardState.ready,
    text: text,
    plan: plan,
    warnings: warnings,
    fewRecordsLine: fewRecords ? sleepPlanFewRecordsText : null,
    inShift: plan.currentShift != null,
    premiumLocked: !isPremium,
    showPremiumTeaser: !isPremium && advicePromoVisible,
    premiumReasonLines: isPremium ? text.reasonLines : const [],
    premiumExtraLines: isPremium ? text.extraLines : const [],
    premiumDays: isPremium ? text.days : const [],
  );
}
