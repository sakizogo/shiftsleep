import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/next_shift.dart';
import 'package:shiftsleep/services/sleep_baseline.dart';
import 'package:shiftsleep/services/sleep_plan.dart';
import 'package:shiftsleep/services/sleep_plan_text.dart';

// A-2 4/4：sleep_plan_text.dart のテスト
// 3 交代：日勤 8:00〜17:00／準夜勤 16:00〜1:00／深夜 0:00〜9:00（前日の欄に登録）
// 2 交代：日勤 8:00〜17:00／夜勤 20:00〜5:00。2026-11-16 は月曜

DateTime t(int day, int hour, [int minute = 0]) => DateTime(2026, 11, day, hour, minute);

TimeOfDay hm(int hour, int minute) => TimeOfDay(hour: hour, minute: minute);

ShiftPatternModel work(String name, TimeOfDay start, TimeOfDay end) => ShiftPatternModel(
      id: 'p_$name',
      patternName: name,
      patternType: ShiftType.work,
      startTime: start,
      endTime: end,
      colorIndex: 1,
    );

final dayD = work('日勤', hm(8, 0), hm(17, 0));
final eveningE = work('準夜勤', hm(16, 0), hm(1, 0));
final nightN = work('深夜', hm(0, 0), hm(9, 0));
final nightNt = work('夜勤', hm(20, 0), hm(5, 0));

List<WorkShift> shiftsOf(Map<int, ShiftPatternModel> byDay) =>
    workShiftsFromMap({for (final entry in byDay.entries) t(entry.key, 0): entry.value});

SleepBaseline baselineWith({List<ShiftSleepGap> before = const []}) => SleepBaseline(
      sampleCount: 0,
      usedDefault: true,
      averageAsleep: defaultAverageAsleep,
      rawAverageAsleep: null,
      bedtime: null,
      wakeTime: null,
      midpoint: null,
      afterShift: const [],
      beforeShift: before,
      shortSleepCount: 0,
      shortSleepTotal: Duration.zero,
    );

SleepPlan? plan(
  DateTime now,
  List<WorkShift> shifts, {
  SleepStylePreference preference = SleepStylePreference.immediate,
  SleepBaseline? baseline,
  int alarmMinutesBefore = 60,
  DateTime? sleepingSince,
}) =>
    buildSleepPlan(
      now: now,
      shifts: shifts,
      baseline: baseline ?? baselineWith(),
      preference: preference,
      options: SleepPlanOptions(alarmMinutesBefore: alarmMinutesBefore),
      sleepingSince: sleepingSince,
    );

SleepPlanText text(
  DateTime now,
  List<WorkShift> shifts, {
  SleepStylePreference preference = SleepStylePreference.immediate,
  SleepBaseline? baseline,
  int alarmMinutesBefore = 60,
  DateTime? sleepingSince,
}) =>
    sleepPlanText(
      plan(now, shifts,
          preference: preference,
          baseline: baseline,
          alarmMinutesBefore: alarmMinutesBefore,
          sleepingSince: sleepingSince),
      now: now,
      sleeping: sleepingSince != null,
      sleepingSince: sleepingSince,
    );

/// テストに出てくる場面・状態をひととおり（言い方の確認に使う）
List<SleepPlanText> allSampleTexts() => [
      text(t(16, 18), shiftsOf({16: dayD, 17: dayD})),
      text(t(16, 22, 30), shiftsOf({16: dayD, 17: dayD}), sleepingSince: t(16, 22)),  // N51 A 3/3：早く寝た
      text(t(17, 7, 30), shiftsOf({16: dayD, 17: dayD})),
      text(t(17, 1), shiftsOf({16: dayD, 17: dayD})),
      text(t(17, 10), shiftsOf({18: dayD})),
      text(t(16, 18), shiftsOf({16: dayD, 17: eveningE})),
      text(t(17, 1), shiftsOf({16: eveningE, 17: eveningE})),
      text(t(16, 12), shiftsOf({17: nightNt})),
      text(t(16, 12), shiftsOf({16: nightN})),
      text(t(16, 22), shiftsOf({16: nightN})),
      text(t(16, 17), shiftsOf({16: dayD, 17: nightNt})),
      text(t(17, 5), shiftsOf({16: nightNt, 17: nightNt})),
      text(t(17, 5), shiftsOf({16: nightNt, 17: nightNt}), preference: SleepStylePreference.lastMinute),
      text(t(17, 8), shiftsOf({16: nightNt, 17: nightNt})),
      text(t(17, 8), shiftsOf({16: nightNt, 17: nightNt}), sleepingSince: t(17, 6, 30)),
      text(t(16, 17), [...shiftsOf({16: dayD}), ...shiftsOf({16: nightN})]),
      text(t(17, 5), shiftsOf({16: nightNt, 17: dayD}), alarmMinutesBefore: 90),
      text(t(17, 5), shiftsOf({16: nightNt})),
      text(t(17, 9), shiftsOf({16: nightN, 18: dayD})),
      text(t(17, 5), shiftsOf({16: nightNt, 18: eveningE})),
      text(t(17, 22), shiftsOf({16: nightNt, 17: nightNt})),
      sleepPlanText(null, now: t(16, 12)),
    ];

