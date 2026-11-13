import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/wake_pre_cancel.dart';

// N180 2/3：registeredPreAlarmAt・shouldCancelPreOnWake のテスト

void main() {
  // 2026-11-16 は月曜
  final monday = DateTime(2026, 11, 16);
  DateTime mon(int hour, int minute) => DateTime(2026, 11, 16, hour, minute);

  ShiftPatternModel work(int hour, int minute) => ShiftPatternModel(
        id: 'p_$hour$minute',
        patternName: '勤務',
        patternType: ShiftType.work,
        startTime: TimeOfDay(hour: hour, minute: minute),
        endTime: const TimeOfDay(hour: 17, minute: 0),
      );

  group('registeredPreAlarmAt', () {
    test('1. 出勤：登録した日＋開始時刻−分数', () {
      expect(registeredPreAlarmAt(shiftDate: monday, pattern: work(8, 0), minutesBefore: 30), mon(7, 30));
    });

    test('2. 今の登録の式のまま：月曜の欄の 0:00 開始・60 分前は日曜 23:00（N180 3/3 で直す）', () {
      expect(
        registeredPreAlarmAt(shiftDate: monday, pattern: work(0, 0), minutesBefore: 60),
        DateTime(2026, 11, 15, 23, 0),
      );
    });

    test('3. 登録した日の時刻は捨てる', () {
      expect(
        registeredPreAlarmAt(shiftDate: mon(17, 45), pattern: work(16, 0), minutesBefore: 30),
        mon(15, 30),
      );
    });

    test('4. 分数が 0 以下・シフトなし・削除済み・開始時刻なしは null', () {
      expect(registeredPreAlarmAt(shiftDate: monday, pattern: work(8, 0), minutesBefore: 0), isNull);
      expect(registeredPreAlarmAt(shiftDate: monday, pattern: work(8, 0), minutesBefore: -5), isNull);
      expect(registeredPreAlarmAt(shiftDate: monday, pattern: null, minutesBefore: 30), isNull);
      expect(
        registeredPreAlarmAt(shiftDate: monday, pattern: ShiftPatternModel.deleted('gone'), minutesBefore: 30),
        isNull,
      );
      expect(
        registeredPreAlarmAt(
          shiftDate: monday,
          pattern: ShiftPatternModel(id: 'p', patternName: '時刻なし', patternType: ShiftType.work),
          minutesBefore: 30,
        ),
        isNull,
      );
    });

    test('5. 休日・有休・半休は開始時刻があっても null', () {
      for (final type in [ShiftType.dayOff, ShiftType.vacation, ShiftType.halfVacation]) {
        final pattern = ShiftPatternModel(
          id: 'p',
          patternName: '休み',
          patternType: type,
          startTime: const TimeOfDay(hour: 8, minute: 0),
          endTime: const TimeOfDay(hour: 12, minute: 0),
        );
        expect(registeredPreAlarmAt(shiftDate: monday, pattern: pattern, minutesBefore: 30), isNull, reason: '$type');
      }
    });
  });

  group('shouldCancelPreOnWake', () {
    test('1. 日勤：朝 6:00 に起き、7:00 の pre は取り消す', () {
      expect(shouldCancelPreOnWake(wakeUpTime: mon(6, 0), preAlarmAt: mon(7, 0)), isTrue);
    });

    test('2. 夜勤明け：17:00 に起き、23:00 の pre は残す', () {
      expect(shouldCancelPreOnWake(wakeUpTime: mon(17, 0), preAlarmAt: mon(23, 0)), isFalse);
    });

    test('3. 準夜勤：7:00 に起き、15:30 の pre は残す', () {
      expect(shouldCancelPreOnWake(wakeUpTime: mon(7, 0), preAlarmAt: mon(15, 30)), isFalse);
    });

    test('4. 境目：ちょうど 3 時間後は取り消し、3 時間 1 分後は残す', () {
      expect(shouldCancelPreOnWake(wakeUpTime: mon(6, 0), preAlarmAt: mon(9, 0)), isTrue);
      expect(shouldCancelPreOnWake(wakeUpTime: mon(6, 0), preAlarmAt: mon(9, 1)), isFalse);
    });

    test('5. すでに過ぎた pre（起床と同じ時刻を含む）は取り消す', () {
      expect(shouldCancelPreOnWake(wakeUpTime: mon(8, 0), preAlarmAt: mon(7, 30)), isTrue);
      expect(shouldCancelPreOnWake(wakeUpTime: mon(8, 0), preAlarmAt: mon(8, 0)), isTrue);
    });

    test('6. 日をまたぐ：22:00 に起き、翌 0:30 の pre は取り消し、翌 1:01 は残す', () {
      expect(shouldCancelPreOnWake(wakeUpTime: mon(22, 0), preAlarmAt: DateTime(2026, 11, 17, 0, 30)), isTrue);
      expect(shouldCancelPreOnWake(wakeUpTime: mon(22, 0), preAlarmAt: DateTime(2026, 11, 17, 1, 1)), isFalse);
    });

    test('7. pre がなければ（null）取り消さない', () {
      expect(shouldCancelPreOnWake(wakeUpTime: mon(6, 0), preAlarmAt: null), isFalse);
    });

    test('8. 今の 24 時間ずれた登録：月曜の欄 0:00・60 分前（日曜 23:00）は月曜 17:00 の起床で取り消す（過ぎているので害がない）', () {
      final preAt = registeredPreAlarmAt(shiftDate: monday, pattern: work(0, 0), minutesBefore: 60);
      expect(shouldCancelPreOnWake(wakeUpTime: mon(17, 0), preAlarmAt: preAt), isTrue);
    });
  });
}
