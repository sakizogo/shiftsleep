// N213：審査用コードの比べ方（isValidReviewCode）と、解放の保存（ReviewUnlockStore）
// コードは dart-define に頼らず、expected で渡す（本物のコードはテストにも書かない）
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/services/review_unlock.dart';

const _code = 'TEST-CODE-1A';

void main() {
  group('isValidReviewCode', () {
    test('同じコードなら true', () {
      expect(isValidReviewCode(_code, expected: _code), isTrue);
    });

    test('前後の空白（改行・タブを含む）は除いて比べる', () {
      expect(isValidReviewCode('  $_code \n', expected: _code), isTrue);
      expect(isValidReviewCode('\t$_code', expected: _code), isTrue);
    });

    test('D51 B：大文字・小文字は区別しない', () {
      expect(isValidReviewCode('test-code-1a', expected: _code), isTrue);
      expect(isValidReviewCode('Test-Code-1A', expected: _code), isTrue);
    });

    test('違うコード・途中の空白・全角は false（全角は変換しない）', () {
      expect(isValidReviewCode('TEST-CODE-1B', expected: _code), isFalse);
      expect(isValidReviewCode('TEST-CODE-1', expected: _code), isFalse);
      expect(isValidReviewCode('TEST- CODE-1A', expected: _code), isFalse);
      expect(isValidReviewCode('ＴＥＳＴ－ＣＯＤＥ－１Ａ', expected: _code), isFalse);
    });

    test('空の入力・空白だけの入力は false', () {
      expect(isValidReviewCode('', expected: _code), isFalse);
      expect(isValidReviewCode('   ', expected: _code), isFalse);
    });

    test('D45 B：expected が空（付け忘れ）なら、どんな入力でも false', () {
      for (final input in ['', '   ', _code, 'anything']) {
        expect(isValidReviewCode(input, expected: ''), isFalse, reason: input);
        expect(isValidReviewCode(input, expected: '   '), isFalse, reason: input);
      }
    });
  });

  group('ReviewUnlockStore', () {
    const store = ReviewUnlockStore();

    test('保存がなければ false。保存すると true、解除すると false に戻る', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await store.load(), isFalse);

      expect(await store.save(), isTrue);
      expect(await store.load(), isTrue);
      expect((await SharedPreferences.getInstance()).getBool(reviewUnlockedKey), isTrue);

      expect(await store.clear(), isTrue);
      expect(await store.load(), isFalse);
      expect((await SharedPreferences.getInstance()).containsKey(reviewUnlockedKey), isFalse);
    });

    test('読めない（型が違う）ときは false', () async {
      SharedPreferences.setMockInitialValues({reviewUnlockedKey: 'abc'});

      expect(await store.load(), isFalse);
    });
  });
}
