import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/range_apply_message.dart';

// N93：rangeApplyFailureMessage（期間指定が途中で失敗したときの文言）のテスト

void main() {
  final error = Exception('disk I/O error');

  test('1. 1 日目で失敗（lastSucceeded が null）→ ❌ の文言', () {
    final message = rangeApplyFailureMessage(
      DateTime(2026, 11, 1),
      null,
      DateTime(2026, 11, 1),
      error,
    );
    expect(message, '❌ 期間指定に失敗しました: Exception: disk I/O error');
  });

  test('2. 途中で失敗 → 開始日〜最後に成功した日と、失敗した日', () {
    final message = rangeApplyFailureMessage(
      DateTime(2026, 11, 1),
      DateTime(2026, 11, 5),
      DateTime(2026, 11, 6),
      error,
    );
    expect(
      message,
      '⚠️ 11/1〜11/5 は登録しました。11/6 で失敗したため、以降は登録していません: Exception: disk I/O error',
    );
  });

  test('3. 2 日目で失敗（開始日＝最後に成功した日）→「11/1〜11/1」ではなく「11/1 は登録しました」', () {
    final message = rangeApplyFailureMessage(
      DateTime(2026, 11, 1),
      DateTime(2026, 11, 1),
      DateTime(2026, 11, 2),
      error,
    );
    expect(
      message,
      '⚠️ 11/1 は登録しました。11/2 で失敗したため、以降は登録していません: Exception: disk I/O error',
    );
  });

  test('4. 時刻つきの開始日でも、日付が同じなら 1 日として扱う', () {
    final message = rangeApplyFailureMessage(
      DateTime(2026, 11, 1, 9, 30),
      DateTime(2026, 11, 1),
      DateTime(2026, 11, 2),
      error,
    );
    expect(message, startsWith('⚠️ 11/1 は登録しました。'));
  });

  test('5. 月・年をまたぐ期間は M/d のまま（年は出さない）', () {
    final message = rangeApplyFailureMessage(
      DateTime(2026, 12, 30),
      DateTime(2026, 12, 31),
      DateTime(2027, 1, 1),
      error,
    );
    expect(message, startsWith('⚠️ 12/30〜12/31 は登録しました。1/1 で失敗したため'));
  });
}
