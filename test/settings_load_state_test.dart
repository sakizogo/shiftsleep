import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/settings_load_state.dart';

// N118 2/4 2c：設定を読み込めなかったときに押せるかどうかの判定と、知らせの文言のテスト

void main() {
  group('canEditSettings', () {
    test('読み込めていて処理中でなければ押せる', () {
      expect(canEditSettings(loaded: true, alarmBusy: false), isTrue);
    });
    test('読み込めていてもアラームの処理中は押せない', () {
      expect(canEditSettings(loaded: true, alarmBusy: true), isFalse);
    });
    test('読み込み中・失敗中は押せない', () {
      expect(canEditSettings(loaded: false, alarmBusy: false), isFalse);
    });
    test('読み込めていなくて処理中も押せない', () {
      expect(canEditSettings(loaded: false, alarmBusy: true), isFalse);
    });
  });

  group('canToggleAlarm', () {
    test('処理中でなければ押せる（読み込みの成否は見ない）', () {
      expect(canToggleAlarm(alarmBusy: false), isTrue);
    });
    test('処理中は押せない', () {
      expect(canToggleAlarm(alarmBusy: true), isFalse);
    });
  });

  group('canReloadSettings', () {
    test('再読み込み中でなければ押せる', () {
      expect(canReloadSettings(reloading: false), isTrue);
    });
    test('再読み込み中は押せない（二度押し防止）', () {
      expect(canReloadSettings(reloading: true), isFalse);
    });
  });

  group('settingsReloadMessage', () {
    test('成功は ✅ で既定の色', () {
      final message = settingsReloadMessage(succeeded: true);
      expect(message.text, startsWith('✅'));
      expect(message.color, isNull);
    });
    test('失敗は ⚠️ でオレンジ', () {
      final message = settingsReloadMessage(succeeded: false);
      expect(message.text, startsWith('⚠️'));
      expect(message.color, Colors.orange);
    });
  });

  test('バナーの文言は ⚠️ で始まり、既定値の表示と ON/OFF が使えることを伝える', () {
    expect(settingsLoadFailedTitle, startsWith('⚠️'));
    expect(settingsLoadFailedBody, contains('既定の値'));
    expect(settingsLoadFailedBody, contains('ON/OFF は使えます'));
  });
}
