// 次のシフトに合わせた睡眠プラン（A-2）
//
// 1/4：場面の分け方（SleepScene）と、寝方のタイプ（帰ってすぐ寝る／出勤ギリギリまで寝る）の決め方
// 2/4：次のシフト 1 回分の寝る・起きる目安（main。無料）と、夜勤前の仮眠（main が過ぎたとき。無料）
// 理由・3 日分・プレミアムの仮眠・文言・設定の保存は 3/4・4/4 で作る
// DB・アラームには依存しない
import 'package:flutter/material.dart' show TimeOfDay;
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

// ===== A-2 2/4：次のシフト 1 回分の目安 =====

/// D23：ベースラインに起床の円周平均がないときの、ふつうの起床（7:00。app_settings の wakeUpTime の既定と同じ）
const TimeOfDay defaultWakeTime = TimeOfDay(hour: 7, minute: 0);

/// D5：前置き（出勤前の分数）が 0（無効）のときの前置き
const Duration defaultLeadTime = Duration(minutes: 60);

/// S2・S3：夜勤明けの睡眠の長さ
const Duration afterNightSleepLength = Duration(hours: 4);

/// S4：日勤→夜勤の切り替えで、前夜の睡眠を遅らせる時間
const Duration dayToNightDelay = Duration(hours: 1);

/// S9：準夜勤前に、ふつうの起床より遅くしてよい上限
const Duration eveningWakeMaxDelay = Duration(hours: 1);

/// S1：夜勤前の仮眠の長さ
const Duration preNightNapLength = Duration(minutes: 90);

/// D18・D21：目安として出す睡眠の最短の長さ（これ未満なら出さない・過ぎたとする）
const Duration minPlanSleepLength = Duration(minutes: 30);

/// 目安の状態（now から見て）
enum SleepWindowStatus {
  /// これから（now < 寝る目安）
  upcoming,

  /// 中にいる（寝る目安 <= now < 起きる目安）
  ongoing,

  /// 過ぎた（起きる目安 <= now）
  past,
}

/// 寝る・起きる目安 1 回分
class SleepWindow {
  /// 寝る目安
  final DateTime sleepAt;

  /// 起きる目安
  final DateTime wakeAt;

  /// 予定の長さ（平均の睡眠時間・明けの 4 時間・仮眠の 90 分）より短い
  final bool shortened;

  /// now から見た状態
  final SleepWindowStatus status;

  /// 寝る目安を now・実際の入眠から数え直した（D16・D17。表示のときだけ 5 分単位に丸める。F4）
  final bool sleepAtRecounted;

  /// 起きる目安を数え直した寝る目安から数え直した（入眠で決まるもの。表示のときだけ 5 分単位に丸める。F4）
  final bool wakeAtRecounted;

  const SleepWindow({
    required this.sleepAt,
    required this.wakeAt,
    required this.shortened,
    required this.status,
    this.sleepAtRecounted = false,
    this.wakeAtRecounted = false,
  });

  /// 寝る目安から起きる目安までの長さ
  Duration get length => wakeAt.difference(sleepAt);

  @override
  String toString() => 'SleepWindow($sleepAt〜$wakeAt, shortened: $shortened, status: $status)';
}

/// 目安を出すための設定
class SleepPlanOptions {
  /// 出勤前アラームの分数（app_settings の alarmTimeBeforeShift。0 以下は無効）
  final int alarmMinutesBefore;

  /// 通勤の時間（A-4 で任意の設定にする予定）
  final Duration? commute;

  /// 身支度の時間（A-4 で任意の設定にする予定）
  final Duration? prep;

  const SleepPlanOptions({required this.alarmMinutesBefore, this.commute, this.prep});

  /// 前置き L（起きてから出勤までに要る時間）
  /// - 通勤・身支度のどちらかがあれば、その合計（ないほうは 0）
  /// - どちらもなければ出勤前アラームの分数（出勤前アラームと同じ時刻に起きる）。0 以下なら 60 分
  Duration get leadTime {
    if (commute != null || prep != null) return (commute ?? Duration.zero) + (prep ?? Duration.zero);
    return alarmMinutesBefore > 0 ? Duration(minutes: alarmMinutesBefore) : defaultLeadTime;
  }

  /// 帰る時間 H（勤務の終わりから寝られるまで）。通勤があればそれ、なければ前置き L（D20）
  Duration get homeTime => commute ?? leadTime;
}

