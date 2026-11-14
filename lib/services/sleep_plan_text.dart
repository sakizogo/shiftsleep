// 次のシフトに合わせた睡眠プランの文言（A-2 4/4）
//
// 決まり：言い切らない（「目安」「ごろ」）・どの場面にも「眠れなくても大丈夫」の一言・責めない／急かさない
// - 時刻は、その睡眠が属する夜の日（入眠 − 5:00 の日）を基準に書き、次の日の時刻は「翌 0:30」（D41）
//   ただし日の呼び方が夜（今夜など）の行では、次の日の 0:00〜4:59 は同じ夜なので「翌」を付けない（D71）
// - 日の呼び方は入眠の時刻で分ける。5:00〜17:59 は「今日／明日／11/19（木）」、
//   18:00〜4:59 は「今夜／明日の夜／11/19（木）の夜」（D52・D53）
// - 「あと何時間」は出さない（D44）
// - 無料（見出し〜タイプ）とプレミアム（理由・追加の睡眠・3 日分）を分けて返し、画面で 🔒 にする（D46）
// DB・アラームには依存しない
import 'package:shiftsleep/services/next_shift.dart';
import 'package:shiftsleep/services/sleep_plan.dart';

/// 眠れなくても大丈夫の一言：短い・まとまった睡眠がとれないとき
const String sleepReassuranceRest = '眠れなくても、横になって目を閉じるだけで体は休まります。';

/// 眠れなくても大丈夫の一言：ふだん
const String sleepReassuranceEnough = '目安どおりに眠れなくても大丈夫です。できる範囲で十分です。';

/// 眠れなくても大丈夫の一言：目安の時間が終わったとき
const String sleepReassuranceNext = '眠れない日があっても大丈夫。次の目安で少しずつ整えていけます。';

const List<String> _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

/// 1 日分の文言（3 日分。プレミアム）
class SleepDayText {
  /// 「今日 11/17（火）」など
  final String title;

  /// 勤務と睡眠の行（時刻の早い順）
  final List<String> lines;

  const SleepDayText({required this.title, required this.lines});
}

/// 睡眠プランの文言
class SleepPlanText {
  /// 無料：見出し
  final String headline;

  /// 無料：副題（次の勤務など）
  final String? subline;

  /// 無料：main の行（main がなければ null）
  final String? mainLine;

  /// 無料：夜勤前で main が終わったときの仮眠の行（D25 B）
  final String? freeNapLine;

  /// 無料：状態の文（勤務中・中にいる・終わった・短め・目安が出せない）
  final List<String> statusLines;

  /// 無料：眠れなくても大丈夫の一言（D43）
  final String reassurance;

  /// 無料：寝方のタイプがどこから決まったか（タイプで目安が変わる場面だけ。D45）
  final String? styleNote;

  /// プレミアム：理由の文（大事な順）
  final List<String> reasonLines;

  /// プレミアム：仮眠・明けの睡眠・その夜の行
  final List<String> extraLines;

  /// プレミアム：3 日分
  final List<SleepDayText> days;

  const SleepPlanText({
    required this.headline,
    required this.subline,
    required this.mainLine,
    required this.freeNapLine,
    required this.statusLines,
    required this.reassurance,
    required this.styleNote,
    required this.reasonLines,
    required this.extraLines,
    required this.days,
  });

  /// すべての文（テストで言い方を確かめるため）
  List<String> get allTexts => [
        headline,
        if (subline != null) subline!,
        if (mainLine != null) mainLine!,
        if (freeNapLine != null) freeNapLine!,
        ...statusLines,
        reassurance,
        if (styleNote != null) styleNote!,
        ...reasonLines,
        ...extraLines,
        for (final day in days) ...[day.title, ...day.lines],
      ];
}

DateTime _date(DateTime time) => DateTime(time.year, time.month, time.day);

