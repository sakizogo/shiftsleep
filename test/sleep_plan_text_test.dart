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
    );

/// テストに出てくる場面・状態をひととおり（言い方の確認に使う）
List<SleepPlanText> allSampleTexts() => [
      text(t(16, 18), shiftsOf({16: dayD, 17: dayD})),
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
          '今夜　寝る目安 翌 0:00 ごろ → 起きる目安 翌 7:00 ごろ（7 時間）');
      // 3 日分の行も、その日を基準に書く
      final days = text(t(16, 18), shiftsOf({16: dayD, 17: nightNt})).days;
      expect(days.first.title, '今日 11/16（月）');
      expect(days.first.lines, ['勤務　日勤 8:00〜17:00', '寝る目安 翌 1:00 ごろ → 起きる目安 翌 8:00 ごろ（7 時間）']);
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
      expect(text(t(16, 17), shiftsOf({16: dayD, 17: nightNt})).mainLine, startsWith('今夜　寝る目安 翌 1:00 ごろ'));
      // 休み→深夜（月の欄・火 0:00）を日 20:00 に見る：仮眠は月 21:30 から（明日の夜）
      final result = text(t(15, 20), shiftsOf({16: nightN}));
      expect(result.mainLine, startsWith('今夜　'));
      expect(result.extraLines, ['明日の夜　仮眠の目安 21:30〜23:00 ごろ（90 分ほど）']);
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
    test('7. 理由 12 種類すべてに、ちがう文がある', () {
      final texts = SleepPlanReason.values.map(sleepPlanReasonText).toList();
      expect(texts, hasLength(12));
      expect(texts.every((s) => s.isNotEmpty), isTrue);
      expect(texts.toSet(), hasLength(12));
      expect(text(t(16, 18), shiftsOf({16: dayD, 17: dayD})).reasonLines,
          [sleepPlanReasonText(SleepPlanReason.wakeForShift), sleepPlanReasonText(SleepPlanReason.fewRecords)]);
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
}
