import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/tab_snackbar.dart';

// N190：タブを切り替えるときに SnackBar を消すかの判定のテスト

void main() {
  group('shouldClearSnackBarsOnTabChange', () {
    test('設定タブからほかのタブへ移るときは消す', () {
      expect(shouldClearSnackBarsOnTabChange(from: 2, to: 0), isTrue);
      expect(shouldClearSnackBarsOnTabChange(from: 2, to: 1), isTrue);
      expect(shouldClearSnackBarsOnTabChange(from: 2, to: 3), isTrue);
    });
    test('設定タブを押し直したときは消さない', () {
      expect(shouldClearSnackBarsOnTabChange(from: 2, to: 2), isFalse);
    });
    test('設定タブから離れないときは消さない', () {
      expect(shouldClearSnackBarsOnTabChange(from: 0, to: 1), isFalse);
      expect(shouldClearSnackBarsOnTabChange(from: 1, to: 2), isFalse);
      expect(shouldClearSnackBarsOnTabChange(from: 3, to: 0), isFalse);
    });
  });
}