/// その時刻が属する夜の日（5:00 より前は前日）
DateTime _nightKey(DateTime time) =>
    _date(time.subtract(Duration(hours: nextDayStartBoundary.hour, minutes: nextDayStartBoundary.minute)));

int _daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// 「8:00」（時は 0 埋めなし、分は 2 桁）
String planTimeOfDay(DateTime time) => '${time.hour}:${time.minute.toString().padLeft(2, '0')}';

/// 「11/19（木）」
String planMonthDay(DateTime date) => '${date.month}/${date.day}（${_weekdays[date.weekday - 1]}）';

/// D41：baseDate の日の時刻はそのまま、次の日は「翌 0:30」、それ以外は「11/19（木） 0:30」
/// D71：sameNight（日の呼び方が「今夜／明日の夜／〇〇の夜」）なら、次の日の 0:00〜4:59 は同じ夜なので「翌」を付けない
///   （「今夜 寝る目安 0:00 ごろ → 起きる目安 翌 7:00 ごろ」。5:00 以降の次の日の時刻には「翌」を付ける）
String planTime(DateTime time, {required DateTime baseDate, bool sameNight = false}) {
  final diff = _daysBetween(baseDate, time);
  if (diff == 0) return planTimeOfDay(time);
  if (diff == 1) {
    if (sameNight && time.hour < nextDayStartBoundary.hour) return planTimeOfDay(time);
    return '翌 ${planTimeOfDay(time)}';
  }
  return '${planMonthDay(_date(time))} ${planTimeOfDay(time)}';
}

/// 18:00〜4:59 に始まるものは夜（D53）
bool _isNightStart(DateTime start) => start.hour >= 18 || start.hour < nextDayStartBoundary.hour;

/// D52・D53：日の呼び方。18:00〜4:59 に始まるものは夜（今夜／明日の夜／11/19（木）の夜）
String planDayLabel(DateTime start, {required DateTime now}) {
  final night = _isNightStart(start);
  final diff = _daysBetween(_nightKey(now), _nightKey(start));
  if (diff == 0) return night ? '今夜' : '今日';
  if (diff == 1) return night ? '明日の夜' : '明日';
  final date = planMonthDay(_nightKey(start));
  return night ? '$dateの夜' : date;
}

/// D51：「7 時間」「6 時間 30 分」「90 分」（2 時間未満で端数があれば分だけ）
String planDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  if (hours == 0 || (hours == 1 && minutes != 0)) return '${duration.inMinutes} 分';
  if (minutes == 0) return '$hours 時間';
  return '$hours 時間 $minutes 分';
}

/// 場面の見出し
String sleepSceneHeadline(SleepScene scene) {
  switch (scene) {
    case SleepScene.beforeDay:
      return '次の日勤に向けた目安';
    case SleepScene.afterRest:
      return '休み明けの日勤に向けた目安';
    case SleepScene.beforeEvening:
      return '準夜勤の前の目安';
    case SleepScene.beforeNight:
      return '夜勤の前の目安';
    case SleepScene.dayToNight:
      return '日勤から夜勤への切り替えの目安';
    case SleepScene.betweenNights:
      return '夜勤と夜勤のあいだの目安';
    case SleepScene.quickReturn:
      return '勤務の間が短い日の目安';
    case SleepScene.nightToOff:
      return '夜勤明けの目安';
    case SleepScene.nightToDay:
      return '夜勤から日勤への切り替えの目安';
    case SleepScene.noShift:
      return 'この 2 日は勤務がありません';
  }
}