void main() {
  group('見出し・副題（1・11）', () {
    test('1. 10 の場面の見出しと、パターン名の入った副題', () {
      void expectHead(SleepPlanText result, String headline, String? subline) {
        expect(result.headline, headline);
        expect(result.subline, subline);
      }

      expectHead(text(t(16, 18), shiftsOf({16: dayD, 17: dayD})), '次の日勤に向けた目安', '明日 8:00 からの「日勤」');
      expectHead(text(t(17, 10), shiftsOf({18: dayD})), '休み明けの日勤に向けた目安', '明日 8:00 からの「日勤」');
      expectHead(text(t(16, 18), shiftsOf({16: dayD, 17: eveningE})), '準夜勤の前の目安', '明日 16:00 からの「準夜勤」');
      expectHead(text(t(16, 12), shiftsOf({17: nightNt})), '夜勤の前の目安', '明日の夜 20:00 からの「夜勤」');
      expectHead(text(t(16, 17), shiftsOf({16: dayD, 17: nightNt})), '日勤から夜勤への切り替えの目安', '明日の夜 20:00 からの「夜勤」');
      expectHead(text(t(17, 5), shiftsOf({16: nightNt, 17: nightNt})), '夜勤と夜勤のあいだの目安', '今夜 20:00 からの「夜勤」');
      expectHead(text(t(16, 17), [...shiftsOf({16: dayD}), ...shiftsOf({16: nightN})]), '勤務の間が短い日の目安',
          '今夜 0:00 からの「深夜」');
      expectHead(text(t(17, 5), shiftsOf({16: nightNt})), '夜勤明けの目安', '夜勤おつかれさまでした');
      expectHead(text(t(17, 5), shiftsOf({16: nightNt, 18: dayD})), '夜勤から日勤への切り替えの目安', '明日 8:00 からの「日勤」');
      expectHead(sleepPlanText(null, now: t(16, 12)), 'この 2 日は勤務がありません', 'ふだんどおりに過ごせる日です');
    });

    test('11. プランが null なら勤務なしの見出しで、目安の行はない', () {
      final result = sleepPlanText(null, now: t(16, 12));
      expect(result.headline, 'この 2 日は勤務がありません');
      expect(result.mainLine, isNull);
      expect(result.days, isEmpty);
      expect(result.reassurance, isNotEmpty);
    });
  });

  group('時刻・日・長さの書き方（2〜4・20・21）', () {
    test('2. 「翌 0:30」：基準の日はそのまま、次の日は「翌」、それより先は日付', () {
      final base = t(17, 0);
      expect(planTime(t(17, 23), baseDate: base), '23:00');
      expect(planTime(t(18, 0, 30), baseDate: base), '翌 0:30');
      expect(planTime(t(19, 7), baseDate: base), '11/19（木） 7:00');
      // 出勤前アラーム 120 分：寝る 月 23:00、起きる 火 6:00
      expect(text(t(16, 18), shiftsOf({16: dayD, 17: dayD}), alarmMinutesBefore: 120).mainLine,
          '今夜　寝る目安 23:00 ごろ → 起きる目安 翌 6:00 ごろ（7 時間）');
      expect(text(t(16, 18), shiftsOf({16: dayD, 17: dayD})).mainLine,
          '今夜　寝る目安 0:00 ごろ → 起きる目安 翌 7:00 ごろ（7 時間）');  // A-3 1/3：D71 で「翌 0:00」→「0:00」
      // 3 日分の行も、その日を基準に書く
      final days = text(t(16, 18), shiftsOf({16: dayD, 17: nightNt})).days;
      expect(days.first.title, '今日 11/16（月）');
      // N188：3 日分の main は「寝る」「起きる」の 2 行。N205：17:00 に終わった日勤は 18:00 に見ると出さない
      expect(days.first.lines, ['寝る 翌 1:00 ごろ', '起きる 翌 8:00 ごろ（7 時間）']);
      expect(days[1].title, '明日 11/17（火）');
      expect(days[1].lines, ['仮眠の目安 17:30〜19:00 ごろ（90 分ほど）', '勤務　夜勤 20:00〜翌 5:00']);
      expect(days[2].title, 'あさって 11/18（水）');
    });

    test('3. 今日／今夜／明日／明日の夜／日付（曜日つき）の書き方', () {
      final now = t(16, 12);
      expect(planDayLabel(t(16, 10), now: now), '今日');
      expect(planDayLabel(t(16, 23), now: now), '今夜');
      expect(planDayLabel(t(17, 0, 30), now: now), '今夜');
      expect(planDayLabel(t(17, 4, 59), now: now), '今夜');
      expect(planDayLabel(t(17, 5), now: now), '明日');
      expect(planDayLabel(t(17, 17, 59), now: now), '明日');
      expect(planDayLabel(t(17, 18), now: now), '明日の夜');
      expect(planDayLabel(t(18, 3), now: now), '明日の夜');
      expect(planDayLabel(t(18, 10), now: now), '11/18（水）');
      expect(planDayLabel(t(18, 20), now: now), '11/18（水）の夜');
      expect(planDayLabel(t(19, 2), now: now), '11/18（水）の夜');
    });

    test('4. 長さ：7 時間・6 時間 30 分・90 分。追加の睡眠には「ほど」を付け、「ごろ」は最後に 1 回', () {
      expect(planDuration(const Duration(hours: 7)), '7 時間');
      expect(planDuration(const Duration(hours: 6, minutes: 30)), '6 時間 30 分');
      expect(planDuration(const Duration(minutes: 90)), '90 分');
      expect(planDuration(const Duration(hours: 1)), '1 時間');
      expect(planDuration(const Duration(minutes: 30)), '30 分');
      expect(text(t(16, 12), shiftsOf({17: nightNt})).extraLines, ['明日　仮眠の目安 17:30〜19:00 ごろ（90 分ほど）']);
      expect(text(t(17, 9), shiftsOf({16: nightN, 18: dayD})).extraLines,
          ['今日　明けの睡眠の目安 10:00〜14:00 ごろ（4 時間ほど）']);
    });

    test('20. 夜勤明けの睡眠（10:00 開始）は「今日」で、「今夜」にならない', () {
      expect(text(t(17, 9), shiftsOf({16: nightN})).mainLine, '今日　寝る目安 10:00 ごろ → 起きる目安 14:00 ごろ（4 時間）');
      expect(text(t(17, 9), shiftsOf({16: nightN, 18: dayD})).extraLines.single, startsWith('今日　'));
    });

    test('21. 18:00 以降・0:00〜4:59 に始まる睡眠は「今夜」「明日の夜」', () {
      // 日→夜（D→Nt）を月 17:00 に見る：main は火 1:00 から（今夜）
      expect(text(t(16, 17), shiftsOf({16: dayD, 17: nightNt})).mainLine, startsWith('今夜　寝る目安 1:00 ごろ'));  // A-3 1/3：D71 で「翌 1:00」→「1:00」
      // 休み→深夜（月の欄・火 0:00）を日 20:00 に見る：仮眠は月 21:30 から（明日の夜）
      final result = text(t(15, 20), shiftsOf({16: nightN}));
      expect(result.mainLine, startsWith('今夜　'));
      expect(result.extraLines, ['明日の夜　仮眠の目安 21:30〜23:00 ごろ（90 分ほど）']);
    });
  });

  group('A-3 1/3：D71（夜の呼び方の行は、0:00〜4:59 に「翌」を付けない）', () {
    test('11. 今夜 0:00／翌 7:00／今日 10:00〜14:00 ごろ／明日の夜 23:00 → 翌 6:00', () {
      expect(text(t(16, 18), shiftsOf({16: dayD, 17: dayD})).mainLine,
          '今夜　寝る目安 0:00 ごろ → 起きる目安 翌 7:00 ごろ（7 時間）');
      expect(text(t(17, 9), shiftsOf({16: nightN, 18: dayD})).extraLines,
          ['今日　明けの睡眠の目安 10:00〜14:00 ごろ（4 時間ほど）']);
      // 月 12:00 に見て、水 8:00 の日勤（出勤前 120 分）：寝る 火 23:00、起きる 水 6:00
      expect(text(t(16, 12), shiftsOf({18: dayD}), alarmMinutesBefore: 120).mainLine,
          '明日の夜　寝る目安 23:00 ごろ → 起きる目安 翌 6:00 ごろ（7 時間）');

      final base = t(17, 0);
      expect(planTime(t(18, 0, 30), baseDate: base, sameNight: true), '0:30');
      expect(planTime(t(18, 4, 59), baseDate: base, sameNight: true), '4:59');
      expect(planTime(t(18, 5), baseDate: base, sameNight: true), '翌 5:00');
      expect(planTime(t(18, 0, 30), baseDate: base), '翌 0:30');
    });
  });

  group('A-3 3/3：F3・F4・F5', () {
    test('F3：3 日分で始まりと終わりが同じ日なら、終わりの「翌」を省く（違う日なら付ける）', () {
      // 2 交代 ①（月 Nt・水 D）を火 5:00 に見る：水の欄の夜は 木 0:00〜7:00
      final days = text(t(17, 5), shiftsOf({16: nightNt, 18: dayD})).days;
      expect(days[1].lines.last, 'ふだんの睡眠の目安 翌 0:00〜7:00 ごろ（7 時間ほど）');
      expect(days[2].lines.single, 'ふだんの睡眠の目安 翌 0:00〜7:00 ごろ（7 時間ほど）');
      // 仮眠（同じ日の中）はそのまま
      expect(text(t(16, 12), shiftsOf({17: nightNt})).days[1].lines.first, '仮眠の目安 17:30〜19:00 ごろ（90 分ほど）');
    });

    test('F3：始まりが基準の日で終わりが次の日なら「翌」を付けたまま', () {
      final early = SleepBaseline(
        sampleCount: 0,
        usedDefault: true,
        averageAsleep: defaultAverageAsleep,
        rawAverageAsleep: null,
        bedtime: null,
        wakeTime: const CircularTimeMean(minuteOfDay: 6 * 60 + 30, concentration: 0.9),
        midpoint: null,
        afterShift: const [],
        beforeShift: const [],
        shortSleepCount: 0,
        shortSleepTotal: Duration.zero,
      );
      final days = text(t(17, 5), shiftsOf({16: nightNt, 18: dayD}), baseline: early).days;
      expect(days[1].lines.last, 'ふだんの睡眠の目安 23:30〜翌 6:30 ごろ（7 時間ほど）');
    });

    test('F4：5 分単位の近いほうに丸める（5 分ちょうどは変わらない）', () {
      expect(planRoundToFiveMinutes(t(17, 10, 2)), t(17, 10, 0));
      expect(planRoundToFiveMinutes(t(17, 10, 3)), t(17, 10, 5));
      expect(planRoundToFiveMinutes(t(17, 17, 2)), t(17, 17, 0));
      expect(planRoundToFiveMinutes(t(17, 10, 0)), t(17, 10, 0));
      expect(planRoundToFiveMinutes(t(17, 23, 58)), t(18, 0, 0));
    });

    test('F4：数え直した時刻だけ表示で丸め、計算の値は変えない', () {
      // 連続夜勤（帰ってすぐ寝る）を 8:02 に見る：計算は 8:02〜15:02、表示は 8:00〜15:00
      final shifts = shiftsOf({16: nightNt, 17: nightNt});
      final p = plan(t(17, 8, 2), shifts)!;
      expect(p.main!.sleepAt, t(17, 8, 2));
      expect(p.main!.wakeAt, t(17, 15, 2));
      final result = sleepPlanText(p, now: t(17, 8, 2));
      expect(result.mainLine, '今日　寝る目安 8:00 ごろ → 起きる目安 15:00 ごろ（7 時間）');
      expect(result.statusLines, ['今から眠ると、起きる目安は 15:00 ごろです']);

      // 日勤前を 1:03 に見る：寝る目安だけ数え直す（1:05）。起きる目安 7:00 はそのまま
      expect(text(t(17, 1, 3), shiftsOf({16: dayD, 17: dayD})).mainLine,
          '今夜　寝る目安 1:05 ごろ → 起きる目安 翌 7:00 ごろ（5 時間 55 分）');

      // 数え直していない目安は変わらない
      expect(text(t(16, 18), shiftsOf({16: dayD, 17: dayD})).mainLine,
          '今夜　寝る目安 0:00 ごろ → 起きる目安 翌 7:00 ごろ（7 時間）');
    });

    test('F5：次が夜勤で仮眠がないとき（出勤ぎりぎりまで寝る）は 1 行出し、仮眠があるとき・日勤前は出さない', () {
      final shifts = shiftsOf({16: nightNt, 17: nightNt});
      expect(text(t(17, 5), shifts, preference: SleepStylePreference.lastMinute).extraLines, [sleepPlanNoNapText]);
      expect(text(t(17, 5), shifts).extraLines, isNot(contains(sleepPlanNoNapText)));
      expect(text(t(16, 18), shiftsOf({16: dayD, 17: dayD})).extraLines, isEmpty);
      expect(sleepPlanNoNapText, isNot(contains('してください')));
    });

    test('G1：数え直した main と重なって仮眠を外したら、F5 の一言を出し、仮眠の理由は出さない', () {
      final shifts = shiftsOf({13: nightN, 14: nightNt});
      final napReason = sleepPlanReasonText(SleepPlanReason.nightShiftNap);
      for (final sleepingSince in [null, t(14, 12)]) {
        final result = text(t(14, 12, 35), shifts, sleepingSince: sleepingSince);
        expect(result.extraLines, [sleepPlanNoNapText], reason: 'sleepingSince: $sleepingSince');
        expect(result.freeNapLine, isNull);
        expect(result.reasonLines, isNot(contains(napReason)));
      }
      // 数え直していないときは、今までどおり仮眠が出て、一言は出ない
      final before = text(t(14, 9, 30), shifts);
      expect(before.extraLines, isNot(contains(sleepPlanNoNapText)));
      expect(before.reasonLines, contains(napReason));
    });
  });

  group('状態・一言（5・6）', () {
    test('5. 状態ごとの文', () {
      expect(text(t(16, 18), shiftsOf({16: dayD, 17: dayD})).statusLines, isEmpty);
      expect(text(t(17, 8), shiftsOf({16: nightNt, 17: nightNt})).statusLines, ['今から眠ると、起きる目安は 15:00 ごろです']);
      expect(text(t(17, 8), shiftsOf({16: nightNt, 17: nightNt}), sleepingSince: t(17, 6, 30)).statusLines,
          ['おやすみ中です。起きる目安は 13:30 ごろです']);
      expect(text(t(17, 7, 30), shiftsOf({16: dayD, 17: dayD})).statusLines, ['この目安の時間は終わりました。次の目安からで大丈夫です']);

      final withNap = text(t(16, 12), shiftsOf({16: nightN}));
      expect(withNap.statusLines, ['この目安の時間は終わりました。次の目安からで大丈夫です', '次は出勤前の仮眠の目安です（21:30 ごろ〜）']);
      expect(withNap.freeNapLine, '今夜　仮眠の目安 21:30〜23:00 ごろ（90 分ほど）');

      expect(text(t(16, 17), [...shiftsOf({16: dayD}), ...shiftsOf({16: nightN})]).statusLines,
          ['勤務の間が短いため、いつもより短めの目安です。足りない分は、できるときに少しずつで大丈夫です']);
      final noMain = text(t(17, 5), shiftsOf({16: nightNt, 17: dayD}), alarmMinutesBefore: 90);
      expect(noMain.mainLine, isNull);
      expect(noMain.statusLines, ['次の勤務までの時間が短く、まとまった睡眠の目安は出せません。少し横になるだけでも体は休まります']);
      expect(text(t(17, 22), shiftsOf({16: nightNt, 17: nightNt})).statusLines, ['勤務中です。終わったあとの目安です']);
    });

    test('6. 一言は状態で選ぶ', () {
      expect(text(t(16, 18), shiftsOf({16: dayD, 17: dayD})).reassurance, sleepReassuranceEnough);
      expect(text(t(17, 8), shiftsOf({16: nightNt, 17: nightNt})).reassurance, sleepReassuranceEnough);
      expect(text(t(17, 7, 30), shiftsOf({16: dayD, 17: dayD})).reassurance, sleepReassuranceNext);
      expect(text(t(16, 17), [...shiftsOf({16: dayD}), ...shiftsOf({16: nightN})]).reassurance, sleepReassuranceRest);
      expect(text(t(17, 5), shiftsOf({16: nightNt, 17: dayD}), alarmMinutesBefore: 90).reassurance, sleepReassuranceRest);
      expect(sleepPlanText(null, now: t(16, 12)).reassurance, sleepReassuranceEnough);
    });
  });

  group('理由・寝方のタイプ（7・8）', () {
    test('7. 理由 15 種類すべてに、ちがう文がある', () {
      final texts = SleepPlanReason.values.map(sleepPlanReasonText).toList();
      expect(texts, hasLength(15));
      expect(texts.every((s) => s.isNotEmpty), isTrue);
      expect(texts.toSet(), hasLength(15));
      expect(text(t(16, 18), shiftsOf({16: dayD, 17: dayD})).reasonLines,
          [sleepPlanReasonText(SleepPlanReason.wakeForShift), sleepPlanReasonText(SleepPlanReason.fewRecords)]);
    });

    test('7b. A-4 2/3：起きる目安の理由の文', () {
      expect(sleepPlanReasonText(SleepPlanReason.wakeForShift), '起きる目安は、出勤前アラームと同じころにしています。');
      expect(sleepPlanReasonText(SleepPlanReason.wakeForCommutePrep),
          '起きる目安は、出勤の時刻から、登録した通勤・身支度の時間を引いたころにしています。');
      expect(sleepPlanReasonText(SleepPlanReason.wakeForCommutePrepBeforeAlarm),
          '起きる目安は、出勤の時刻から、登録した通勤・身支度の時間を引いたころにしています。出勤前アラームより早めの目安です。');
      expect(sleepPlanReasonText(SleepPlanReason.wakeDefaultLead),
          '出勤前アラームが無効のため、起きる目安は出勤の 1 時間前ごろにしています。通勤・身支度を登録すると、それに合わせた目安になります。');
      // 言い切らない・「あなた」を使わない
      for (final reason in [
        SleepPlanReason.wakeForShift,
        SleepPlanReason.wakeForCommutePrep,
        SleepPlanReason.wakeForCommutePrepBeforeAlarm,
        SleepPlanReason.wakeDefaultLead,
      ]) {
        final s = sleepPlanReasonText(reason);
        expect(s, contains('目安'));
        expect(s, isNot(contains('あなた')));
        expect(s, isNot(contains('してください')));
        expect(s, isNot(contains('しなければ')));
      }
    });

    test('8. 寝方のタイプ：設定・記録・既定。タイプで目安が変わる場面だけ', () {
      final shifts = shiftsOf({16: nightNt, 17: nightNt});
      expect(text(t(17, 5), shifts).styleNote, '寝方のタイプ：帰ってすぐ寝る（設定から）');
      final nightShift = shiftsOf({16: nightNt}).single;
      final records = baselineWith(before: [
        for (var i = 0; i < 3; i++)
          ShiftSleepGap(
            sleep: MainSleep(start: t(1, 0), end: t(1, 7), asleep: const Duration(hours: 7), recordIds: const ['x']),
            shift: nightShift,
            gap: const Duration(hours: 1),
          ),
      ]);
      expect(text(t(17, 5), shifts, preference: SleepStylePreference.auto, baseline: records).styleNote,
          '寝方のタイプ：出勤ぎりぎりまで寝る（これまでの記録から）');
      expect(text(t(17, 5), shifts, preference: SleepStylePreference.auto).styleNote,
          '寝方のタイプ：帰ってすぐ寝る（記録がまだ少ないため。設定で変えられます）');
      // 間が短い・夜勤→準夜勤では出し、日勤前・夜勤→日勤では出さない
      expect(text(t(16, 17), [...shiftsOf({16: dayD}), ...shiftsOf({16: nightN})]).styleNote, isNotNull);
      expect(text(t(17, 5), shiftsOf({16: nightNt, 18: eveningE})).styleNote, isNotNull);
      expect(text(t(16, 18), shiftsOf({16: dayD, 17: dayD})).styleNote, isNull);
      expect(text(t(17, 5), shiftsOf({16: nightNt, 18: dayD})).styleNote, isNull);
    });
  });

  group('言い方（9・10・22）', () {
    final samples = allSampleTexts();
    final everyText = [
      for (final sample in samples) ...sample.allTexts,
      for (final reason in SleepPlanReason.values) sleepPlanReasonText(reason),
      for (final style in SleepStyle.values)
        for (final source in SleepStyleSource.values) sleepStyleNote(style, source),
      for (final scene in SleepScene.values) sleepSceneHeadline(scene),
    ];

    test('9. どの文にも「してください」「しなければ」が入らない', () {
      for (final line in everyText) {
        expect(line, isNot(contains('してください')), reason: line);
        expect(line, isNot(contains('しなければ')), reason: line);
      }
    });

    test('10. どの場面にも、眠れなくても大丈夫の一言が入る', () {
      const reassurances = {sleepReassuranceRest, sleepReassuranceEnough, sleepReassuranceNext};
      for (final sample in samples) {
        expect(reassurances, contains(sample.reassurance), reason: sample.headline);
      }
    });

    test('22. どの文にも「休みの日に」「次の休みで」が入らない', () {
      for (final line in everyText) {
        expect(line, isNot(contains('休みの日に')), reason: line);
        expect(line, isNot(contains('次の休みで')), reason: line);
      }
    });
  });

  group('N51 A 3/3：寝る目安より早く寝たとき', () {
    const early = '早めにおやすみ中です。起きる目安は';

    test('1. 日勤前の夜：22:00 に寝た（寝る目安 0:00）→ 寝る目安の行は出さず、起きる目安はプランのまま', () {
      final shifts = shiftsOf({16: dayD, 17: dayD});
      expect(sleepingBeforeMain(plan(t(16, 22, 30), shifts, sleepingSince: t(16, 22))!, sleepingSince: t(16, 22)), isTrue);
      final result = text(t(16, 22, 30), shifts, sleepingSince: t(16, 22));
      expect(result.mainLine, '早めにおやすみ中です。起きる目安は 翌 7:00 ごろです');
      expect(result.allTexts.where((line) => line.contains('寝る目安')), isEmpty);
      // 寝ていなければ今までどおり
      expect(text(t(16, 22, 30), shifts).mainLine, '今夜　寝る目安 0:00 ごろ → 起きる目安 翌 7:00 ごろ（7 時間）');
    });

    test('2. 夜勤前：前の夜に早く寝た → 当てはまる（起きる目安はプランのまま）', () {
      final result = text(t(16, 22, 30), shiftsOf({17: nightNt}), sleepingSince: t(16, 22));
      expect(result.mainLine, '早めにおやすみ中です。起きる目安は 翌 7:00 ごろです');
    });

    test('3. 連続夜勤の出勤ぎりぎりまで寝るタイプ：9:00 に寝た（寝る目安 12:00）→ 起きる目安は出勤の 1 時間前', () {
      final shifts = shiftsOf({16: nightNt, 17: nightNt});
      final result = text(t(17, 9, 30), shifts, preference: SleepStylePreference.lastMinute, sleepingSince: t(17, 9));
      expect(result.mainLine, '早めにおやすみ中です。起きる目安は 19:00 ごろです');
      // 入眠が前の勤務（5:00 まで）の中なら当てはまらない
      final fromShift = plan(t(17, 9, 30), shifts, preference: SleepStylePreference.lastMinute, sleepingSince: t(17, 4))!;
      expect(sleepingBeforeMain(fromShift, sleepingSince: t(17, 4)), isFalse);
    });

    test('4. 明けの睡眠の中・明けの睡眠の前に寝たときは当てはまらない', () {
      final shifts = shiftsOf({16: nightNt, 18: dayD});  // 明けの睡眠 6:00〜10:00、main 水 0:00〜7:00
      for (final (now, since) in [(t(17, 7), t(17, 6, 30)), (t(17, 5, 45), t(17, 5, 30))]) {
        expect(sleepingBeforeMain(plan(now, shifts, sleepingSince: since)!, sleepingSince: since), isFalse, reason: '$since');
        expect(text(now, shifts, sleepingSince: since).mainLine, isNot(startsWith(early)), reason: '$since');
      }
    });

    test('5. 寝る目安を過ぎてから寝たときは当てはまらず、今までどおり「おやすみ中です」', () {
      final shifts = shiftsOf({16: dayD, 17: dayD});
      final result = text(t(17, 1), shifts, sleepingSince: t(17, 0, 30));
      expect(sleepingBeforeMain(plan(t(17, 1), shifts, sleepingSince: t(17, 0, 30))!, sleepingSince: t(17, 0, 30)), isFalse);
      expect(result.mainLine, isNot(startsWith(early)));
      expect(result.statusLines, contains('おやすみ中です。起きる目安は 7:00 ごろです'));
    });

    test('6. 4:16 に寝て、main の寝る目安が翌日 0:30（違う日）→ 当てはまらず、今までどおりの表示', () {
      final shifts = shiftsOf({18: work('テスト', hm(8, 30), hm(17, 0))});
      final now = t(17, 4, 16);
      expect(sleepingBeforeMain(plan(now, shifts, sleepingSince: now)!, sleepingSince: now), isFalse);
      expect(text(now, shifts, sleepingSince: now).mainLine, '明日の夜　寝る目安 0:30 ごろ → 起きる目安 翌 7:30 ごろ（7 時間）');
    });

    test('7. 起きる目安まで 12 時間ちょうどなら当てはまり、それより長い（昼寝など）なら当てはまらない', () {
      final shifts = shiftsOf({16: dayD, 17: dayD});  // 寝る目安 0:00、起きる目安 火 7:00
      bool sleptEarly(DateTime since) =>
          sleepingBeforeMain(plan(since.add(const Duration(minutes: 1)), shifts, sleepingSince: since)!, sleepingSince: since);
      expect(sleptEarly(t(16, 19)), isTrue);  // 12 時間ちょうど
      expect(sleptEarly(t(16, 18, 59)), isFalse);  // 12 時間 1 分
      expect(sleptEarly(t(16, 14)), isFalse);  // 日勤前の日の昼寝（17 時間）← 前の勤務の前なので、ほかの条件でも外れる
      expect(sleptEarly(t(16, 17, 30)), isFalse);  // 勤務のあとすぐ（13 時間 30 分）
    });

    test('8. ふだんの睡眠の目安の枠の中で寝ているときは当てはまらない', () {
      // 同じ日・12 時間以内で、main より前に、まだ終わっていない「ふだんの睡眠の目安」の枠がある形を作る
      SleepWindow window(DateTime start, DateTime end, SleepWindowStatus status) =>
          SleepWindow(sleepAt: start, wakeAt: end, shortened: false, status: status);
      SleepPlan planWith(SleepWindowStatus usualStatus) => SleepPlan(
            currentShift: null,
            scene: SleepScene.beforeDay,
            previous: null,
            next: null,
            style: SleepStyle.immediate,
            styleSource: SleepStyleSource.setting,
            main: window(t(17, 0), t(17, 7), SleepWindowStatus.upcoming),
            preShiftNap: null,
            reasons: const [],
            extraSleeps: const [],
            days: [
              DayPlan(date: t(16, 0), shifts: const [], sleeps: [
                PlannedSleep(kind: PlannedSleepKind.usualNight, window: window(t(16, 21, 30), t(16, 23, 30), usualStatus)),
              ]),
            ],
          );
      expect(sleepingBeforeMain(planWith(SleepWindowStatus.ongoing), sleepingSince: t(16, 21, 30)), isFalse);
      expect(sleepingBeforeMain(planWith(SleepWindowStatus.past), sleepingSince: t(16, 21, 30)), isTrue);
    });
  });

  group('N205：3 日分の欄を 5:00 で切る', () {
    final test830 = work('テスト', hm(8, 30), hm(17, 0));

    test('1. planDayOf：2:47・4:59 は前の日、5:00・12:00 はその日', () {
      expect(planDayOf(t(17, 2, 47)), t(16, 0));
      expect(planDayOf(t(17, 4, 59)), t(16, 0));
      expect(planDayOf(t(17, 5)), t(17, 0));
      expect(planDayOf(t(17, 12)), t(17, 0));
    });

    test('2. planDayDates：0:00〜4:59 は最初の欄が端末の日付より 1 日前', () {
      expect(planDayDates(t(17, 2, 47)), [t(16, 0), t(17, 0), t(18, 0)]);
      expect(planDayDates(t(17, 4, 59)), [t(16, 0), t(17, 0), t(18, 0)]);
      expect(planDayDates(t(17, 5)), [t(17, 0), t(18, 0), t(19, 0)]);
      expect(planDayDates(t(17, 12)), [t(17, 0), t(18, 0), t(19, 0)]);
    });

    test('3. planDayTitle：0:00〜4:59 の最初の欄だけ夜をまたぐ書き方', () {
      for (final now in [t(17, 2, 47), t(17, 4, 59)]) {
        final dates = planDayDates(now);
        expect([for (var i = 0; i < 3; i++) planDayTitle(i, dates[i], now: now)],
            ['今夜 11/16（月）〜17（火）', '明日 11/17（火）', 'あさって 11/18（水）'], reason: '$now');
      }
      for (final now in [t(17, 5), t(17, 12)]) {
        final dates = planDayDates(now);
        expect([for (var i = 0; i < 3; i++) planDayTitle(i, dates[i], now: now)],
            ['今日 11/17（火）', '明日 11/18（水）', 'あさって 11/19（木）'], reason: '$now');
      }
      // 月が変わるときは、終わりの日にも月を書く
      expect(planDayTitle(0, DateTime(2026, 11, 30), now: DateTime(2026, 12, 1, 2)), '今夜 11/30（月）〜12/1（火）');
    });

    test('4. 2:47 に 8:30 の勤務：今夜の睡眠は最初の欄、勤務は「明日」の欄（見出しの「明日」とそろう）', () {
      final result = text(t(17, 2, 47), shiftsOf({17: test830}));
      expect(result.subline, startsWith('明日 8:30 からの'));
      expect(result.days[0].title, '今夜 11/16（月）〜17（火）');
      expect(result.days[0].lines.take(2), ['寝る 翌 2:45 ごろ', '起きる 翌 7:30 ごろ（4 時間 45 分）']);
      expect(result.days[1].title, '明日 11/17（火）');
      expect(result.days[1].lines.first, '勤務　テスト 8:30〜17:00');
    });

    test('5. 12:00 に見ると、同じ勤務の前の睡眠は「今日」の欄に 2 行で出る', () {
      final days = text(t(17, 12), shiftsOf({18: test830})).days;
      expect(days[0].title, '今日 11/17（火）');
      expect(days[0].lines, contains('起きる 翌 7:30 ごろ（7 時間）'));
      expect(days[1].lines.first, '勤務　テスト 8:30〜17:00');
    });
  });
}
