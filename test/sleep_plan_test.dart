import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/next_shift.dart';
import 'package:shiftsleep/services/sleep_baseline.dart';
import 'package:shiftsleep/services/sleep_plan.dart';

// A-2 1/4：classifySleepScene・detectSleepStyle・resolveSleepStyle のテスト
// 3 交代：日勤 D 8:00〜17:00／準夜勤 E 16:00〜1:00／深夜 N 0:00〜9:00（前日の欄に登録）
// 2 交代：日勤 D 8:00〜17:00／夜勤 Nt 20:00〜5:00
// 2026-11-16 は月曜

/// 2026 年 11 月の日時
DateTime t(int day, int hour, [int minute = 0]) => DateTime(2026, 11, day, hour, minute);

TimeOfDay hm(int hour, int minute) => TimeOfDay(hour: hour, minute: minute);

ShiftPatternModel work(String id, TimeOfDay start, TimeOfDay end) => ShiftPatternModel(
      id: id,
      patternName: id,
      patternType: ShiftType.work,
      startTime: start,
      endTime: end,
      colorIndex: 1,
    );

final dayD = work('D', hm(8, 0), hm(17, 0));
final eveningE = work('E', hm(16, 0), hm(1, 0));
final nightN = work('N', hm(0, 0), hm(9, 0));
final nightNt = work('Nt', hm(20, 0), hm(5, 0));

/// 日（11 月の日）→ パターンの勤務の一覧
List<WorkShift> shiftsOf(Map<int, ShiftPatternModel> byDay) =>
    workShiftsFromMap({for (final entry in byDay.entries) t(entry.key, 0): entry.value});

SleepScene scene(DateTime now, List<WorkShift> shifts) => classifySleepScene(now: now, shifts: shifts);

/// 勤務明け・出勤前の 1 件（睡眠の中身は判定に使わない）
ShiftSleepGap gapOf(Duration gap, WorkShift shift) => ShiftSleepGap(
      sleep: MainSleep(start: t(1, 0), end: t(1, 7), asleep: const Duration(hours: 7), recordIds: const ['x']),
      shift: shift,
      gap: gap,
    );

SleepBaseline baselineWith({List<ShiftSleepGap> after = const [], List<ShiftSleepGap> before = const []}) =>
    SleepBaseline(
      sampleCount: 0,
      usedDefault: true,
      averageAsleep: defaultAverageAsleep,
      rawAverageAsleep: null,
      bedtime: null,
      wakeTime: null,
      midpoint: null,
      afterShift: after,
      beforeShift: before,
      shortSleepCount: 0,
      shortSleepTotal: Duration.zero,
    );

Duration h(double hours) => Duration(minutes: (hours * 60).round());