/// 目安の理由（3/4。プレミアム。大事な順に並べる。文言は 4/4 で enum から作る）
enum SleepPlanReason {
  /// 起きる目安は「出勤 − 前置き」で、出勤前アラームと同じ時刻
  wakeForShift,

  /// 準夜勤の前は、ふだんより 1 時間まで遅く起きてもよい（S9）
  eveningLaterWake,

  /// 夜勤の前の夜は、ふだんどおりに寝る
  usualNight,

  /// 夜勤に体を寄せるため、前の夜を 1 時間遅くする（S4）
  delayedNight,

  /// 夜勤の前に 90 分の仮眠をとると、夜中の眠気が減る（S1）
  nightShiftNap,

  /// 帰ってすぐ寝るタイプなので、明けの直後に寝る（どこから決めたかは SleepPlan.styleSource）
  sleepRightAfter,

  /// 出勤ギリギリまで寝るタイプなので、出勤の前に起きる（同上）
  sleepUntilShift,

  /// 勤務の間が短いので、とれるだけ寝る。足りない分は次の休みで取り戻す
  shortGap,

  /// 明けは 4 時間ほどにして、夜に眠気が来るようにする（S2・S3）
  shortAfterNight,

  /// その夜はふだんどおりに寝ると、昼夜のリズムが戻りやすい（S2・S3）
  usualNightAfterNight,

  /// 前の勤務の終わりと帰る時間のぶん、寝る目安を後ろにずらした（D19）
  shiftedByPrevious,

  /// 記録が少ないので、7 時間・7:00 起きの既定で出している
  fewRecords,
}

/// 目安の睡眠の種類
enum PlannedSleepKind {
  /// 次のシフトに合わせたメインの睡眠（SleepPlan.main と同じ決め方）
  main,

  /// 夜勤前の 90 分の仮眠（開始 − L に終わる。S1・S4）
  preNightNap,

  /// 夜勤→日勤の明けの 4 時間（S3）
  afterNightSleep,

  /// 夜勤明け→休みの、その夜のふだんの睡眠（S2）
  followingNight,

  /// 3 日分で、勤務のない夜に足すふだんの睡眠（W − A 〜 W）
  usualNight,
}

/// 種類つきの寝る・起きる目安
class PlannedSleep {
  final PlannedSleepKind kind;
  final SleepWindow window;

  const PlannedSleep({required this.kind, required this.window});

  @override
  String toString() => 'PlannedSleep($kind, $window)';
}

/// 3 日分のうちの 1 日
class DayPlan {
  /// 日付（時刻なし）
  final DateTime date;

  /// その日に始まる勤務（開始の早い順）
  final List<WorkShift> shifts;

  /// その日の睡眠（入眠の早い順）。0:00〜4:59 に寝る睡眠は前日の夜として前日に入る（D33）
  final List<PlannedSleep> sleeps;

  const DayPlan({required this.date, required this.shifts, required this.sleeps});
}

/// 次のシフトに合わせた睡眠の目安
class SleepPlan {
  /// 場面
  final SleepScene scene;

  /// 前の勤務（now の 24 時間前〜now に終わった勤務。なければ null）
  final WorkShift? previous;

  /// 次の勤務（now から 48 時間以内に始まる勤務。夜勤明け→休みでは null）
  final WorkShift? next;

  /// 寝方のタイプと、どこから決めたか
  final SleepStyle style;
  final SleepStyleSource styleSource;

  /// 無料：次のシフト 1 回分の寝る・起きる目安（使える時間が 30 分未満なら null）
  final SleepWindow? main;

  /// 無料（D25 B）：main が過ぎていて、次が夜勤（夜勤前・日勤→夜勤）のときの出勤前の仮眠（90 分）
  /// extraSleeps の preNightNap のうち、無料で見せる分。両方あるときは同じ SleepWindow（同じ時刻・状態）
  final SleepWindow? preShiftNap;

  /// プレミアム：理由（大事な順。D26・D27）
  final List<SleepPlanReason> reasons;

  /// プレミアム：仮眠・明けの睡眠・その夜の睡眠（入眠の早い順。D30・D31）
  final List<PlannedSleep> extraSleeps;

  /// プレミアム：今日・明日・あさっての 3 日分（D32〜D35・D39）
  final List<DayPlan> days;

  /// D40：勤務中に開いたときの、その勤務（目安はこの勤務の終わりの時点で作る）。勤務中でなければ null
  final WorkShift? currentShift;

