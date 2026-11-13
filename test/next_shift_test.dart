import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
