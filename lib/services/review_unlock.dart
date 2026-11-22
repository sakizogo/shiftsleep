// N213：審査用コードでプレミアム版を解放する
// - コードはソースに書かない。ビルドのときに --dart-define-from-file=review_code.json で渡す（D45 B）
// - 前後の空白を除き、大文字・小文字を区別せずに比べる。全角は変換しない（D51 B）
// - コードが空（付け忘れ）なら、どんな入力でも解放しない
// - 解放したことは SharedPreferences に保存する（D44 A）。期限なし。再起動しても続く
// - 読めない・書けないときは debugPrint だけ（読めなければ解放していない扱い）
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ビルドのときに渡された審査用コード（渡していなければ空）
const String reviewCodeFromEnvironment = String.fromEnvironment('SHIFTSLEEP_REVIEW_CODE');

/// 解放したかのキー
const String reviewUnlockedKey = 'shiftsleep_review_unlocked';

/// 入力が審査用コードと同じか（expected が空なら、いつも false）
bool isValidReviewCode(String input, {required String expected}) {
  final code = expected.trim();
  if (code.isEmpty) return false;
  return input.trim().toLowerCase() == code.toLowerCase();
}

/// 審査用コードを入れた結果
enum ReviewUnlockOutcome {
  /// 解放して、保存もできた
  unlocked,

  /// コードが違う（何も変えない）
  wrongCode,

  /// 保存に失敗したので、この起動中だけ解放した（D50 A）
  unlockedThisSessionOnly,
}

class ReviewUnlockStore {
  const ReviewUnlockStore();

  /// 解放しているか（保存がない・読めないときは false）
  Future<bool> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(reviewUnlockedKey) ?? false;
    } catch (e) {
      debugPrint('❌ [ReviewUnlock] 審査用の解放を読めませんでした: $e');
      return false;
    }
  }

  /// 解放したことを保存する（保存できたか）
  Future<bool> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setBool(reviewUnlockedKey, true);
      debugPrint('[ReviewUnlock] 審査用の解放を保存: $saved');
      return saved;
    } catch (e) {
      debugPrint('❌ [ReviewUnlock] 審査用の解放を保存できませんでした: $e');
      return false;
    }
  }

  /// 解放の保存を消す（消せたか）
  Future<bool> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final removed = await prefs.remove(reviewUnlockedKey);
      debugPrint('[ReviewUnlock] 審査用の解放を解除: $removed');
      return removed;
    } catch (e) {
      debugPrint('❌ [ReviewUnlock] 審査用の解放の保存を消せませんでした: $e');
      return false;
    }
  }
}