  const SleepPlan({
    required this.currentShift,
    required this.scene,
    required this.previous,
    required this.next,
    required this.style,
    required this.styleSource,
    required this.main,
    required this.preShiftNap,
    required this.reasons,
    required this.extraSleeps,
    required this.days,
  });
}

DateTime _atMinuteOfDay(DateTime day, int minuteOfDay) =>
    DateTime(day.year, day.month, day.day, minuteOfDay ~/ 60, minuteOfDay % 60);

/// limit 以前でいちばん遅い「その時刻」（limit ちょうどを含む）
DateTime _latestAtOrBefore(DateTime limit, int minuteOfDay) {
  final sameDay = _atMinuteOfDay(limit, minuteOfDay);
  if (!sameDay.isAfter(limit)) return sameDay;
  return _atMinuteOfDay(DateTime(limit.year, limit.month, limit.day - 1), minuteOfDay);
}

DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

SleepWindowStatus _statusOf(DateTime sleepAt, DateTime wakeAt, DateTime now) {
  if (now.isBefore(sleepAt)) return SleepWindowStatus.upcoming;
  if (now.isBefore(wakeAt)) return SleepWindowStatus.ongoing;
  return SleepWindowStatus.past;
}

/// 次のシフトに合わせた睡眠の目安を出す（勤務なしの場面なら null）
/// - 前置き L：SleepPlanOptions.leadTime、帰る時間 H：homeTime、平均 A：baseline.averageAsleep
/// - ふつうの起床 W：baseline.wakeTime（なければ 7:00）。ふつうの入眠は W − A
/// - 使える時間：前の勤務の終わり + H 〜 次の開始 − L
/// - 場面ごとの決め方：
///   日勤前・休み明け・夜勤→日勤（次が日勤）：起きる＝開始 − L、寝る＝起きる − A
///   準夜勤前：起きる＝その日の W + 1 時間と「開始 − L」の早いほう、寝る＝起きる − A
///   夜勤前：起きる＝「開始 − L」以前でいちばん遅い W、寝る＝起きる − A
///   日勤→夜勤：起きる＝「開始 − L」以前でいちばん遅い W + 1 時間、寝る＝起きる − A
///   連続夜勤・間が短い・夜勤→日勤（次が準夜勤）：帰ってすぐ寝る＝前の終わり + H から A、
///     出勤ギリギリまで寝る＝開始 − L に起きて A
///   夜勤明け→休み：前の終わり + H から 4 時間
/// - 共通の調整：寝るが「前の終わり + H」より前なら、そこまでずらして起きるも同じだけ遅くする（長さを保つ。D19）
///   起きるは「開始 − L」を超えない。予定の長さより短くなったら shortened
/// - 30 分未満になったら main は null（D21）
/// - now が中にいて寝ていない：寝るを now にする。入眠で決まる場面（帰ってすぐ寝る・明けの 4 時間）は
///   起きるも now から数え直す（使える時間の終わりまで）。残りが 30 分未満なら過ぎたとする（D16・D18）
/// - 寝ている（sleepingSince あり）で中にいる：寝るを実際の入眠にし、入眠で決まる場面は起きるも数え直す（D17）
/// - main が過ぎて、次が夜勤（夜勤前・日勤→夜勤）なら、extraSleeps の preNightNap と同じものを preShiftNap に入れる（D25 B）
/// - プレミアム（3/4）：理由（reasons）・仮眠など（extraSleeps）・3 日分（days）。画面で 🔒 にする（D10）
///   仮眠も、中にいるときは main と同じく寝る目安を now か実際の入眠にする（D37）
/// - 3 日分のため、呼び出し側は 5 日先までの勤務を渡す（3 日目の夜の次の勤務まで見るため）
/// - D40：勤務中（開始 <= now < 終わり）なら、その勤務の終わりの時点で場面と目安を作る（状態は now から見る）
///   その時点で勤務なしの場面なら null。勤務の終わりちょうどは勤務中に入らない
SleepPlan? buildSleepPlan({
  required DateTime now,
  required List<WorkShift> shifts,
  required SleepBaseline baseline,
  required SleepStylePreference preference,
  required SleepPlanOptions options,
  DateTime? sleepingSince,
}) {
  // D40：勤務中の勤務（複数あれば終わりがいちばん遅いもの）
  WorkShift? currentShift;
  for (final shift in shifts) {
    if (shift.startAt.isAfter(now) || !now.isBefore(shift.endAt)) continue;
    if (currentShift == null || shift.endAt.isAfter(currentShift.endAt)) currentShift = shift;
  }

  final core = _buildCore(
    planNow: currentShift?.endAt ?? now,
    statusNow: now,
    shifts: shifts,
    baseline: baseline,
    preference: preference,
    options: options,
    sleepingSince: sleepingSince,
  );
  if (core == null) return null;

  return SleepPlan(
    currentShift: currentShift,
    scene: core.scene,
    previous: core.previous,
    next: core.next,
    style: core.style,
    styleSource: core.styleSource,
    main: core.main,
    preShiftNap: core.preShiftNap,
    reasons: core.reasons,
    extraSleeps: core.extraSleeps,
    days: _buildDays(
      now: now,
      shifts: shifts,
      baseline: baseline,
      preference: preference,
      options: options,
      sleepingSince: sleepingSince,
      realCore: core,
    ),
  );
}

