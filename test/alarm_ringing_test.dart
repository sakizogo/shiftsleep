import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/alarm_ringing.dart';

// N129 2/2：shouldShowStopAlarmButton・文言のテスト

void main() {
  group('shouldShowStopAlarmButton', () {
    test('1. 鳴っている＋睡眠中でない → 出す', () {
      expect(shouldShowStopAlarmButton(isRinging: true, isSleeping: false), isTrue);
    });

    test('2. 鳴っている＋睡眠中 → 出さない（「起きる」で止める）', () {
      expect(shouldShowStopAlarmButton(isRinging: true, isSleeping: true), isFalse);
    });

    test('3. 鳴っていない＋睡眠中でない → 出さない', () {
      expect(shouldShowStopAlarmButton(isRinging: false, isSleeping: false), isFalse);
    });

    test('4. 鳴っていない＋睡眠中 → 出さない', () {
      expect(shouldShowStopAlarmButton(isRinging: false, isSleeping: true), isFalse);
    });
  });

  group('文言', () {
    test('1. バナーは 🔔 で始まり、文字だけで意味が分かる', () {
      expect(stopAlarmBannerText, '🔔 アラームが鳴っています');
      expect(stopAlarmBannerText.startsWith('🔔'), isTrue);
    });

    test('2. ボタンは「止める」', () {
      expect(stopAlarmButtonLabel, '止める');
    });

    test('3. 失敗の文言は ⚠️ で始まり、もう一度試すことが分かる', () {
      expect(stopAlarmFailedText, '⚠️ アラームを止められませんでした。もう一度お試しください');
      expect(stopAlarmFailedText.startsWith('⚠️'), isTrue);
    });
  });
}
