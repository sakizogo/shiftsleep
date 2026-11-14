import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/next_shift.dart';

// N180 1/3：shiftStartDateTime・shiftEndDateTime のテスト
// 例の勤務：3 交代 8:00〜17:00／16:00〜1:00／0:00〜9:00、2 交代 8:00〜17:00／20:00〜5:00

void main() {
  // 2026-11-16 は月曜
  final monday = DateTime(2026, 11, 16);

  TimeOfDay hm(int hour, int minute) => TimeOfDay(hour: hour, minute: minute);

  group('shiftStartDateTime', () {
    test('1. 境目：4:59 開始は翌日、5:00 開始は当日', () {
      expect(shiftStartDateTime(monday, hm(4, 59)), DateTime(2026, 11, 17, 4, 59));
      expect(shiftStartDateTime(monday, hm(5, 0)), DateTime(2026, 11, 16, 5, 0));
    });

    test('2. 月曜の欄の 0:00 開始は火曜の 0:00 に始まる', () {
      expect(shiftStartDateTime(monday, hm(0, 0)), DateTime(2026, 11, 17, 0, 0));
    });

    test('3. 日勤 8:00・準夜勤 16:00・夜勤 20:00 は当日に始まる', () {
      expect(shiftStartDateTime(monday, hm(8, 0)), DateTime(2026, 11, 16, 8, 0));
      expect(shiftStartDateTime(monday, hm(16, 0)), DateTime(2026, 11, 16, 16, 0));
      expect(shiftStartDateTime(monday, hm(20, 0)), DateTime(2026, 11, 16, 20, 0));
    });

    test('4. 登録した日の時刻は捨てる', () {
      expect(shiftStartDateTime(DateTime(2026, 11, 16, 23, 30), hm(0, 0)), DateTime(2026, 11, 17, 0, 0));
      expect(shiftStartDateTime(DateTime(2026, 11, 16, 23, 30), hm(8, 0)), DateTime(2026, 11, 16, 8, 0));
    });

    test('5. 12/31 の欄の 0:00 開始は翌年 1/1 の 0:00', () {
      expect(shiftStartDateTime(DateTime(2026, 12, 31), hm(0, 0)), DateTime(2027, 1, 1, 0, 0));
    });

    test('6. 2028/2/28 の欄の 0:00 開始は 2/29（うるう年）', () {
      expect(shiftStartDateTime(DateTime(2028, 2, 28), hm(0, 0)), DateTime(2028, 2, 29, 0, 0));
    });

    test('7. 境目は引数で変えられる', () {
      expect(shiftStartDateTime(monday, hm(5, 30), boundary: hm(6, 0)), DateTime(2026, 11, 17, 5, 30));
      expect(shiftStartDateTime(monday, hm(0, 0), boundary: hm(0, 0)), DateTime(2026, 11, 16, 0, 0));
    });
  });

  group('startsOnNextDay（N180 3/3）', () {
    test('0:00・4:59 は翌日、5:00・23:59 は当日', () {
      expect(startsOnNextDay(hm(0, 0)), isTrue);
      expect(startsOnNextDay(hm(4, 59)), isTrue);
      expect(startsOnNextDay(hm(5, 0)), isFalse);
      expect(startsOnNextDay(hm(23, 59)), isFalse);
    });

    test('境目は引数で変えられる', () {
      expect(startsOnNextDay(hm(5, 30), boundary: hm(6, 0)), isTrue);
      expect(startsOnNextDay(hm(0, 0), boundary: hm(0, 0)), isFalse);
    });
  });

  group('shiftEndDateTime', () {
    DateTime? end(TimeOfDay start, TimeOfDay? endTime, {DateTime? date}) =>
        shiftEndDateTime(shiftStartDateTime(date ?? monday, start), endTime);

    test('1. 8:00〜17:00 は当日に終わる', () {
      expect(end(hm(8, 0), hm(17, 0)), DateTime(2026, 11, 16, 17, 0));
    });

    test('2. 16:00〜1:00 は翌日の 1:00 に終わる', () {
      expect(end(hm(16, 0), hm(1, 0)), DateTime(2026, 11, 17, 1, 0));
    });

    test('3. 月曜の欄の 0:00〜9:00 は火曜の 9:00 に終わる', () {
      expect(end(hm(0, 0), hm(9, 0)), DateTime(2026, 11, 17, 9, 0));
    });

    test('4. 20:00〜5:00 は翌日の 5:00 に終わる', () {
      expect(end(hm(20, 0), hm(5, 0)), DateTime(2026, 11, 17, 5, 0));
    });

    test('5. 開始＝終了は 24 時間の勤務（翌日の同じ時刻に終わる）', () {
      expect(end(hm(8, 0), hm(8, 0)), DateTime(2026, 11, 17, 8, 0));
      expect(end(hm(0, 0), hm(0, 0)), DateTime(2026, 11, 18, 0, 0));
    });

    test('6. 終了が null なら null', () {
      expect(end(hm(8, 0), null), isNull);
    });

    test('7. 12/31 の 16:00〜1:00 は翌年 1/1 に、12/31 の欄の 0:00〜9:00 は 1/1 の 9:00 に終わる', () {
      expect(end(hm(16, 0), hm(1, 0), date: DateTime(2026, 12, 31)), DateTime(2027, 1, 1, 1, 0));
      expect(end(hm(0, 0), hm(9, 0), date: DateTime(2026, 12, 31)), DateTime(2027, 1, 1, 9, 0));
    });

    test('8. 2028/2/28 の欄の 0:00〜9:00 は 2/29 の 9:00、20:00〜5:00 も 2/29 の 5:00 に終わる', () {
      expect(end(hm(0, 0), hm(9, 0), date: DateTime(2028, 2, 28)), DateTime(2028, 2, 29, 9, 0));
      expect(end(hm(20, 0), hm(5, 0), date: DateTime(2028, 2, 28)), DateTime(2028, 2, 29, 5, 0));
    });
  });

  // ===== A-1（1/2）：shiftKindOf・workShiftsFromMap・nextWorkShift・previousWorkShift =====
  // パターンの作り方は alarm_reschedule_test.dart と同じ
  final dayOff = ShiftPatternModel(id: 'default_dayoff', patternName: '休日', patternType: ShiftType.dayOff, colorIndex: 0);
  final vacation = ShiftPatternModel(id: 'default_vacation_1day', patternName: '有休', patternType: ShiftType.vacation, colorIndex: 3);
  final halfVacation = ShiftPatternModel(id: 'default_vacation_half', patternName: '半休', patternType: ShiftType.halfVacation, colorIndex: 4);
  ShiftPatternModel work(String id, TimeOfDay? start, TimeOfDay? end) => ShiftPatternModel(
        id: id,
        patternName: id,
        patternType: ShiftType.work,
        startTime: start,
        endTime: end,
        colorIndex: 1,
      );
  final dayShift = work('p_day', hm(8, 0), hm(17, 0));  // 日勤 8:00〜17:00
  final night20 = work('p_night20', hm(20, 0), hm(5, 0));  // 夜勤 20:00〜5:00
  final night0 = work('p_night0', hm(0, 0), hm(9, 0));  // 夜勤 0:00〜9:00（前日の欄に登録）
  final long24 = work('p_long24', hm(20, 0), hm(20, 0));  // 24 時間 20:00〜20:00

  final sunday = DateTime(2026, 11, 15);
  final tuesday = DateTime(2026, 11, 17);
  final wednesday = DateTime(2026, 11, 18);

  group('shiftKindOf（A-1）', () {
    test('1. 境目：4:59 は夜勤、5:00 は日勤', () {
      expect(shiftKindOf(hm(4, 59)), ShiftKind.night);
      expect(shiftKindOf(hm(5, 0)), ShiftKind.day);
    });

    test('2. 境目：11:59 は日勤、12:00 は準夜勤', () {
      expect(shiftKindOf(hm(11, 59)), ShiftKind.day);
      expect(shiftKindOf(hm(12, 0)), ShiftKind.evening);
    });

    test('3. 境目：19:59 は準夜勤、20:00 は夜勤', () {
      expect(shiftKindOf(hm(19, 59)), ShiftKind.evening);
      expect(shiftKindOf(hm(20, 0)), ShiftKind.night);
    });

    test('4. 0:00・23:59 は夜勤', () {
      expect(shiftKindOf(hm(0, 0)), ShiftKind.night);
      expect(shiftKindOf(hm(23, 59)), ShiftKind.night);
    });
  });

  group('workShiftsFromMap（A-1）', () {
    test('5. 休日・有休・半休・削除済み・null だけなら空', () {
      final map = <DateTime, ShiftPatternModel?>{
        monday: dayOff,
        tuesday: vacation,
        wednesday: halfVacation,
        DateTime(2026, 11, 19): ShiftPatternModel.deleted('p_gone'),
        DateTime(2026, 11, 20): null,
      };
      expect(workShiftsFromMap(map), isEmpty);
    });

    test('6. 開始のない出勤・終了のない出勤は入らない', () {
      final map = <DateTime, ShiftPatternModel?>{
        monday: work('p_no_start', null, hm(17, 0)),
        tuesday: work('p_no_end', hm(8, 0), null),
      };
      expect(workShiftsFromMap(map), isEmpty);
    });

    test('7. 月曜の欄の 0:00〜9:00 は火曜 0:00〜9:00 の夜勤（登録した日は月曜）', () {
      final shifts = workShiftsFromMap({monday: night0});
      expect(shifts, hasLength(1));
      expect(shifts.single.registeredDate, monday);
      expect(shifts.single.pattern, same(night0));
      expect(shifts.single.startAt, DateTime(2026, 11, 17, 0, 0));
      expect(shifts.single.endAt, DateTime(2026, 11, 17, 9, 0));
      expect(shifts.single.kind, ShiftKind.night);
    });

    test('8. 20:00〜5:00 は翌日の 5:00 に終わる', () {
      final shift = workShiftsFromMap({monday: night20}).single;
      expect(shift.startAt, DateTime(2026, 11, 16, 20, 0));
      expect(shift.endAt, DateTime(2026, 11, 17, 5, 0));
      expect(shift.kind, ShiftKind.night);
    });

    test('9. 開始の早い順（前日の欄の 0:00 が当日の欄の 8:00 より先）', () {
      final shifts = workShiftsFromMap({tuesday: dayShift, monday: night0});
      expect(shifts.map((s) => s.startAt).toList(), [
        DateTime(2026, 11, 17, 0, 0),
        DateTime(2026, 11, 17, 8, 0),
      ]);
      expect(shifts.map((s) => s.registeredDate).toList(), [monday, tuesday]);
      expect(shifts.last.kind, ShiftKind.day);
    });
  });

  group('nextWorkShift（A-1）', () {
    test('10. 勤務中は飛ばして、その次を返す', () {
      final shifts = workShiftsFromMap({monday: dayShift, tuesday: dayShift});
      expect(nextWorkShift(DateTime(2026, 11, 16, 10, 0), shifts)?.startAt, DateTime(2026, 11, 17, 8, 0));
    });

    test('11. ちょうど now に始まる勤務は勤務中なので含めない', () {
      final shifts = workShiftsFromMap({monday: dayShift, tuesday: dayShift});
      expect(nextWorkShift(DateTime(2026, 11, 16, 8, 0), shifts)?.startAt, DateTime(2026, 11, 17, 8, 0));
    });

    test('12. ちょうど 48 時間後に始まる勤務は含め、48 時間 1 分後なら null', () {
      final shifts = workShiftsFromMap({wednesday: dayShift});
      expect(nextWorkShift(DateTime(2026, 11, 16, 8, 0), shifts)?.startAt, DateTime(2026, 11, 18, 8, 0));
      expect(nextWorkShift(DateTime(2026, 11, 16, 7, 59), shifts), isNull);
    });

    test('13. 前日（月曜）の欄に登録した 0:00 勤務が、火曜 0:00 に始まる次の勤務として出る', () {
      final shift = nextWorkShift(DateTime(2026, 11, 16, 23, 30), workShiftsFromMap({monday: night0}));
      expect(shift?.startAt, DateTime(2026, 11, 17, 0, 0));
      expect(shift?.registeredDate, monday);
    });

    test('14. 休日・有休だけの期間は null（前の勤務も null）', () {
      final shifts = workShiftsFromMap({monday: dayOff, tuesday: vacation, wednesday: dayOff});
      final now = DateTime(2026, 11, 16, 0, 0);
      expect(nextWorkShift(now, shifts), isNull);
      expect(previousWorkShift(now, shifts), isNull);
    });

    test('15. 半休の日の出勤も勤務として数える（半休パターンの行そのものは勤務ではない）', () {
      // 半休は有休の使用に入り、shifts には出勤が残る（N77）。古いデータの半休パターンの行は勤務に入らない
      final shifts = workShiftsFromMap({monday: halfVacation, tuesday: dayShift});
      expect(shifts, hasLength(1));
      expect(nextWorkShift(DateTime(2026, 11, 16, 6, 0), shifts)?.startAt, DateTime(2026, 11, 17, 8, 0));
    });
  });

  group('previousWorkShift（A-1）', () {
    test('16. ちょうど now に終わった勤務は含める', () {
      final shifts = workShiftsFromMap({monday: dayShift});
      expect(previousWorkShift(DateTime(2026, 11, 16, 17, 0), shifts)?.endAt, DateTime(2026, 11, 16, 17, 0));
    });

    test('17. 勤務中は前の勤務に入れない', () {
      final shifts = workShiftsFromMap({monday: dayShift, tuesday: dayShift});
      expect(previousWorkShift(DateTime(2026, 11, 17, 10, 0), shifts)?.endAt, DateTime(2026, 11, 16, 17, 0));
    });

    test('18. ちょうど 48 時間前に終わった勤務は含め、48 時間 1 分前なら null', () {
      final shifts = workShiftsFromMap({monday: dayShift});
      expect(previousWorkShift(DateTime(2026, 11, 18, 17, 0), shifts)?.endAt, DateTime(2026, 11, 16, 17, 0));
      expect(previousWorkShift(DateTime(2026, 11, 18, 17, 1), shifts), isNull);
    });

    test('19. 夜勤 20:00〜5:00 が終わった直後はその夜勤、終わる 1 分前は null', () {
      final shifts = workShiftsFromMap({monday: night20});
      expect(previousWorkShift(DateTime(2026, 11, 17, 5, 0), shifts)?.pattern, same(night20));
      expect(previousWorkShift(DateTime(2026, 11, 17, 4, 59), shifts), isNull);
    });

    test('20. 勤務が重なるときは、終わりの遅いほう', () {
      // 日曜 20:00〜月曜 20:00（24 時間）と、月曜 8:00〜17:00（始まりは遅いが先に終わる）
      final shifts = workShiftsFromMap({sunday: long24, monday: dayShift});
      final shift = previousWorkShift(DateTime(2026, 11, 16, 21, 0), shifts);
      expect(shift?.pattern, same(long24));
      expect(shift?.endAt, DateTime(2026, 11, 16, 20, 0));
    });

    test('21. 12/31 の欄の 0:00 開始は年をまたぎ、2028/2/28 の欄の 0:00 開始は 2/29（次・前とも）', () {
      final yearEnd = workShiftsFromMap({DateTime(2026, 12, 31): night0});
      expect(nextWorkShift(DateTime(2026, 12, 31, 23, 0), yearEnd)?.startAt, DateTime(2027, 1, 1, 0, 0));
      expect(previousWorkShift(DateTime(2027, 1, 1, 9, 0), yearEnd)?.endAt, DateTime(2027, 1, 1, 9, 0));

      final leap = workShiftsFromMap({DateTime(2028, 2, 28): night0});
      expect(nextWorkShift(DateTime(2028, 2, 28, 22, 0), leap)?.startAt, DateTime(2028, 2, 29, 0, 0));
      expect(previousWorkShift(DateTime(2028, 2, 29, 9, 0), leap)?.endAt, DateTime(2028, 2, 29, 9, 0));
    });
  });
}