/// buildSleepPlan の中身（3 日分を除く）
class _PlanCore {
  final SleepScene scene;
  final WorkShift? previous;
  final WorkShift? next;
  final SleepStyle style;
  final SleepStyleSource styleSource;
  final SleepWindow? main;
  final SleepWindow? preShiftNap;
  final List<SleepPlanReason> reasons;
  final List<PlannedSleep> extraSleeps;

  const _PlanCore({
    required this.scene,
    required this.previous,
    required this.next,
    required this.style,
    required this.styleSource,
    required this.main,
    required this.preShiftNap,
    required this.reasons,
    required this.extraSleeps,
  });
}

/// 予定の寝る・起きるに、now から見た状態を付ける（30 分未満なら null）
/// - 中にいて寝ていない：寝るを now にする（D16）。寝ている：寝るを実際の入眠にする（D17）
/// - 入眠で決まるもの（sleepAnchored）は、起きるも寝るから数え直す（limit まで）
/// - 寝ていなくて残りが 30 分未満なら、予定の時刻のまま過ぎたとする（D18・D37）
SleepWindow? _settle({
  required DateTime sleepAt,
  required DateTime wakeAt,
  required Duration intended,
  required bool sleepAnchored,
  required DateTime? limit,
  required DateTime now,
  required DateTime? sleepingSince,
}) {
  if (wakeAt.difference(sleepAt) < minPlanSleepLength) return null;
  var start = sleepAt;
  var end = wakeAt;
  var status = _statusOf(start, end, now);
  var sleepAtRecounted = false;
  var wakeAtRecounted = false;
  if (status == SleepWindowStatus.ongoing) {
    final newStart = sleepingSince ?? now;
    var newEnd = end;
    if (sleepAnchored) {
      newEnd = newStart.add(intended);
      if (limit != null && newEnd.isAfter(limit)) newEnd = limit;
    }
    if (sleepingSince == null && newEnd.difference(now) < minPlanSleepLength) {
      status = SleepWindowStatus.past;
    } else {
      start = newStart;
      end = newEnd;
      status = now.isBefore(end) ? SleepWindowStatus.ongoing : SleepWindowStatus.past;
      sleepAtRecounted = true;
      wakeAtRecounted = sleepAnchored;
    }
  }
  return SleepWindow(
    sleepAt: start,
    wakeAt: end,
    shortened: end.difference(start) < intended,
    status: status,
    sleepAtRecounted: sleepAtRecounted,
    wakeAtRecounted: wakeAtRecounted,
  );
}

bool _overlaps(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) =>
    aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

