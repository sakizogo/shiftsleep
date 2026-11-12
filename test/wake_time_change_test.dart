// N166：起床時刻の［変更］のあとの判定と SnackBar
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/wake_time_change.dart';

void main() {
  group('wakeTimeChangeMessages・shouldSaveSettingsAfterWakeTimeChange', () {
    test('成功 → 何も出さず、設定の保存へ進む', () {
      expect(wakeTimeChangeMessages(saveFailed: false, dailyFailed: false), isEmpty);
      expect(shouldSaveSettingsAfterWakeTimeChange(saveFailed: false), isTrue);
    });

    test('save の失敗 → オレンジの ⚠️ を 1 つ出し、設定の保存へ進まない', () {
      final list = wakeTimeChangeMessages(saveFailed: true, dailyFailed: false);
      expect(list.map((message) => message.text), [wakeTimeSaveFailedText]);
      expect(list.single.color, Colors.orange);
      expect(list.single.seconds, 6);
      expect(list.single.text, startsWith('⚠️'));
      expect(shouldSaveSettingsAfterWakeTimeChange(saveFailed: true), isFalse);
    });

    test('setDaily だけの失敗 → 「毎日」の ⚠️ を 1 つ出し、設定の保存へは進む', () {
      final list = wakeTimeChangeMessages(saveFailed: false, dailyFailed: true);
      expect(list.map((message) => message.text), [wakeTimeDailySaveFailedText]);
      expect(list.single.color, Colors.orange);
      expect(list.single.seconds, 6);
      expect(list.single.text, startsWith('⚠️'));
      expect(shouldSaveSettingsAfterWakeTimeChange(saveFailed: false), isTrue);
    });

    test('両方の失敗 → save の ⚠️ だけを出す', () {
      final list = wakeTimeChangeMessages(saveFailed: true, dailyFailed: true);
      expect(list.map((message) => message.text), [wakeTimeSaveFailedText]);
      expect(shouldSaveSettingsAfterWakeTimeChange(saveFailed: true), isFalse);
    });
  });
}
