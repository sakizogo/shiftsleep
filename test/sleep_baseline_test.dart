import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/next_shift.dart';
import 'package:shiftsleep/services/sleep_baseline.dart';

// A-1 2/2：sleep_baseline.dart のテスト
// 2026-11-16 は月曜。now は基本 2026-11-25 12:00

/// テスト用の睡眠記録（durationMinutes は既定で end − start）
SleepRecord rec(
  String id,
  DateTime start,
  DateTime end, {
  int? durationMinutes,
  SleepRole role = SleepRole.primary,
}) {
  return SleepRecord(
    id: id,
    userId: 'test_user',
    sleepDate: DateTime(start.year, start.month, start.day),
    sleepStartTime: start,
    sleepStartAuto: true,
    sleepEndTime: end,
    sleepEndAuto: false,
    wakeUpType: '',
    durationMinutes: durationMinutes ?? end.difference(start).inMinutes,
    lastModifiedAt: start,
    canEditUntil: end.add(const Duration(days: 2)),
    createdAt: start,
    updatedAt: start,
    sleepRole: role,
  );
}

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

void main() {
  final now = t(25, 12);
  final dayShift = work('p_day', hm(8, 0), hm(17, 0));  // 日勤 8:00〜17:00
  final night20 = work('p_night20', hm(20, 0), hm(5, 0));  // 夜勤 20:00〜5:00
  final night0 = work('p_night0', hm(0, 0), hm(9, 0));  // 夜勤 0:00〜9:00（前日の欄に登録）

  /// 11/15 から 1 晩ずつ、23:00 に寝て durations の長さだけ眠る記録
  List<SleepRecord> nights(List<Duration> durations) => [
        for (var i = 0; i < durations.length; i++)
          rec('n$i', t(15 + i, 23), t(15 + i, 23).add(durations[i])),
      ];

  List<Duration> repeat(Duration duration, int count) => List.filled(count, duration);

  group('circularMeanOfMinutes', () {
    test('1. 23:30 と 0:30 の平均は 0:00', () {
      expect(circularMeanOfMinutes([23 * 60 + 30, 30])?.minuteOfDay, 0);
    });

    test('2. 22:00・23:00・0:00 の平均は 23:00', () {
      expect(circularMeanOfMinutes([22 * 60, 23 * 60, 0])?.minuteOfDay, 23 * 60);
    });

    test('3. 同じ時刻だけなら R は 1', () {
      final mean = circularMeanOfMinutes([480, 480, 480]);
      expect(mean?.minuteOfDay, 480);
      expect(mean?.concentration, closeTo(1.0, 1e-9));
    });

    test('4. 0:00 と 12:00 は R がほぼ 0 なので null', () {
      expect(circularMeanOfMinutes([0, 720]), isNull);
    });

    test('5. 空なら null', () {
      expect(circularMeanOfMinutes([]), isNull);
    });
  });

  group('mainSleepsFrom', () {
    test('6. 5 時間ちょうどはメイン睡眠、4 時間 59 分は入らない', () {
      final mains = mainSleepsFrom([
        rec('5h', t(16, 23), t(17, 4)),
        rec('4h59', t(18, 23), t(19, 3, 59)),
      ], now);
      expect(mains.map((s) => s.recordIds).toList(), [
        ['5h'],
      ]);
    });

    test('7. 記録中・途中で終わった記録（durationMinutes 0、終了は翌日 7:00）は入らない', () {
      final mains = mainSleepsFrom([
        rec('sleeping', t(25, 10), t(26, 7), durationMinutes: 0),
        rec('orphan', t(20, 23), t(21, 7), durationMinutes: 0),
      ], now);
      expect(mains, isEmpty);
    });

    test('8. 10 分以下・20 時間を超える記録は入らない（11 分・20 時間ちょうどは使う）', () {
      // 3 時間＋10 分＋3 時間：10 分の記録を除くと間が 70 分になり、まとまらない
      expect(
        mainSleepsFrom([
          rec('a', t(16, 22), t(17, 1)),
          rec('10m', t(17, 1, 30), t(17, 1, 40)),
          rec('b', t(17, 2, 10), t(17, 5, 10)),
        ], now),
        isEmpty,
      );
      // 11 分なら間が 30 分・29 分になり、1 回にまとまる
      final merged = mainSleepsFrom([
        rec('a', t(16, 22), t(17, 1)),
        rec('11m', t(17, 1, 30), t(17, 1, 41)),
        rec('b', t(17, 2, 10), t(17, 5, 10)),
      ], now);
      expect(merged.single.asleep, const Duration(hours: 6, minutes: 11));

      final long = mainSleepsFrom([
        rec('20h', t(18, 0), t(18, 20)),
        rec('20h01', t(20, 0), t(20, 20, 1)),
      ], now);
      expect(long.map((s) => s.recordIds.single).toList(), ['20h']);
    });

    test('9. 間が 60 分ならまとまり、61 分ならまとまらない（寝ていた時間に間は入らない）', () {
      final mains = mainSleepsFrom([
        rec('b', t(17, 2), t(17, 5)),
        rec('a', t(16, 22), t(17, 1)),
        rec('c', t(18, 22), t(19, 1)),
        rec('d', t(19, 2, 1), t(19, 5, 1)),
      ], now);
      expect(mains, hasLength(1));
      expect(mains.single.recordIds, ['a', 'b']);
      expect(mains.single.start, t(16, 22));
      expect(mains.single.end, t(17, 5));
      expect(mains.single.asleep, const Duration(hours: 6));
    });

    test('10. 3 時間＋3 時間（間 30 分）がまとまるとメイン睡眠になる', () {
      final sleep = mainSleepsFrom([
        rec('a', t(16, 22), t(17, 1)),
        rec('b', t(17, 1, 30), t(17, 4, 30)),
      ], now).single;
      expect(sleep.asleep, const Duration(hours: 6));
      expect(sleep.end.difference(sleep.start), const Duration(hours: 6, minutes: 30));
    });

    test('11. 終了が開始より前の古い記録は、終了を +1 日として扱う', () {
      final sleep = mainSleepsFrom([rec('old', t(16, 23), t(16, 6), durationMinutes: 420)], now).single;
      expect(sleep.end, t(17, 6));
      expect(sleep.asleep, const Duration(hours: 7));
    });

    test('12. 起床が 28 日より前の睡眠は使わない（ちょうど 28 日前は使う）', () {
      final from = now.subtract(baselineWindow);
      final inside = rec('in', from.subtract(const Duration(hours: 6)), from);
      final outside = rec(
        'out',
        from.subtract(const Duration(hours: 6, minutes: 1)),
        from.subtract(const Duration(minutes: 1)),
      );
      expect(mainSleepsFrom([inside], now), hasLength(1));
      expect(mainSleepsFrom([outside], now), isEmpty);
    });

    test('13. SleepRole が supplementary でも 6 時間ならメイン睡眠', () {
      final mains = mainSleepsFrom([rec('s', t(16, 23), t(17, 5), role: SleepRole.supplementary)], now);
      expect(mains, hasLength(1));
    });

    test('27. 重なった 2 つの記録は、寝ていた時間を二重に数えない', () {
      final sleep = mainSleepsFrom([
        rec('a', t(16, 22), t(17, 4)),  // 6 時間
        rec('b', t(17, 3), t(17, 7)),  // 4 時間（1 時間重なる）
      ], now).single;
      expect(sleep.asleep, const Duration(hours: 9));
      expect(sleep.end, t(17, 7));
    });

    test('29. 3 つの記録が間 30 分ずつで続くと、1 回にまとまる', () {
      final sleep = mainSleepsFrom([
        rec('a', t(16, 22), t(17, 0)),
        rec('b', t(17, 0, 30), t(17, 2, 30)),
        rec('c', t(17, 3), t(17, 5)),
      ], now).single;
      expect(sleep.recordIds, ['a', 'b', 'c']);
      expect(sleep.asleep, const Duration(hours: 6));
    });
  });

  group('computeSleepBaseline：時間', () {
    test('14. メイン睡眠が 4 件なら 7 時間（usedDefault）、5 件なら実際の平均', () {
      final few = computeSleepBaseline(records: nights(repeat(const Duration(hours: 8), 4)), shifts: [], now: now);
      expect(few.sampleCount, 4);
      expect(few.usedDefault, isTrue);
      expect(few.averageAsleep, defaultAverageAsleep);
      expect(few.rawAverageAsleep, const Duration(hours: 8));

      final enough = computeSleepBaseline(
        records: nights([6, 7, 8, 7, 7].map((h) => Duration(hours: h)).toList()),
        shifts: [],
        now: now,
      );
      expect(enough.sampleCount, 5);
      expect(enough.usedDefault, isFalse);
      expect(enough.averageAsleep, const Duration(hours: 7));
    });

    test('15. 平均 5 時間 30 分は 6 時間に収め、収める前の値も残す', () {
      final baseline = computeSleepBaseline(
          records: nights(repeat(const Duration(hours: 5, minutes: 30), 5)), shifts: [], now: now);
      expect(baseline.averageAsleep, averageAsleepMin);
      expect(baseline.rawAverageAsleep, const Duration(hours: 5, minutes: 30));
    });

    test('16. 平均 9 時間 30 分は 9 時間に収める', () {
      final baseline = computeSleepBaseline(
          records: nights(repeat(const Duration(hours: 9, minutes: 30), 5)), shifts: [], now: now);
      expect(baseline.averageAsleep, averageAsleepMax);
    });

    test('17. 平均 7 時間 20 分はそのまま', () {
      final baseline = computeSleepBaseline(
          records: nights(repeat(const Duration(hours: 7, minutes: 20), 5)), shifts: [], now: now);
      expect(baseline.averageAsleep, const Duration(hours: 7, minutes: 20));
    });

    test('28. 4 時間＋3 時間（間 8 時間）はメイン睡眠 0 件、短い睡眠 2 件・7 時間（除く記録は数えない）', () {
      final baseline = computeSleepBaseline(
        records: [
          rec('a', t(16, 22), t(17, 2)),
          rec('b', t(17, 10), t(17, 13)),
          rec('sleeping', t(25, 10), t(26, 7), durationMinutes: 0),
          rec('10m', t(19, 15), t(19, 15, 10)),
        ],
        shifts: [],
        now: now,
      );
      expect(baseline.sampleCount, 0);
      expect(baseline.rawAverageAsleep, isNull);
      expect(baseline.shortSleepCount, 2);
      expect(baseline.shortSleepTotal, const Duration(hours: 7));
    });
  });

  group('computeSleepBaseline：時刻', () {
    test('18. 0:00 をまたぐ入眠・起床・真ん中の円周平均', () {
      final baseline = computeSleepBaseline(
        records: [
          rec('a', t(15, 23, 30), t(16, 7, 30)),
          rec('b', t(17, 0, 30), t(17, 8, 30)),
          rec('c', t(17, 23, 30), t(18, 7, 30)),
          rec('d', t(19, 0, 30), t(19, 8, 30)),
          rec('e', t(20, 0, 0), t(20, 8, 0)),
        ],
        shifts: [],
        now: now,
      );
      expect(baseline.bedtime?.minuteOfDay, 0);
      expect(baseline.wakeTime?.minuteOfDay, 8 * 60);
      expect(baseline.midpoint?.minuteOfDay, 4 * 60);
    });

    test('19. 記録が少ないときは円周平均がすべて null', () {
      final baseline = computeSleepBaseline(records: nights(repeat(const Duration(hours: 8), 4)), shifts: [], now: now);
      expect(baseline.bedtime, isNull);
      expect(baseline.wakeTime, isNull);
      expect(baseline.midpoint, isNull);
    });
  });

  group('computeSleepBaseline：勤務明け・出勤前', () {
    test('20. 夜勤 20:00〜5:00 のあと 6:00 に寝ると勤務明け（1 時間）', () {
      final baseline = computeSleepBaseline(
        records: [rec('a', t(17, 6), t(17, 13))],
        shifts: workShiftsFromMap({t(16, 0): night20}),
        now: now,
      );
      expect(baseline.afterShift, hasLength(1));
      expect(baseline.afterShift.single.gap, const Duration(hours: 1));
      expect(baseline.afterShift.single.shift.kind, ShiftKind.night);
      expect(baseline.beforeShift, isEmpty);
    });

    test('21. 勤務の終わりからちょうど 6 時間は勤務明けに入り、6 時間 1 分は入らない', () {
      final shifts = workShiftsFromMap({t(16, 0): night20});
      final inside = computeSleepBaseline(records: [rec('a', t(17, 11), t(17, 18))], shifts: shifts, now: now);
      expect(inside.afterShift.single.gap, afterShiftMaxGap);
      final outside = computeSleepBaseline(records: [rec('a', t(17, 11, 1), t(17, 18, 1))], shifts: shifts, now: now);
      expect(outside.afterShift, isEmpty);
    });

    test('22. 7:00 に起きて 8:00 の日勤に出ると出勤前（1 時間）', () {
      final baseline = computeSleepBaseline(
        records: [rec('a', t(17, 0), t(17, 7))],
        shifts: workShiftsFromMap({t(17, 0): dayShift}),
        now: now,
      );
      expect(baseline.beforeShift.single.gap, const Duration(hours: 1));
      expect(baseline.beforeShift.single.shift.kind, ShiftKind.day);
      expect(baseline.afterShift, isEmpty);
    });

    test('23. 起床から出勤までちょうど 12 時間は出勤前に入り、12 時間 1 分は入らない', () {
      final shifts = workShiftsFromMap({t(18, 0): dayShift});
      final inside = computeSleepBaseline(records: [rec('a', t(17, 13), t(17, 20))], shifts: shifts, now: now);
      expect(inside.beforeShift.single.gap, beforeShiftMaxGap);
      final outside = computeSleepBaseline(records: [rec('a', t(17, 12, 59), t(17, 19, 59))], shifts: shifts, now: now);
      expect(outside.beforeShift, isEmpty);
    });

    test('24. 連続した夜勤のあいだの睡眠は、勤務明けと出勤前の両方に入る', () {
      final baseline = computeSleepBaseline(
        records: [rec('a', t(17, 6), t(17, 13))],
        shifts: workShiftsFromMap({t(16, 0): night20, t(17, 0): night20}),
        now: now,
      );
      expect(baseline.afterShift.single.gap, const Duration(hours: 1));
      expect(baseline.afterShift.single.shift.registeredDate, t(16, 0));
      expect(baseline.beforeShift.single.gap, const Duration(hours: 7));
      expect(baseline.beforeShift.single.shift.registeredDate, t(17, 0));
    });

    test('25. 勤務がなければ、勤務明け・出勤前とも空', () {
      final baseline = computeSleepBaseline(records: nights(repeat(const Duration(hours: 8), 5)), shifts: [], now: now);
      expect(baseline.afterShift, isEmpty);
      expect(baseline.beforeShift, isEmpty);
    });

    test('26. 前日の欄に登録した 0:00 勤務の前の睡眠も出勤前に入る', () {
      final baseline = computeSleepBaseline(
        records: [rec('a', t(16, 14), t(16, 21))],
        shifts: workShiftsFromMap({t(16, 0): night0}),
        now: now,
      );
      final gap = baseline.beforeShift.single;
      expect(gap.gap, const Duration(hours: 3));
      expect(gap.shift.startAt, t(17, 0));
      expect(gap.shift.registeredDate, t(16, 0));
      expect(gap.shift.kind, ShiftKind.night);
    });
  });
}