/// planNow で場面と予定を決め、statusNow（本当の now）で状態を付ける（3 日分では planNow が勤務の終わり）
_PlanCore? _buildCore({
  required DateTime planNow,
  required DateTime statusNow,
  required List<WorkShift> shifts,
  required SleepBaseline baseline,
  required SleepStylePreference preference,
  required SleepPlanOptions options,
  required DateTime? sleepingSince,
}) {
  final now = planNow;
  final scene = classifySleepScene(now: now, shifts: shifts);
  if (scene == SleepScene.noShift) return null;

  final next = nextWorkShift(now, shifts);
  final previous = previousWorkShift(now, shifts, lookback: sleepScenePreviousLookback);
  final resolved = resolveSleepStyle(preference, baseline);
  final style = resolved.style;

  final average = baseline.averageAsleep;
  final wakeMinute = baseline.wakeTime?.minuteOfDay ?? defaultWakeTime.hour * 60 + defaultWakeTime.minute;
  final windowStart = previous?.endAt.add(options.homeTime);
  final windowEnd = next?.startAt.subtract(options.leadTime);

  // 場面ごとの予定（寝る・起きる）と、予定の長さ・入眠で決まるか
  late DateTime sleepAt;
  late DateTime wakeAt;
  var intended = average;
  var sleepAnchored = false;

  void fromWake(DateTime wake) {
    wakeAt = wake;
    sleepAt = wake.subtract(average);
  }

  void byStyle() {
    if (style == SleepStyle.immediate) {
      sleepAt = windowStart!;
      wakeAt = sleepAt.add(average);
      sleepAnchored = true;
    } else {
      fromWake(windowEnd!);
    }
  }

  switch (scene) {
    case SleepScene.beforeDay:
    case SleepScene.afterRest:
      fromWake(windowEnd!);
    case SleepScene.nightToDay:
      if (next!.kind == ShiftKind.evening) {
        byStyle();  // D22
      } else {
        fromWake(windowEnd!);
      }
    case SleepScene.beforeEvening:
      final delayed = _atMinuteOfDay(windowEnd!, (wakeMinute + eveningWakeMaxDelay.inMinutes) % (24 * 60));
      fromWake(_earlier(delayed, windowEnd));
    case SleepScene.beforeNight:
      fromWake(_latestAtOrBefore(windowEnd!, wakeMinute));
    case SleepScene.dayToNight:
      fromWake(_latestAtOrBefore(windowEnd!, (wakeMinute + dayToNightDelay.inMinutes) % (24 * 60)));
    case SleepScene.betweenNights:
    case SleepScene.quickReturn:
      byStyle();
    case SleepScene.nightToOff:
      sleepAt = windowStart!;
      wakeAt = sleepAt.add(afterNightSleepLength);
      intended = afterNightSleepLength;
      sleepAnchored = true;
    case SleepScene.noShift:
      return null;
  }

  // 共通の調整（D19）
  var shiftedByPrevious = false;
  if (windowStart != null && sleepAt.isBefore(windowStart)) {
    wakeAt = wakeAt.add(windowStart.difference(sleepAt));
    sleepAt = windowStart;
    shiftedByPrevious = true;
  }
  if (windowEnd != null && wakeAt.isAfter(windowEnd)) wakeAt = windowEnd;

  // 予定の main（状態を付ける前。仮眠などとの重なりを見るのに使う）
  final hasPlannedMain = wakeAt.difference(sleepAt) >= minPlanSleepLength;
  final plannedSleepAt = sleepAt;
  final plannedWakeAt = wakeAt;
  bool overlapsMain(DateTime start, DateTime end) =>
      hasPlannedMain && _overlaps(start, end, plannedSleepAt, plannedWakeAt);

  final main = _settle(
    sleepAt: sleepAt,
    wakeAt: wakeAt,
    intended: intended,
    sleepAnchored: sleepAnchored,
    limit: windowEnd,
    now: statusNow,
    sleepingSince: sleepingSince,
  );

  // 追加の睡眠（D29〜D31）
  final extras = <PlannedSleep>[];

  // 夜勤前の仮眠：夜勤前・日勤→夜勤・連続夜勤（帰ってすぐ寝るタイプ）。開始 − L に終わる 90 分
  // 前の勤務の終わり + H より前に始まる・main と重なるなら出さない
  SleepWindow? nap;
  final wantsNap = scene == SleepScene.beforeNight ||
      scene == SleepScene.dayToNight ||
      (scene == SleepScene.betweenNights && style == SleepStyle.immediate);
  if (wantsNap) {
    final napEnd = windowEnd!;
    final napStart = napEnd.subtract(preNightNapLength);
    final startsTooEarly = windowStart != null && napStart.isBefore(windowStart);
    // G1：D16・D17 で数え直した main とも重なるなら出さない（予定の main とは重ならなくても、伸びた main と重なることがある）
    final overlapsRecountedMain = main != null &&
        (main.sleepAtRecounted || main.wakeAtRecounted) &&
        _overlaps(napStart, napEnd, main.sleepAt, main.wakeAt);
    if (!startsTooEarly && !overlapsMain(napStart, napEnd) && !overlapsRecountedMain) {
      nap = _settle(
        sleepAt: napStart,
        wakeAt: napEnd,
        intended: preNightNapLength,
        sleepAnchored: false,
        limit: windowEnd,
        now: statusNow,
        sleepingSince: sleepingSince,
      );
      if (nap != null) extras.add(PlannedSleep(kind: PlannedSleepKind.preNightNap, window: nap));
    }
  }

  // 夜勤→日勤（次が日勤）：明けの 4 時間。main（日勤前の夜）より前に終わる
  if (scene == SleepScene.nightToDay && next!.kind != ShiftKind.evening) {
    final start = windowStart!;
    var end = start.add(afterNightSleepLength);
    final limit = hasPlannedMain && plannedSleepAt.isBefore(windowEnd!) ? plannedSleepAt : windowEnd!;
    if (end.isAfter(limit)) end = limit;
    final window = _settle(
      sleepAt: start,
      wakeAt: end,
      intended: afterNightSleepLength,
      sleepAnchored: true,
      limit: limit,
      now: statusNow,
      sleepingSince: sleepingSince,
    );
    if (window != null) extras.add(PlannedSleep(kind: PlannedSleepKind.afterNightSleep, window: window));
  }

  // 夜勤明け→休み：明けの日の夜をふだんどおり（W − A 〜 翌日の W）
  if (scene == SleepScene.nightToOff) {
    final endDay = previous!.endAt;
    final wake = _atMinuteOfDay(DateTime(endDay.year, endDay.month, endDay.day + 1), wakeMinute);
    final start = wake.subtract(average);
    if (!overlapsMain(start, wake) && (!hasPlannedMain || !start.isBefore(plannedWakeAt))) {
      final window = _settle(
        sleepAt: start,
        wakeAt: wake,
        intended: average,
        sleepAnchored: false,
        limit: null,
        now: statusNow,
        sleepingSince: sleepingSince,
      );
      if (window != null) extras.add(PlannedSleep(kind: PlannedSleepKind.followingNight, window: window));
    }
  }
  extras.sort((a, b) => a.window.sleepAt.compareTo(b.window.sleepAt));

  // D25 B：夜勤前・日勤→夜勤で main が過ぎたら、仮眠（extraSleeps の preNightNap と同じもの）を無料で見せる
  final preShiftNap = main?.status == SleepWindowStatus.past &&
          (scene == SleepScene.beforeNight || scene == SleepScene.dayToNight)
      ? nap
      : null;

  // 理由（D26・D27：大事な順にすべて）
  final styleReason = style == SleepStyle.immediate ? SleepPlanReason.sleepRightAfter : SleepPlanReason.sleepUntilShift;
  final reasons = <SleepPlanReason>[];
  switch (scene) {
    case SleepScene.beforeDay:
    case SleepScene.afterRest:
      reasons.add(SleepPlanReason.wakeForShift);
      if (shiftedByPrevious) reasons.add(SleepPlanReason.shiftedByPrevious);
    case SleepScene.beforeEvening:
      reasons.add(SleepPlanReason.eveningLaterWake);
      if (shiftedByPrevious) reasons.add(SleepPlanReason.shiftedByPrevious);
    case SleepScene.beforeNight:
      reasons.add(SleepPlanReason.usualNight);
      if (nap != null) reasons.add(SleepPlanReason.nightShiftNap);  // G1：仮眠が出るときだけ
    case SleepScene.dayToNight:
      reasons.add(SleepPlanReason.delayedNight);
      if (nap != null) reasons.add(SleepPlanReason.nightShiftNap);  // G1：仮眠が出るときだけ
      if (shiftedByPrevious) reasons.add(SleepPlanReason.shiftedByPrevious);
    case SleepScene.betweenNights:
      reasons.add(styleReason);
      if (nap != null) reasons.add(SleepPlanReason.nightShiftNap);
    case SleepScene.quickReturn:
      reasons.addAll([SleepPlanReason.shortGap, styleReason]);
    case SleepScene.nightToOff:
      reasons.addAll([SleepPlanReason.shortAfterNight, SleepPlanReason.usualNightAfterNight]);
    case SleepScene.nightToDay:
      reasons.addAll([SleepPlanReason.shortAfterNight, SleepPlanReason.usualNightAfterNight]);
      if (next!.kind == ShiftKind.evening) reasons.add(styleReason);
    case SleepScene.noShift:
      break;
  }
  if (baseline.usedDefault || baseline.wakeTime == null) reasons.add(SleepPlanReason.fewRecords);

  return _PlanCore(
    scene: scene,
    previous: previous,
    next: next,
    style: style,
    styleSource: resolved.source,
    main: main,
    preShiftNap: preShiftNap,
    reasons: reasons,
    extraSleeps: extras,
  );
}

