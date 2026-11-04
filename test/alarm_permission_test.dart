import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/alarm_permission.dart';
import 'package:shiftsleep/services/alarm_reschedule.dart';
import 'package:shiftsleep/services/alarm_service.dart';

// N128：shouldShowAlarmPermissionIntro・shouldShowAlarmPermissionBanner・文言のテスト
// N128 2/2：shouldReschedulePreAlarmsOnGrant・alarmPermissionGrantedMessages のテスト
// N129 1/2：alarmPermissionBannerKind・通知のバナーの文言のテスト

void main() {
  group('shouldShowAlarmPermissionIntro', () {
    test('1. まだ出していない＋アラームとリマインダーが許可なし → 出す', () {
      expect(
        shouldShowAlarmPermissionIntro(alreadyShown: false, exactAlarmGranted: false, notificationGranted: true),
        isTrue,
      );
    });

    test('2. まだ出していない＋通知が許可なし → 出す', () {
      expect(
        shouldShowAlarmPermissionIntro(alreadyShown: false, exactAlarmGranted: true, notificationGranted: false),
        isTrue,
      );
    });

    test('3. まだ出していない＋どちらも許可なし → 出す', () {
      expect(
        shouldShowAlarmPermissionIntro(alreadyShown: false, exactAlarmGranted: false, notificationGranted: false),
        isTrue,
      );
    });

    test('4. まだ出していない＋どちらも許可あり → 出さない', () {
      expect(
        shouldShowAlarmPermissionIntro(alreadyShown: false, exactAlarmGranted: true, notificationGranted: true),
        isFalse,
      );
    });

    test('5. 出したあと → 許可がなくても出さない', () {
      expect(
        shouldShowAlarmPermissionIntro(alreadyShown: true, exactAlarmGranted: false, notificationGranted: false),
        isFalse,
      );
    });

    test('6. 出したあと＋どちらも許可あり → 出さない', () {
      expect(
        shouldShowAlarmPermissionIntro(alreadyShown: true, exactAlarmGranted: true, notificationGranted: true),
        isFalse,
      );
    });
  });

  group('shouldShowAlarmPermissionBanner', () {
    test('1. ON＋許可なし → 出す', () {
      expect(shouldShowAlarmPermissionBanner(alarmEnabled: true, exactAlarmGranted: false), isTrue);
    });

    test('2. ON＋許可あり → 出さない', () {
      expect(shouldShowAlarmPermissionBanner(alarmEnabled: true, exactAlarmGranted: true), isFalse);
    });

    test('3. OFF＋許可なし → 出さない', () {
      expect(shouldShowAlarmPermissionBanner(alarmEnabled: false, exactAlarmGranted: false), isFalse);
    });

    test('4. OFF＋許可あり → 出さない', () {
      expect(shouldShowAlarmPermissionBanner(alarmEnabled: false, exactAlarmGranted: true), isFalse);
    });
  });

  group('alarmPermissionBannerKind', () {
    AlarmPermissionBannerKind kind(bool alarmEnabled, bool exactAlarmGranted, bool notificationGranted) {
      return alarmPermissionBannerKind(
        alarmEnabled: alarmEnabled,
        exactAlarmGranted: exactAlarmGranted,
        notificationGranted: notificationGranted,
      );
    }

    test('1. ON＋両方なし → アラーム（通知より優先）', () {
      expect(kind(true, false, false), AlarmPermissionBannerKind.exactAlarm);
    });

    test('2. ON＋アラームのみなし → アラーム', () {
      expect(kind(true, false, true), AlarmPermissionBannerKind.exactAlarm);
    });

    test('3. ON＋通知のみなし → 通知', () {
      expect(kind(true, true, false), AlarmPermissionBannerKind.notification);
    });

    test('4. ON＋両方あり → なし', () {
      expect(kind(true, true, true), AlarmPermissionBannerKind.none);
    });

    test('5. OFF → 許可がどうでも なし', () {
      expect(kind(false, false, false), AlarmPermissionBannerKind.none);
      expect(kind(false, false, true), AlarmPermissionBannerKind.none);
      expect(kind(false, true, false), AlarmPermissionBannerKind.none);
      expect(kind(false, true, true), AlarmPermissionBannerKind.none);
    });
  });

  group('文言', () {
    test('1. ダイアログのタイトル・本文・ボタン', () {
      expect(alarmPermissionIntroTitle, '⏰ アラームを使うための許可');
      expect(
        alarmPermissionIntroBody,
        '出勤前アラーム・起床アラームを正確な時刻に鳴らすため、次の画面で「アラームとリマインダー」をオンにしてください。そのあと、通知の許可もお願いします。',
      );
      expect(alarmPermissionIntroSettingsLabel, '設定する');
      expect(alarmPermissionIntroLaterLabel, 'あとで');
    });

    test('2. バナーは ⚠️ で始まり、文字だけで意味が分かる', () {
      expect(alarmPermissionBannerText, '⚠️ 「アラームとリマインダー」が許可されていないため、アラームが鳴りません');
      expect(alarmPermissionBannerText.startsWith('⚠️'), isTrue);
      expect(alarmPermissionBannerButtonLabel, '設定を開く');
    });

    test('3. 通知のバナーも ⚠️ で始まり、文字だけで意味が分かる', () {
      expect(notificationPermissionBannerText, '⚠️ 通知が許可されていないため、鳴ったアラームを通知から止められません');
      expect(notificationPermissionBannerText.startsWith('⚠️'), isTrue);
    });
  });

  group('shouldReschedulePreAlarmsOnGrant', () {
    test('1. 記録なし＋許可あり＋ON → しない（記録するだけ）', () {
      expect(shouldReschedulePreAlarmsOnGrant(previousGranted: null, exactAlarmGranted: true, alarmEnabled: true), isFalse);
    });

    test('2. 許可なし → 許可あり＋ON → する', () {
      expect(shouldReschedulePreAlarmsOnGrant(previousGranted: false, exactAlarmGranted: true, alarmEnabled: true), isTrue);
    });

    test('3. 許可なし → 許可あり＋OFF → しない', () {
      expect(shouldReschedulePreAlarmsOnGrant(previousGranted: false, exactAlarmGranted: true, alarmEnabled: false), isFalse);
    });

    test('4. 許可あり → 許可あり＋ON → しない', () {
      expect(shouldReschedulePreAlarmsOnGrant(previousGranted: true, exactAlarmGranted: true, alarmEnabled: true), isFalse);
    });

    test('5. 許可あり → 許可なし＋ON → しない', () {
      expect(shouldReschedulePreAlarmsOnGrant(previousGranted: true, exactAlarmGranted: false, alarmEnabled: true), isFalse);
    });

    test('6. 許可なし → 許可なし＋ON → しない', () {
      expect(shouldReschedulePreAlarmsOnGrant(previousGranted: false, exactAlarmGranted: false, alarmEnabled: true), isFalse);
    });

    test('7. 記録なし＋許可なし＋ON → しない', () {
      expect(shouldReschedulePreAlarmsOnGrant(previousGranted: null, exactAlarmGranted: false, alarmEnabled: true), isFalse);
    });
  });

  group('alarmPermissionGrantedMessages', () {
    const granted = '✅ アラームが使えるようになりました';
    final denied = AlarmService.alarmErrorMessage('EXACT_ALARM_DENIED')!;

    test('1. n 件・エラーなし → 括弧つきの ✅（緑）だけ', () {
      final messages = alarmPermissionGrantedMessages(count: 3, errorMessage: null, readFailed: false, alarmDisabled: false);
      expect(messages.map((m) => m.text), ['$granted（出勤前アラーム 3件を登録しました）']);
      expect(messages.map((m) => m.color), [Colors.green]);
    });

    test('2. 0 件 → 括弧なしの ✅ だけ', () {
      final messages = alarmPermissionGrantedMessages(count: 0, errorMessage: null, readFailed: false, alarmDisabled: false);
      expect(messages.map((m) => m.text), [granted]);
      expect(messages.map((m) => m.color), [Colors.green]);
    });

    test('3. 分が 0 → 括弧なしの ✅ だけ', () {
      final messages = alarmPermissionGrantedMessages(count: 0, errorMessage: null, readFailed: false, alarmDisabled: true);
      expect(messages.map((m) => m.text), [granted]);
    });

    test('4. 読めなかった → 括弧なしの ✅ のあとにオレンジ（エラーより優先）', () {
      final messages = alarmPermissionGrantedMessages(count: 0, errorMessage: denied, readFailed: true, alarmDisabled: false);
      expect(messages.map((m) => m.text), [granted, '⚠️ 出勤前アラームを登録できませんでした。シフトを確定し直してください']);
      expect(messages.map((m) => m.color), [Colors.green, Colors.orange]);
    });

    test('5. 権限エラー → 括弧なしの ✅ のあとに alarmErrorMessage のオレンジ（件数は出さない）', () {
      final messages = alarmPermissionGrantedMessages(count: 2, errorMessage: denied, readFailed: false, alarmDisabled: false);
      expect(messages.map((m) => m.text), [granted, denied]);
      expect(messages.map((m) => m.color), [Colors.green, Colors.orange]);
    });

    test('6. 睡眠中で手動起床が有効 → 最後にオレンジで「起床アラームは戻りません」（N123 と同じ文言）', () {
      final messages = alarmPermissionGrantedMessages(
        count: 1,
        errorMessage: null,
        readFailed: false,
        alarmDisabled: false,
        manualWakeNotRestored: true,
      );
      expect(messages.map((m) => m.text), [
        '$granted（出勤前アラーム 1件を登録しました）',
        '⚠️ 起床アラームは戻りません。『起きる』→『今から寝る』をやり直してください',
      ]);
      expect(messages.last.text, manualWakeNotRestoredText);
      expect(messages.map((m) => m.color), [Colors.green, Colors.orange]);
    });

    test('7. 権限エラー＋手動起床 → ✅・権限エラー・起床アラームの順', () {
      final messages = alarmPermissionGrantedMessages(
        count: 0,
        errorMessage: denied,
        readFailed: false,
        alarmDisabled: false,
        manualWakeNotRestored: true,
      );
      expect(messages.map((m) => m.text), [granted, denied, manualWakeNotRestoredText]);
    });
  });
}