void main() {
  group('classifySleepScene', () {
    test('1. D→D は日勤前', () {
      expect(scene(t(16, 18), shiftsOf({16: dayD, 17: dayD})), SleepScene.beforeDay);
    });

    test('2. D→E は準夜勤前', () {
      expect(scene(t(16, 18), shiftsOf({16: dayD, 17: eveningE})), SleepScene.beforeEvening);
    });

    test('3. D→N（同じ月曜の欄・間 7 時間）は間が短い', () {
      // 1 日の欄にはパターンを 1 つしか置けないので、2 つの一覧をつなげて作る
      final shifts = [...shiftsOf({16: dayD}), ...shiftsOf({16: nightN})];
      expect(scene(t(16, 18), shifts), SleepScene.quickReturn);
    });

    test('4. E→D（間 7 時間）は間が短い', () {
      expect(scene(t(17, 2), shiftsOf({16: eveningE, 17: dayD})), SleepScene.quickReturn);
    });

    test('5. N→E（間 7 時間）は間が短い', () {
      // 月曜の欄の N は火曜 0:00〜9:00、火曜の E は 16:00 から
      expect(scene(t(17, 9), shiftsOf({16: nightN, 17: eveningE})), SleepScene.quickReturn);
    });

    test('6. 間がちょうど 11 時間なら間が短いに入らず、10 時間 59 分なら入る', () {
      final ends2100 = work('P2100', hm(10, 0), hm(21, 0));
      final ends2101 = work('P2101', hm(10, 0), hm(21, 1));
      expect(scene(t(16, 22), shiftsOf({16: ends2100, 17: dayD})), SleepScene.beforeDay);
      expect(scene(t(16, 22), shiftsOf({16: ends2101, 17: dayD})), SleepScene.quickReturn);
    });

    test('7. N→N・Nt→Nt は連続夜勤のあいだ', () {
      expect(scene(t(17, 10), shiftsOf({16: nightN, 17: nightN})), SleepScene.betweenNights);
      expect(scene(t(17, 6), shiftsOf({16: nightNt, 17: nightNt})), SleepScene.betweenNights);
    });

    test('8. 夜勤のあと 48 時間勤務がなければ夜勤明け→休み', () {
      expect(scene(t(17, 6), shiftsOf({16: nightNt})), SleepScene.nightToOff);
      expect(scene(t(17, 10), shiftsOf({16: nightN})), SleepScene.nightToOff);
    });

    test('9. N→D（間 23 時間）・Nt→D（間 27 時間）は夜勤→日勤の切り替え', () {
      expect(scene(t(17, 10), shiftsOf({16: nightN, 18: dayD})), SleepScene.nightToDay);
      expect(scene(t(17, 6), shiftsOf({16: nightNt, 18: dayD})), SleepScene.nightToDay);
    });

    test('10. D→Nt（間 27 時間）・E→N（間 23 時間）は日勤→夜勤の切り替え', () {
      expect(scene(t(16, 18), shiftsOf({16: dayD, 17: nightNt})), SleepScene.dayToNight);
      // 月曜の E は火曜 1:00 まで、火曜の欄の N は水曜 0:00 から
      expect(scene(t(17, 2), shiftsOf({16: eveningE, 17: nightN})), SleepScene.dayToNight);
    });

    test('11. 24 時間以内に勤務がなく、次が D なら休み明け', () {
      expect(scene(t(17, 10), shiftsOf({18: dayD})), SleepScene.afterRest);
    });

    test('12. 24 時間以内に勤務がなく、次が Nt なら夜勤前', () {
      expect(scene(t(17, 10), shiftsOf({18: nightNt})), SleepScene.beforeNight);
    });

    test('13. 48 時間以内に勤務がなければ勤務なし（25 時間前に終わった勤務は前に入らない）', () {
      expect(scene(t(17, 18), shiftsOf({16: dayD})), SleepScene.noShift);
      expect(scene(t(17, 18), []), SleepScene.noShift);
      // ちょうど 24 時間前に終わった夜勤は前に入る
      expect(scene(t(18, 5), shiftsOf({16: nightNt})), SleepScene.nightToOff);
      expect(scene(t(18, 5, 1), shiftsOf({16: nightNt})), SleepScene.noShift);
    });

    test('14. 勤務中の勤務は前にも次にも入らない', () {
      // 火曜の Nt（20:00〜5:00）の勤務中。前の夜勤明け→休みにはならず、勤務なし
      expect(scene(t(17, 22), shiftsOf({17: nightNt})), SleepScene.noShift);
      // 火曜の D の勤務中。前は月曜の D、次は水曜の D なので日勤前
      expect(scene(t(17, 10), shiftsOf({16: dayD, 17: dayD, 18: dayD})), SleepScene.beforeDay);
    });

    test('15. 前日の欄に登録した 0:00 勤務も夜勤として扱う', () {
      // 月曜の欄の N（火曜 0:00 から）を月曜の昼に見ると夜勤前
      expect(scene(t(16, 12), shiftsOf({16: nightN})), SleepScene.beforeNight);
    });

    test('23. 夜勤のあと 7 時間で準夜勤（N→E）は、夜勤→日勤・夜勤明けより先に間が短い', () {
      expect(scene(t(17, 12), shiftsOf({16: nightN, 17: eveningE})), SleepScene.quickReturn);
    });
  });

  group('detectSleepStyle・resolveSleepStyle', () {
    final nightShift = shiftsOf({16: nightNt}).single;
    final dayShift = shiftsOf({16: dayD}).single;

    test('16. 夜勤明けの gap（1・1.5・2 時間）が 3 件で、帰ってすぐ寝る', () {
      final result = detectSleepStyle(baselineWith(after: [
        for (final hours in [1.0, 1.5, 2.0]) gapOf(h(hours), nightShift),
      ]));
      expect(result.style, SleepStyle.immediate);
      expect(result.afterSamples, 3);
      expect(result.beforeSamples, 0);
    });

    test('17. 出勤前の gap（1・2・2 時間）が 3 件で、出勤ギリギリまで寝る', () {
      final result = detectSleepStyle(baselineWith(before: [
        for (final hours in [1.0, 2.0, 2.0]) gapOf(h(hours), nightShift),
      ]));
      expect(result.style, SleepStyle.lastMinute);
      expect(result.beforeSamples, 3);
    });

    test('18. 2 件ずつでは決まらない', () {
      final result = detectSleepStyle(baselineWith(
        after: [gapOf(h(1), nightShift), gapOf(h(1), nightShift)],
        before: [gapOf(h(1), nightShift), gapOf(h(1), nightShift)],
      ));
      expect(result.style, isNull);
    });

    test('19. 両方に当てはまれば中央値の小さいほう', () {
      final lastMinute = detectSleepStyle(baselineWith(
        after: [for (final hours in [1.0, 2.0, 3.0]) gapOf(h(hours), nightShift)],  // 中央値 2 時間
        before: [for (final hours in [0.5, 1.0, 1.0]) gapOf(h(hours), nightShift)],  // 中央値 1 時間
      ));
      expect(lastMinute.style, SleepStyle.lastMinute);

      final immediate = detectSleepStyle(baselineWith(
        after: [for (final hours in [0.5, 1.0, 1.0]) gapOf(h(hours), nightShift)],
        before: [for (final hours in [1.0, 2.0, 3.0]) gapOf(h(hours), nightShift)],
      ));
      expect(immediate.style, SleepStyle.immediate);

      // 中央値が 3 時間を超えるほうは当てはまらない（偶数件は真ん中 2 つの平均）
      final tooLong = detectSleepStyle(baselineWith(
        after: [for (final hours in [3.0, 3.0, 4.0, 4.0]) gapOf(h(hours), nightShift)],  // 中央値 3.5 時間
      ));
      expect(tooLong.style, isNull);
    });

    test('20. 日勤の組は数えない', () {
      final result = detectSleepStyle(baselineWith(
        after: [for (var i = 0; i < 3; i++) gapOf(h(1), dayShift)],
        before: [for (var i = 0; i < 3; i++) gapOf(h(1), dayShift)],
      ));
      expect(result.style, isNull);
      expect(result.afterSamples, 0);
      expect(result.beforeSamples, 0);
    });

    test('21. 設定（自動以外）が記録より優先される', () {
      final recordsSayLastMinute = baselineWith(before: [
        for (var i = 0; i < 3; i++) gapOf(h(1), nightShift),
      ]);
      expect(
        resolveSleepStyle(SleepStylePreference.immediate, recordsSayLastMinute),
        (style: SleepStyle.immediate, source: SleepStyleSource.setting),
      );
      expect(
        resolveSleepStyle(SleepStylePreference.lastMinute, baselineWith()),
        (style: SleepStyle.lastMinute, source: SleepStyleSource.setting),
      );
      expect(
        resolveSleepStyle(SleepStylePreference.auto, recordsSayLastMinute),
        (style: SleepStyle.lastMinute, source: SleepStyleSource.records),
      );
    });

    test('22. 自動で記録から決まらなければ既定（帰ってすぐ寝る）', () {
      expect(
        resolveSleepStyle(SleepStylePreference.auto, baselineWith()),
        (style: SleepStyle.immediate, source: SleepStyleSource.fallback),
      );
      expect(defaultSleepStyle, SleepStyle.immediate);
    });
  });
}
