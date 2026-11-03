import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/alarm_permission.dart';

// N128：shouldShowAlarmPermissionIntro・shouldShowAlarmPermissionBanner・文言のテスト

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
  });
}
