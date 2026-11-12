// N147・N166：「この設定を毎日使用する」のあとに出す SnackBar
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/daily_wake_toggle.dart';
import 'package:shiftsleep/services/wake_alarm_choice.dart';

void main() {
  final now = DateTime(2026, 11, 12, 23, 0);
  final mainAt = DateTime(2026, 11, 13, 6, 0);
  final preAt = DateTime(2026, 11, 13, 6, 30);
  const onText = '✅ 毎晩 06:00 に起こします（出勤前アラームの方が早い日はそちらを優先）';
  const offText = '⬜ 「変更」で選んだ夜だけこの時刻を使います';

  List<({String text, Color? color, int seconds})> messages({
    bool enabled = true,
    bool saveFailed = false,
    bool reloadFailed = false,
    WakeAlarmRegistrationResult? alarmResult,
    bool alarmError = false,
  }) =>
      dailyWakeToggleMessages(
        enabled: enabled,
        timeText: '06:00',
        saveFailed: saveFailed,
        reloadFailed: reloadFailed,
        alarmResult: alarmResult,
        alarmError: alarmError,
      );

  List<String> texts(List<({String text, Color? color, int seconds})> list) =>
      list.map((message) => message.text).toList();

  group('起床中（登録しない）', () {
    test('ON → ✅ だけ', () {
      final list = messages();
      expect(texts(list), [onText]);
      expect(list.single.color, isNull);
      expect(list.single.seconds, 2);
    });

    test('OFF → ⬜ だけ', () {
      expect(texts(messages(enabled: false)), [offText]);
    });

    test('読み直しに失敗 → ⚠️ だけ（✅ は出さない）', () {
      final list = messages(reloadFailed: true);
      expect(texts(list), [dailyWakeReloadFailedText]);
      expect(list.single.color, Colors.orange);
      expect(list.single.seconds, 6);
    });
  });

  group('N166：保存に失敗', () {
    for (final enabled in [true, false]) {
      test('${enabled ? 'ON' : 'OFF'} → ⚠️ だけ（✅・⬜ は出さない）', () {
        final list = messages(enabled: enabled, saveFailed: true, reloadFailed: true);
        expect(texts(list), [dailyWakeSaveFailedText]);
        expect(list.single.color, Colors.orange);
      });
    }
  });

  group('N147：睡眠中に ON（登録する）', () {
    test('2 本を登録できた → ✅ のあとに ⏰', () {
      final list = messages(
        alarmResult: WakeAlarmRegistrationResult(
          now: now,
          plan: WakeAlarmPlan.mainAndPre,
          manualWakeAt: mainAt,
          preAlarmAt: preAt,
          minutesBefore: 30,
        ),
      );
      expect(texts(list), [onText, '⏰ 起床アラーム 6:00 と出勤前アラーム 6:30 に鳴ります']);
      expect(list.last.color, isNull);
      expect(list.last.seconds, 6);
    });

    test('main だけ（⏰ の案内なし）→ ✅ だけ', () {
      final list = messages(
        alarmResult: WakeAlarmRegistrationResult(now: now, plan: WakeAlarmPlan.mainOnly, manualWakeAt: mainAt),
      );
      expect(texts(list), [onText]);
    });

    test('main の登録に失敗 → ⚠️ だけ（✅ は出さない）', () {
      final list = messages(
        alarmResult: WakeAlarmRegistrationResult(
          now: now,
          plan: WakeAlarmPlan.mainOnly,
          manualWakeAt: mainAt,
          mainError: '⚠️ main 失敗',
        ),
      );
      expect(texts(list), ['⚠️ main 失敗']);
      expect(list.single.color, Colors.orange);
      expect(list.single.seconds, 6);
    });

    test('登録が例外で止まった → ⚠️ だけ', () {
      final list = messages(alarmError: true);
      expect(texts(list), [dailyWakeAlarmFailedText]);
      expect(list.single.color, Colors.orange);
    });

    test('読み直しにも失敗して登録の ⚠️ がある → ⚠️ を 2 つ（✅ は出さない）', () {
      final list = messages(
        reloadFailed: true,
        alarmResult: WakeAlarmRegistrationResult(
          now: now,
          plan: WakeAlarmPlan.mainOnly,
          manualWakeAt: mainAt,
          mainError: '⚠️ main 失敗',
        ),
      );
      expect(texts(list), [dailyWakeReloadFailedText, '⚠️ main 失敗']);
      expect(list.every((message) => message.color == Colors.orange), isTrue);
    });

    test('読み直しに失敗して登録は成功 → 読み直しの ⚠️ のあとに ⏰', () {
      final list = messages(
        reloadFailed: true,
        alarmResult: WakeAlarmRegistrationResult(
          now: now,
          plan: WakeAlarmPlan.mainAndPre,
          manualWakeAt: mainAt,
          preAlarmAt: preAt,
          minutesBefore: 30,
        ),
      );
      expect(texts(list), [dailyWakeReloadFailedText, '⏰ 起床アラーム 6:00 と出勤前アラーム 6:30 に鳴ります']);
    });
  });
}
