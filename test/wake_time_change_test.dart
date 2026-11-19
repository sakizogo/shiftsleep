// N166：起床時刻の［変更］のあとの判定と SnackBar
// N195：起きているときの「起床アラームは登録されません」を出すかの判定
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

  // N195：保存で起床時刻が変わったか
  group('wakeTimeChangedOnSave', () {
    test('同じ時刻 → 変わっていない', () {
      expect(wakeTimeChangedOnSave(before: '07:00', after: '07:00', chosen: false), isFalse);
    });

    test('違う時刻 → 変わった', () {
      expect(wakeTimeChangedOnSave(before: '07:00', after: '05:30', chosen: false), isTrue);
    });

    test('"7:00" と "07:00" は同じとみなす', () {
      expect(wakeTimeChangedOnSave(before: '7:00', after: '07:00', chosen: false), isFalse);
    });

    test('読めない値 → 変わったとみなす', () {
      expect(wakeTimeChangedOnSave(before: '', after: '07:00', chosen: false), isTrue);
      expect(wakeTimeChangedOnSave(before: '25:00', after: '07:00', chosen: false), isTrue);
    });

    test('D11：［変更］で選んで確定したら、同じ時刻でも変わったとみなす', () {
      expect(wakeTimeChangedOnSave(before: '07:00', after: '07:00', chosen: true), isTrue);
    });
  });

  // N195：時刻の変化あり/なし × アラーム ON/OFF × 寝ている/起きている の 8 通り
  group('shouldShowAwakeNoAlarmNotice', () {
    for (final changed in [true, false]) {
      for (final alarmEnabled in [true, false]) {
        for (final sleepingNow in [true, false]) {
          final expected = changed && alarmEnabled && !sleepingNow;
          test(
            '変化${changed ? 'あり' : 'なし'}・アラーム${alarmEnabled ? 'ON' : 'OFF'}・'
            '${sleepingNow ? '寝ている' : '起きている'} → ${expected ? '出す' : '出さない'}',
            () {
              expect(
                shouldShowAwakeNoAlarmNotice(
                  wakeTimeChanged: changed,
                  alarmEnabled: alarmEnabled,
                  sleepingNow: sleepingNow,
                ),
                expected,
              );
            },
          );
        }
      }
    }
  });

  test('N195：起きているときの知らせの文言（D12）', () {
    expect(awakeNoAlarmText, '⚠️ 起きているあいだは、起床アラームは登録されません。『今から寝る』を押すと登録されます');
  });
}