/// 3 日分（今日・明日・あさって）を作る（D32〜D35・D39）
/// - 本当の now（勤務中ならその勤務の終わり。D40）と、範囲の中の勤務の終わりの時点ごとに _buildCore を呼び、main と追加の睡眠を集める
///   （先に集めたものと重なるものは足さない）
/// - 勤務のない夜には、ふだんの夜（W − A 〜 翌日の W）を足す。集めた睡眠や、勤務（開始 − L 〜 終わり + H）と重なれば足さない
/// - 入眠 − 5:00 の日の欄に入れる（0:00〜4:59 に寝る睡眠は前日の夜。D33）。状態は本当の now から見たもの
List<DayPlan> _buildDays({
  required DateTime now,
  required List<WorkShift> shifts,
  required SleepBaseline baseline,
  required SleepStylePreference preference,
  required SleepPlanOptions options,
  required DateTime? sleepingSince,
  required _PlanCore realCore,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final dates = [for (var i = 0; i < 3; i++) DateTime(today.year, today.month, today.day + i)];
  final horizonEnd = DateTime(today.year, today.month, today.day + 3);
  final collected = <PlannedSleep>[];

  bool overlapsCollected(DateTime start, DateTime end) =>
      collected.any((s) => _overlaps(start, end, s.window.sleepAt, s.window.wakeAt));

  void addFrom(_PlanCore? core) {
    if (core == null) return;
    final main = core.main;
    for (final sleep in [
      if (main != null) PlannedSleep(kind: PlannedSleepKind.main, window: main),
      ...core.extraSleeps,
    ]) {
      if (!overlapsCollected(sleep.window.sleepAt, sleep.window.wakeAt)) collected.add(sleep);
    }
  }

  // 勤務中なら realCore は勤務の終わりの時点で作ったもの（D40）。下の同じ時点のものとは重なるので二重にならない
  addFrom(realCore);

  final ends = {
    for (final shift in shifts)
      if (shift.endAt.isAfter(now) && shift.startAt.isBefore(horizonEnd)) shift.endAt,
  }.toList()
    ..sort();
  for (final end in ends) {
    addFrom(_buildCore(
      planNow: end,
      statusNow: now,
      shifts: shifts,
      baseline: baseline,
      preference: preference,
      options: options,
      sleepingSince: sleepingSince,
    ));
  }

  // 勤務のない夜（D34）
  final average = baseline.averageAsleep;
  final wakeMinute = baseline.wakeTime?.minuteOfDay ?? defaultWakeTime.hour * 60 + defaultWakeTime.minute;
  bool blockedByShift(DateTime start, DateTime end) => shifts.any((s) => _overlaps(
        start,
        end,
        s.startAt.subtract(options.leadTime),
        s.endAt.add(options.homeTime),
      ));
  for (final date in dates) {
    final wake = _atMinuteOfDay(DateTime(date.year, date.month, date.day + 1), wakeMinute);
    final start = wake.subtract(average);
    if (overlapsCollected(start, wake) || blockedByShift(start, wake)) continue;
    final window = _settle(
      sleepAt: start,
      wakeAt: wake,
      intended: average,
      sleepAnchored: false,
      limit: null,
      now: now,
      sleepingSince: sleepingSince,
    );
    if (window != null) collected.add(PlannedSleep(kind: PlannedSleepKind.usualNight, window: window));
  }

  final boundary = Duration(hours: nextDayStartBoundary.hour, minutes: nextDayStartBoundary.minute);
  DateTime dayOf(DateTime sleepAt) {
    final shifted = sleepAt.subtract(boundary);
    return DateTime(shifted.year, shifted.month, shifted.day);
  }

  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  return [
    for (final date in dates)
      DayPlan(
        date: date,
        shifts: shifts.where((s) => sameDay(s.startAt, date)).toList()
          ..sort((a, b) => a.startAt.compareTo(b.startAt)),
        sleeps: collected.where((s) => sameDay(dayOf(s.window.sleepAt), date)).toList()
          ..sort((a, b) => a.window.sleepAt.compareTo(b.window.sleepAt)),
      ),
  ];
}
