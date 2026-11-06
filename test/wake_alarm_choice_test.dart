import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/wake_alarm_choice.dart';

// N19：どの起床アラームを登録するか（todayPreAlarmAt・planWakeAlarms・wakeAlarmMessages）

ShiftPatternModel _pattern({
  ShiftType type = ShiftType.work,
  TimeOfDay? start = const TimeOfDay(hour: 15, minute: 0),
}) {
  return ShiftPatternModel(
    id: 'p',
    patternName: '3番',
    patternType: type,
    startTime: start,
    endTime: const TimeOfDay(hour: 23, minute: 0),
  );
}

void main() {
  final now = DateTime(2026, 11, 5, 9, 0);
  final manual = DateTime(2026, 11, 5, 12, 5);
  final pre = DateTime(2026, 11, 5, 14, 30);

  group('todayPreAlarmAt', () {
    DateTime? at({int minutes = 30, ShiftPatternModel? pattern, DateTime? time}) =>
        todayPreAlarmAt(now: time ?? now, minutesBefore: minutes, pattern: pattern);

    test('出勤日で先なら、開始時刻から分数を引いた時刻', () {
      expect(at(pattern: _pattern()), pre);
    });

    test('分数が 0 以下なら null', () {
      expect(at(minutes: 0, pattern: _pattern()), isNull);
      expect(at(minutes: -1, pattern: _pattern()), isNull);
    });

    test('シフトなしなら null', () {
      expect(at(), isNull);
    });

    test('出勤以外（休日・有休・半休）なら null', () {
      for (final type in [ShiftType.dayOff, ShiftType.vacation, ShiftType.halfVacation]) {
        expect(at(pattern: _pattern(type: type)), isNull, reason: '$type');
      }
    });

    test('削除済みのパターンなら null', () {
      expect(at(pattern: ShiftPatternModel.deleted('x')), isNull);
    });

    test('出勤時刻がなければ null', () {
      expect(
        todayPreAlarmAt(
          now: now,
          minutesBefore: 30,
          pattern: ShiftPatternModel(id: 'p', patternName: '3番', patternType: ShiftType.work),
        ),
        isNull,
      );
    });

    test('すでに過ぎていれば null', () {
      expect(at(pattern: _pattern(), time: DateTime(2026, 11, 5, 14, 31)), isNull);
    });

    test('ちょうど今なら null', () {
      expect(at(pattern: _pattern(), time: pre), isNull);
    });
  });

  group('planWakeAlarms', () {
    test('手動なし・pre なし → なし', () {
      expect(planWakeAlarms(manualWakeAt: null, shiftPreAlarmAt: null), WakeAlarmPlan.none);
    });

    test('手動なし・pre あり → pre だけ', () {
      expect(planWakeAlarms(manualWakeAt: null, shiftPreAlarmAt: pre), WakeAlarmPlan.preOnly);
    });

    test('手動あり・pre なし（過ぎている・読めなかったを含む） → main だけ', () {
      expect(planWakeAlarms(manualWakeAt: manual, shiftPreAlarmAt: null), WakeAlarmPlan.mainOnly);
    });

    test('手動のほうが早い → main と pre の 2 本', () {
      expect(planWakeAlarms(manualWakeAt: manual, shiftPreAlarmAt: pre), WakeAlarmPlan.mainAndPre);
    });

    test('同じ時刻 → pre だけ', () {
      expect(planWakeAlarms(manualWakeAt: pre, shiftPreAlarmAt: pre), WakeAlarmPlan.preOnly);
    });

    test('pre のほうが早い → pre だけ', () {
      expect(
        planWakeAlarms(manualWakeAt: DateTime(2026, 11, 5, 16, 0), shiftPreAlarmAt: pre),
        WakeAlarmPlan.preOnly,
      );
    });
  });

  group('wakeAlarmMessages', () {
    List<({String text, Color? color})> messages(
      WakeAlarmPlan plan, {
      DateTime? manualAt,
      DateTime? preAt,
      int minutesBefore = 30,
      String? mainError,
      String? preError,
      bool shiftsReadFailed = false,
      bool alarmDisabled = false,
      DateTime? time,
    }) {
      return wakeAlarmMessages(WakeAlarmRegistrationResult(
        now: time ?? now,
        plan: plan,
        manualWakeAt: manualAt,
        preAlarmAt: preAt,
        minutesBefore: minutesBefore,
        mainError: mainError,
        preError: preError,
        shiftsReadFailed: shiftsReadFailed,
        alarmDisabled: alarmDisabled,
      ));
    }

    test('pre だけ', () {
      final result = messages(WakeAlarmPlan.preOnly, preAt: pre);
      expect(result.single.text, '⏰ 出勤前アラーム 14:30 に鳴ります');
      expect(result.single.color, isNull);
    });

    test('手動が pre より遅く、出勤時刻より前 → 理由を出す', () {
      final result = messages(WakeAlarmPlan.preOnly, manualAt: DateTime(2026, 11, 5, 14, 45), preAt: pre);
      expect(result.single.text, '⏰ 設定した起床時刻 14:45 は出勤前アラーム（30分前）より遅いため、14:30 に鳴ります');
      expect(result.single.color, isNull);
    });

    test('手動が pre と同時刻 → 同じ文言', () {
      final result = messages(WakeAlarmPlan.preOnly, manualAt: pre, preAt: pre);
      expect(result.single.text, '⏰ 設定した起床時刻 14:30 は出勤前アラーム（30分前）より遅いため、14:30 に鳴ります');
    });

    test('手動が出勤時刻と同時刻 → 出社予定時刻の文言', () {
      final result = messages(WakeAlarmPlan.preOnly, manualAt: DateTime(2026, 11, 5, 15, 0), preAt: pre);
      expect(result.single.text, '⏰ 設定した起床時刻 15:00 は出社予定時刻（15:00）より遅いため、出勤前アラーム（30分前）の 14:30 に鳴ります');
    });

    test('手動が出勤時刻より後 → 出社予定時刻の文言（分数は設定の値）', () {
      final result = messages(
        WakeAlarmPlan.preOnly,
        manualAt: DateTime(2026, 11, 5, 16, 0),
        preAt: DateTime(2026, 11, 5, 14, 0),
        minutesBefore: 60,
      );
      expect(result.single.text, '⏰ 設定した起床時刻 16:00 は出社予定時刻（15:00）より遅いため、出勤前アラーム（60分前）の 14:00 に鳴ります');
    });

    test('手動が pre より遅くても、登録に失敗したら理由も「鳴ります」も出さない', () {
      final result = messages(
        WakeAlarmPlan.preOnly,
        manualAt: DateTime(2026, 11, 5, 16, 0),
        preAt: pre,
        preError: '⚠️ 失敗',
      );
      expect(result.single.text, '⚠️ 失敗');
    });

    test('2 本', () {
      final result = messages(WakeAlarmPlan.mainAndPre, manualAt: manual, preAt: pre);
      expect(result.single.text, '⏰ 起床アラーム 12:05 と出勤前アラーム 14:30 に鳴ります');
      expect(result.single.color, isNull);
    });

    test('main だけ・なし・OFF は案内なし', () {
      expect(messages(WakeAlarmPlan.mainOnly, manualAt: manual), isEmpty);
      expect(messages(WakeAlarmPlan.none), isEmpty);
      expect(messages(WakeAlarmPlan.none, manualAt: manual, alarmDisabled: true), isEmpty);
    });

    test('N18：今と同じ時・分で明日になった main は知らせる', () {
      final result = messages(WakeAlarmPlan.mainOnly, manualAt: DateTime(2026, 11, 6, 9, 0));
      expect(result.single.text, '⏰ 起床時刻 9:00 は今と同じ時刻のため、明日 9:00 に設定しました');
    });

    test('pre だけで失敗 → ⚠️ だけで「鳴ります」は出さない', () {
      final result = messages(WakeAlarmPlan.preOnly, preAt: pre, preError: '⚠️ 失敗');
      expect(result.single.text, '⚠️ 失敗');
      expect(result.single.color, Colors.orange);
    });

    test('main だけで失敗 → ⚠️', () {
      final result = messages(WakeAlarmPlan.mainOnly, manualAt: manual, mainError: '⚠️ 失敗');
      expect(result.single.text, '⚠️ 失敗');
      expect(result.single.color, Colors.orange);
    });

    test('2 本で pre だけ失敗 → main は登録済みと知らせる', () {
      final result = messages(WakeAlarmPlan.mainAndPre, manualAt: manual, preAt: pre, preError: 'x');
      expect(result.single.text, '⚠️ 出勤前アラームを登録できませんでした。起床アラーム 12:05 は登録済みです');
      expect(result.single.color, Colors.orange);
    });

    test('2 本で main だけ失敗 → pre は登録済みと知らせる', () {
      final result = messages(WakeAlarmPlan.mainAndPre, manualAt: manual, preAt: pre, mainError: 'x');
      expect(result.single.text, '⚠️ 起床アラームを登録できませんでした。出勤前アラーム 14:30 は登録済みです');
    });

    test('2 本とも失敗 → 同じ文言は 1 つにまとめる', () {
      final same = messages(WakeAlarmPlan.mainAndPre, manualAt: manual, preAt: pre, mainError: 'x', preError: 'x');
      expect(same.map((m) => m.text), ['x']);
      final different = messages(WakeAlarmPlan.mainAndPre, manualAt: manual, preAt: pre, mainError: 'x', preError: 'y');
      expect(different.map((m) => m.text), ['x', 'y']);
    });

    test('シフトを読めなかった：手動あり → main は登録済み', () {
      final result = messages(WakeAlarmPlan.mainOnly, manualAt: manual, shiftsReadFailed: true);
      expect(result.single.text, '⚠️ シフトを読めなかったため、出勤前アラームを登録できませんでした。手動の起床アラームは登録済みです');
      expect(result.single.color, Colors.orange);
    });

    test('シフトを読めなかった：手動なし', () {
      final result = messages(WakeAlarmPlan.none, shiftsReadFailed: true);
      expect(result.single.text, '⚠️ シフトを読めなかったため、出勤前アラームを登録できませんでした');
    });

    test('シフトを読めず main も失敗 → 「登録済み」とは出さない', () {
      final result = messages(WakeAlarmPlan.mainOnly, manualAt: manual, shiftsReadFailed: true, mainError: '⚠️ 失敗');
      expect(result.single.text, '⚠️ 失敗');
    });
  });
}
