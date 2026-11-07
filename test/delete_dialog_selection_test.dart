import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/delete_dialog_selection.dart';

// N140 4/4：削除ダイアログの初期チェック（initialDeleteSelection）と案内（showDeleteSelectionHint）のテスト

void main() {
  group('initialDeleteSelection', () {
    test('シフトだけの 1 項目ならチェックあり', () {
      expect(initialDeleteSelection(['shift']), {'shift'});
    });

    test('有休だけの 1 項目ならチェックあり（対になったシフトは有休の行にまとまる）', () {
      expect(initialDeleteSelection(['vacation_full']), {'vacation_full'});
    });

    test('シフト＋半休の 2 項目なら全部チェックなし', () {
      expect(initialDeleteSelection(['shift', 'vacation_half']), isEmpty);
    });

    test('シフト＋イベントの 2 項目なら全部チェックなし', () {
      expect(initialDeleteSelection(['shift', 'event']), isEmpty);
    });

    test('3 項目でも全部チェックなし', () {
      expect(initialDeleteSelection(['shift', 'vacation_half', 'event']), isEmpty);
    });

    test('0 項目なら空', () {
      expect(initialDeleteSelection(const <String>[]), isEmpty);
    });

    test('返した Set を変えても、渡したもとの項目は変わらない', () {
      final keys = ['shift'];
      final selected = initialDeleteSelection(keys)..add('event');
      expect(selected, {'shift', 'event'});
      expect(keys, ['shift']);
      // 2 項目のときの空の Set も、あとから足せる
      expect((initialDeleteSelection(['shift', 'event'])..add('shift')), {'shift'});
    });
  });

  group('showDeleteSelectionHint', () {
    test('チェックが 0 個なら案内を出す', () {
      expect(showDeleteSelectionHint(<String>{}), isTrue);
    });

    test('1 つ以上チェックしたら案内を出さない', () {
      expect(showDeleteSelectionHint({'shift'}), isFalse);
      expect(showDeleteSelectionHint({'shift', 'event'}), isFalse);
    });

    test('項目が 1 つで最初からチェックありなら案内を出さない', () {
      expect(showDeleteSelectionHint(initialDeleteSelection(['shift'])), isFalse);
    });

    test('項目が 2 つ以上で開いたときは案内を出す', () {
      expect(showDeleteSelectionHint(initialDeleteSelection(['shift', 'event'])), isTrue);
    });

    test('案内の文言', () {
      expect(deleteSelectionHint, 'ℹ️ 削除するものにチェックを入れてください');
    });
  });
}