/// 理由の文
String sleepPlanReasonText(SleepPlanReason reason) {
  switch (reason) {
    case SleepPlanReason.wakeForShift:
      return '起きる目安は、出勤の時刻から準備の時間を引いたものです。出勤前アラームと同じ時刻にしています。';
    case SleepPlanReason.eveningLaterWake:
      return '準夜勤の日は帰りが遅くなるので、朝はいつもより 1 時間ほどゆっくりでも大丈夫です。';
    case SleepPlanReason.usualNight:
      return '夜勤の前の夜は、いつもどおりの時間に眠れれば十分です。';
    case SleepPlanReason.delayedNight:
      return '夜勤に向けて前の夜を 1 時間ほど遅めにすると、体が夜に向きやすくなります。';
    case SleepPlanReason.nightShiftNap:
      return '夜勤の前に 90 分ほど仮眠をとると、夜中の眠気がやわらぐことがあります。横になるだけでも休めます。';
    case SleepPlanReason.sleepRightAfter:
      return '帰ってすぐ眠るタイプに合わせています。起きたあとは、出勤まで自分や家族の時間にあてられます。';
    case SleepPlanReason.sleepUntilShift:
      return '出勤ぎりぎりまで眠るタイプに合わせています。起きてから出勤までが短いので、夜勤の終わりごろの眠気が少ないと感じる人もいます。';
    case SleepPlanReason.shortGap:
      return '勤務と勤務の間が短い日です。とれるだけ眠れれば十分で、足りない分は、できるときに少しずつで大丈夫です。';
    case SleepPlanReason.shortAfterNight:
      return '明けの睡眠を 4 時間ほどにしておくと、夜に眠気が来やすくなります。';
    case SleepPlanReason.usualNightAfterNight:
      return 'その夜にいつもの時間に眠れると、昼と夜のリズムが戻りやすくなります。';
    case SleepPlanReason.shiftedByPrevious:
      return '前の勤務の終わりと帰りの時間をふまえて、寝る目安を少し遅らせています。';
    case SleepPlanReason.fewRecords:
      return '睡眠の記録がまだ少ないため、7 時間・7:00 起きの目安で出しています。記録が増えると、ふだんの睡眠に合わせた目安になります。';
  }
}

/// 寝方のタイプの名前
String sleepStyleName(SleepStyle style) =>
    style == SleepStyle.immediate ? '帰ってすぐ寝る' : '出勤ぎりぎりまで寝る';

/// 寝方のタイプがどこから決まったか（既定のときは「設定で変えられます」を添える）
String sleepStyleNote(SleepStyle style, SleepStyleSource source) {
  final from = switch (source) {
    SleepStyleSource.setting => '設定から',
    SleepStyleSource.records => 'これまでの記録から',
    SleepStyleSource.fallback => '記録がまだ少ないため。設定で変えられます',
  };
  return '寝方のタイプ：${sleepStyleName(style)}（$from）';
}

String _sleepKindName(PlannedSleepKind kind) {
  switch (kind) {
    case PlannedSleepKind.main:
      return '睡眠の目安';
    case PlannedSleepKind.preNightNap:
      return '仮眠の目安';
    case PlannedSleepKind.afterNightSleep:
      return '明けの睡眠の目安';
    case PlannedSleepKind.followingNight:
      return 'その夜の目安';
    case PlannedSleepKind.usualNight:
      return 'ふだんの睡眠の目安';
  }
}

/// main の書き方：「寝る目安 23:00 ごろ → 起きる目安 翌 6:00 ごろ（7 時間）」
/// sameNight：日の呼び方が夜のとき（D71。0:00〜4:59 に「翌」を付けない）
String _mainWindowText(SleepWindow window, DateTime baseDate, {bool sameNight = false}) {
  final start = _shownSleepAt(window);
  final end = _shownWakeAt(window);
  return '寝る目安 ${planTime(start, baseDate: baseDate, sameNight: sameNight)} ごろ → '
      '起きる目安 ${planTime(end, baseDate: baseDate, sameNight: sameNight)} ごろ（${planDuration(end.difference(start))}）';
}

