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

    // N180 3/3：今日の欄の 0:00〜4:59 開始は翌日に始まる
    test('N180 3/3：今日の欄の 0:00 開始・60 分前は、今日の昼に寝ても今日 23:00', () {
      final zero = _pattern(start: const TimeOfDay(hour: 0, minute: 0));
      expect(at(minutes: 60, pattern: zero, time: DateTime(2026, 11, 5, 14, 0)), DateTime(2026, 11, 5, 23, 0));
      expect(at(minutes: 60, pattern: zero, time: DateTime(2026, 11, 5, 23, 0)), isNull);
    });

    test('N180 3/3：境目：4:59 開始は翌日、5:00 開始は今日', () {
      final early = DateTime(2026, 11, 5, 3, 0);
      expect(at(pattern: _pattern(start: const TimeOfDay(hour: 4, minute: 59)), time: early),
          DateTime(2026, 11, 6, 4, 29));
      expect(at(pattern: _pattern(start: const TimeOfDay(hour: 5, minute: 0)), time: early),
          DateTime(2026, 11, 5, 4, 30));
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

    // N118 2b：設定を読めなかったときは、手動起床があれば必ず main も登録する
    test('keepMain：pre のほうが早い・同じ時刻でも 2 本', () {
      expect(
        planWakeAlarms(manualWakeAt: DateTime(2026, 11, 5, 16, 0), shiftPreAlarmAt: pre, keepMain: true),
        WakeAlarmPlan.mainAndPre,
      );
      expect(planWakeAlarms(manualWakeAt: pre, shiftPreAlarmAt: pre, keepMain: true), WakeAlarmPlan.mainAndPre);
    });

    test('keepMain：手動のほうが早い → 2 本（変わらない）', () {
      expect(planWakeAlarms(manualWakeAt: manual, shiftPreAlarmAt: pre, keepMain: true), WakeAlarmPlan.mainAndPre);
    });

    test('keepMain：手動なし・pre なしは変わらない', () {
      expect(planWakeAlarms(manualWakeAt: null, shiftPreAlarmAt: pre, keepMain: true), WakeAlarmPlan.preOnly);
      expect(planWakeAlarms(manualWakeAt: null, shiftPreAlarmAt: null, keepMain: true), WakeAlarmPlan.none);
      expect(planWakeAlarms(manualWakeAt: manual, shiftPreAlarmAt: null, keepMain: true), WakeAlarmPlan.mainOnly);
    });
  });

  group('todayWorkStartAt', () {
    DateTime? at(ShiftPatternModel? pattern, {DateTime? time}) =>
        todayWorkStartAt(now: time ?? now, pattern: pattern);

    test('出勤で出勤時刻が先なら、今日の出勤時刻', () {
      expect(at(_pattern()), DateTime(2026, 11, 5, 15, 0));
    });

    test('pre が過ぎていても、出勤時刻が先なら出勤時刻', () {
      expect(at(_pattern(), time: DateTime(2026, 11, 5, 14, 50)), DateTime(2026, 11, 5, 15, 0));
    });

    test('出勤時刻ちょうど・過ぎていれば null', () {
      expect(at(_pattern(), time: DateTime(2026, 11, 5, 15, 0)), isNull);
      expect(at(_pattern(), time: DateTime(2026, 11, 5, 15, 1)), isNull);
    });

    test('N180 3/3：今日の欄の 0:00 開始は明日 0:00（今日の 23:30 でもまだ先）', () {
      final zero = _pattern(start: const TimeOfDay(hour: 0, minute: 0));
      expect(at(zero), DateTime(2026, 11, 6, 0, 0));
      expect(at(zero, time: DateTime(2026, 11, 5, 23, 30)), DateTime(2026, 11, 6, 0, 0));
    });

    test('出勤以外・削除済み・出勤時刻なし・シフトなしは null', () {
      for (final type in [ShiftType.dayOff, ShiftType.vacation, ShiftType.halfVacation]) {
        expect(at(_pattern(type: type)), isNull, reason: '$type');
      }
      expect(at(ShiftPatternModel.deleted('x')), isNull);
      expect(at(ShiftPatternModel(id: 'p', patternName: '3番', patternType: ShiftType.work)), isNull);
      expect(at(null), isNull);
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
      bool settingsReadFailed = false,
      bool patternMissing = false,
      DateTime? workStartAt,
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
        settingsReadFailed: settingsReadFailed,
        patternMissing: patternMissing,
        todayWorkStartAt: workStartAt,
      ));
    }

    const fallback = '⚠️ 設定を読めなかったため、既定値（出勤 30 分前・デフォルト音）で登録しました';

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

    // N118 2b：設定を読めなかったとき
    group('設定を読めなかった', () {
      test('main だけ登録できた → 既定値で登録しました', () {
        final result = messages(WakeAlarmPlan.mainOnly, manualAt: manual, settingsReadFailed: true);
        expect(result.single.text, fallback);
        expect(result.single.color, Colors.orange);
      });

      test('2 本登録できた → 既定値の ⚠️ のあとに ⏰', () {
        final result = messages(WakeAlarmPlan.mainAndPre, manualAt: manual, preAt: pre, settingsReadFailed: true);
        expect(result.map((m) => m.text), [fallback, '⏰ 起床アラーム 12:05 と出勤前アラーム 14:30 に鳴ります']);
        expect(result.map((m) => m.color), [Colors.orange, null]);
      });

      test('pre だけ登録できた → 既定値の ⚠️ のあとに ⏰', () {
        final result = messages(WakeAlarmPlan.preOnly, preAt: pre, settingsReadFailed: true);
        expect(result.map((m) => m.text), [fallback, '⏰ 出勤前アラーム 14:30 に鳴ります']);
      });

      test('2 本で片方だけ失敗 → 既定値の ⚠️ と、もう片方は登録済み', () {
        final result = messages(WakeAlarmPlan.mainAndPre, manualAt: manual, preAt: pre, preError: 'x', settingsReadFailed: true);
        expect(result.map((m) => m.text), [fallback, '⚠️ 出勤前アラームを登録できませんでした。起床アラーム 12:05 は登録済みです']);
      });

      test('pre だけで失敗 → 「既定値で登録しました」は出さない', () {
        final result = messages(WakeAlarmPlan.preOnly, preAt: pre, preError: '⚠️ 失敗', settingsReadFailed: true);
        expect(result.single.text, '⚠️ 失敗');
      });

      test('main だけで失敗 → 「既定値で登録しました」は出さない', () {
        final result = messages(WakeAlarmPlan.mainOnly, manualAt: manual, mainError: '⚠️ 失敗', settingsReadFailed: true);
        expect(result.single.text, '⚠️ 失敗');
      });

      test('2 本とも失敗 → 「既定値で登録しました」は出さない', () {
        final result = messages(
          WakeAlarmPlan.mainAndPre,
          manualAt: manual,
          preAt: pre,
          mainError: 'x',
          preError: 'y',
          settingsReadFailed: true,
        );
        expect(result.map((m) => m.text), ['x', 'y']);
      });

      test('none で今日の出勤がまだ先 → pre の時刻は過ぎていると知らせる', () {
        final result = messages(
          WakeAlarmPlan.none,
          settingsReadFailed: true,
          workStartAt: DateTime(2026, 11, 5, 9, 15),
        );
        expect(
          result.single.text,
          '⚠️ 設定を読めなかったため、既定値（出勤 30 分前）で確かめましたが、今日の出勤（9:15）の 30 分前はもう過ぎています。アラームは登録されていません',
        );
        expect(result.single.color, Colors.orange);
      });

      test('none で今日の出勤がない → 何も出さない', () {
        expect(messages(WakeAlarmPlan.none, settingsReadFailed: true), isEmpty);
      });

      test('アラーム OFF → 何も出さない', () {
        expect(
          messages(
            WakeAlarmPlan.none,
            manualAt: manual,
            alarmDisabled: true,
            settingsReadFailed: true,
            workStartAt: DateTime(2026, 11, 5, 9, 15),
          ),
          isEmpty,
        );
      });

      test('シフトも読めなかった（手動なし）→ シフトの ⚠️ だけ', () {
        final result = messages(WakeAlarmPlan.none, shiftsReadFailed: true, settingsReadFailed: true);
        expect(result.single.text, '⚠️ シフトを読めなかったため、出勤前アラームを登録できませんでした');
      });
    });

    // N118 2b：今日のシフトのパターンが削除されているとき
    group('パターンが削除されている', () {
      test('main あり → 起床アラームは登録済み', () {
        final result = messages(WakeAlarmPlan.mainOnly, manualAt: manual, patternMissing: true);
        expect(result.single.text, '⚠️ 今日のシフトのパターンが削除されているため、出勤前アラームは登録しません。起床アラームは登録済みです');
        expect(result.single.color, Colors.orange);
      });

      test('main なし', () {
        final result = messages(WakeAlarmPlan.none, patternMissing: true);
        expect(result.single.text, '⚠️ 今日のシフトのパターンが削除されているため、出勤前アラームは登録しません');
      });

      test('main も失敗 → main の ⚠️ だけ', () {
        final result = messages(WakeAlarmPlan.mainOnly, manualAt: manual, mainError: '⚠️ 失敗', patternMissing: true);
        expect(result.single.text, '⚠️ 失敗');
      });

      test('設定も読めなかった → 既定値の ⚠️ が先', () {
        final result = messages(WakeAlarmPlan.mainOnly, manualAt: manual, patternMissing: true, settingsReadFailed: true);
        expect(result.map((m) => m.text), [
          fallback,
          '⚠️ 今日のシフトのパターンが削除されているため、出勤前アラームは登録しません。起床アラームは登録済みです',
        ]);
      });
    });
  });
}