/// 追加の睡眠の書き方：「仮眠の目安 17:30〜19:00 ごろ（90 分ほど）」（「ごろ」は最後に 1 回）
/// F3：始まりと終わりが同じ日で、始まりが基準の日より後なら、終わりには「翌」や日付を付けない（「翌 0:00〜7:00 ごろ」）
String _extraWindowText(PlannedSleepKind kind, SleepWindow window, DateTime baseDate, {bool sameNight = false}) {
  final start = _shownSleepAt(window);
  final end = _shownWakeAt(window);
  final sameDay = _daysBetween(start, end) == 0;
  final endText = sameDay && _daysBetween(baseDate, start) >= 1
      ? planTimeOfDay(end)
      : planTime(end, baseDate: baseDate, sameNight: sameNight);
  return '${_sleepKindName(kind)} ${planTime(start, baseDate: baseDate, sameNight: sameNight)}〜'
      '$endText ごろ（${planDuration(end.difference(start))}ほど）';
}

/// F4：表示のときだけ、5 分単位の近いほうに丸める（10:02 → 10:00、10:03 → 10:05。5 分ちょうどは変わらない）
DateTime planRoundToFiveMinutes(DateTime time) {
  final seconds = time.minute * 60 + time.second;
  final minutes = (seconds + 150) ~/ 300 * 5;
  return DateTime(time.year, time.month, time.day, time.hour).add(Duration(minutes: minutes));
}

/// 表示する寝る目安（D16・D17 で数え直したものだけ 5 分単位に丸める。F4）
DateTime _shownSleepAt(SleepWindow window) =>
    window.sleepAtRecounted ? planRoundToFiveMinutes(window.sleepAt) : window.sleepAt;

/// 表示する起きる目安（数え直したものだけ 5 分単位に丸める。F4）
DateTime _shownWakeAt(SleepWindow window) =>
    window.wakeAtRecounted ? planRoundToFiveMinutes(window.wakeAt) : window.wakeAt;

/// F5：次が夜勤の場面で仮眠の目安がないときの文
const String sleepPlanNoNapText = '起きてから出勤までが短いので、今回は仮眠の目安はありません';

/// 日の呼び方つきの行（「今夜　寝る目安 …」）
String _labeled(DateTime start, DateTime now, String body) => '${planDayLabel(start, now: now)}　$body';

/// 日の呼び方つきの main の行（D71：夜の呼び方なら 0:00〜4:59 に「翌」を付けない）
String _labeledMain(SleepWindow window, DateTime now) => _labeled(
      window.sleepAt,
      now,
      _mainWindowText(window, _nightKey(window.sleepAt), sameNight: _isNightStart(window.sleepAt)),
    );

/// 日の呼び方つきの追加の睡眠の行（D71 は main と同じ）
String _labeledExtra(PlannedSleepKind kind, SleepWindow window, DateTime now) => _labeled(
      window.sleepAt,
      now,
      _extraWindowText(kind, window, _nightKey(window.sleepAt), sameNight: _isNightStart(window.sleepAt)),
    );

/// 文言を作る（plan が null なら勤務なし）
/// - sleeping：今寝ているか（中にいるときの文が変わる）
SleepPlanText sleepPlanText(SleepPlan? plan, {required DateTime now, bool sleeping = false}) {
  if (plan == null) {
    return SleepPlanText(
      headline: sleepSceneHeadline(SleepScene.noShift),
      subline: 'ふだんどおりに過ごせる日です',
      mainLine: null,
      freeNapLine: null,
      statusLines: const [],
      reassurance: sleepReassuranceEnough,
      styleNote: null,
      reasonLines: const [],
      extraLines: const [],
      days: const [],
    );
  }

  final next = plan.next;
  final subline = next != null
      ? '${planDayLabel(next.startAt, now: now)} ${planTimeOfDay(next.startAt)} からの「${next.pattern.patternName}」'
      : '夜勤おつかれさまでした';

  final main = plan.main;
  final nap = plan.preShiftNap;
  final today = _date(now);

  final mainLine = main != null ? _labeledMain(main, now) : null;
  final freeNapLine = nap != null ? _labeledExtra(PlannedSleepKind.preNightNap, nap, now) : null;

  final statusLines = <String>[
    if (plan.currentShift != null) '勤務中です。終わったあとの目安です',
  ];
  if (main == null) {
    statusLines.add('次の勤務までの時間が短く、まとまった睡眠の目安は出せません。少し横になるだけでも体は休まります');
  } else {
    switch (main.status) {
      case SleepWindowStatus.upcoming:
        if (main.shortened) {
          statusLines.add('勤務の間が短いため、いつもより短めの目安です。足りない分は、できるときに少しずつで大丈夫です');
        }
      case SleepWindowStatus.ongoing:
        final wake = planTime(_shownWakeAt(main), baseDate: today);
        statusLines.add(sleeping ? 'おやすみ中です。起きる目安は $wake ごろです' : '今から眠ると、起きる目安は $wake ごろです');
      case SleepWindowStatus.past:
        statusLines.add('この目安の時間は終わりました。次の目安からで大丈夫です');
        if (nap != null && nap.status != SleepWindowStatus.past) {
          statusLines.add('次は出勤前の仮眠の目安です（${planTime(_shownSleepAt(nap), baseDate: today)} ごろ〜）');
        }
    }
  }

  final String reassurance;
  if (main == null || (main.shortened && main.status == SleepWindowStatus.upcoming)) {
    reassurance = sleepReassuranceRest;
  } else if (main.status == SleepWindowStatus.past) {
    reassurance = sleepReassuranceNext;
  } else {
    reassurance = sleepReassuranceEnough;
  }

  final styleMatters = plan.scene == SleepScene.betweenNights ||
      plan.scene == SleepScene.quickReturn ||
      (plan.scene == SleepScene.nightToDay && next?.kind == ShiftKind.evening);

  const dayNames = ['今日', '明日', 'あさって'];
  final days = <SleepDayText>[];
  for (var i = 0; i < plan.days.length; i++) {
    final day = plan.days[i];
    final entries = <({DateTime at, String text})>[
      for (final shift in day.shifts)
        (
          at: shift.startAt,
          text: '勤務　${shift.pattern.patternName} ${planTime(shift.startAt, baseDate: day.date)}〜'
              '${planTime(shift.endAt, baseDate: day.date)}',
        ),
      for (final sleep in day.sleeps)
        (
          at: sleep.window.sleepAt,
          text: sleep.kind == PlannedSleepKind.main
              ? _mainWindowText(sleep.window, day.date)
              : _extraWindowText(sleep.kind, sleep.window, day.date),
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    days.add(SleepDayText(
      title: '${i < dayNames.length ? dayNames[i] : ''} ${planMonthDay(day.date)}'.trim(),
      lines: [for (final entry in entries) entry.text],
    ));
  }

  return SleepPlanText(
    headline: sleepSceneHeadline(plan.scene),
    subline: subline,
    mainLine: mainLine,
    freeNapLine: freeNapLine,
    statusLines: statusLines,
    reassurance: reassurance,
    styleNote: styleMatters ? sleepStyleNote(plan.style, plan.styleSource) : null,
    reasonLines: [for (final reason in plan.reasons) sleepPlanReasonText(reason)],
    extraLines: [
      for (final extra in plan.extraSleeps) _labeledExtra(extra.kind, extra.window, now),
      // F5：次が夜勤の場面（夜勤前・日勤→夜勤・連続夜勤）で仮眠の目安がないとき
      if ((plan.scene == SleepScene.beforeNight ||
              plan.scene == SleepScene.dayToNight ||
              plan.scene == SleepScene.betweenNights) &&
          !plan.extraSleeps.any((s) => s.kind == PlannedSleepKind.preNightNap))
        sleepPlanNoNapText,
    ],
    days: days,
  );
}
