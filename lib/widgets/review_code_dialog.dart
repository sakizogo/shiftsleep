// N213：審査用コードのダイアログ（購入画面の AppBar の見出しを 2 秒長押しすると開く。リリース版でも動く）
//
// - D46 A：コードが違うときは閉じず、入力欄の下に「❌ コードが違います」（エラーの色＋❌＋文字）
// - D47 A：解放中（SleepProvider.isReviewUnlocked）なら［解除する］を出す（リリース版でも使える）
// - 結果は ReviewCodeDialogResult で返し、SnackBar と購入画面を閉じるかは呼んだ側で決める（D49 A・D50 A）
// - E39：間違えた回数の制限は入れない
// - E41：await の前に NavigatorState を取っておく。ログは debugPrint だけ
// - 処理中は PopScope で、外のタップと戻るボタンで閉じない（閉じたあとの pop が下の画面を閉じないように）
// - 色だけで区別しない（知らせの文の頭に記号）
import 'package:flutter/material.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/services/review_unlock.dart';

/// 見出しを長押しする長さ
const Duration reviewCodeLongPressDuration = Duration(seconds: 2);

/// ダイアログの文字
const reviewCodeDialogTitle = '🔑 審査用コード';
const reviewCodeFieldLabel = 'コード';
const reviewCodeWrongText = '❌ コードが違います';
const reviewCodeCancelLabel = 'キャンセル';
const reviewCodeUnlockLabel = '解放する';
const reviewCodeClearLabel = '解除する';

/// 結果の知らせ
const reviewUnlockedText = '✨ 審査用コードでプレミアム版を解放しました';
const reviewUnlockNotSavedText = '⚠️ 解放を保存できませんでした。再起動すると元に戻ります';
const reviewClearedText = '審査用コードの解放を解除しました';
const reviewClearNotSavedText = '⚠️ 解除を保存できませんでした。再起動すると解放された状態に戻ります';

/// ダイアログの結果（キャンセルは null）
enum ReviewCodeDialogResult {
  /// 解放して、保存もできた
  unlocked,

  /// 保存に失敗したので、この起動中だけ解放した
  unlockedThisSessionOnly,

  /// 解除して、保存も消せた
  cleared,

  /// 解除したが、保存を消せなかった（再起動すると解放に戻る）
  clearNotSaved,
}

/// 結果の知らせ（color が null なら SnackBar のいつもの色）
({String text, Color? color}) reviewCodeResultMessage(
        ReviewCodeDialogResult result) =>
    switch (result) {
      ReviewCodeDialogResult.unlocked => (
          text: reviewUnlockedText,
          color: Colors.green
        ),
      ReviewCodeDialogResult.unlockedThisSessionOnly => (
          text: reviewUnlockNotSavedText,
          color: Colors.orange
        ),
      ReviewCodeDialogResult.cleared => (text: reviewClearedText, color: null),
      ReviewCodeDialogResult.clearNotSaved => (
          text: reviewClearNotSavedText,
          color: Colors.orange
        ),
    };

/// 解放したか（購入画面を閉じるか）
bool reviewCodeResultUnlocks(ReviewCodeDialogResult result) =>
    result == ReviewCodeDialogResult.unlocked ||
    result == ReviewCodeDialogResult.unlockedThisSessionOnly;

/// ダイアログを開く（provider はダイアログの外から渡す）
Future<ReviewCodeDialogResult?> showReviewCodeDialog(BuildContext context,
    {required SleepProvider provider}) {
  return showDialog<ReviewCodeDialogResult>(
    context: context,
    builder: (_) => ReviewCodeDialog(provider: provider),
  );
}

class ReviewCodeDialog extends StatefulWidget {
  const ReviewCodeDialog({super.key, required this.provider});

  final SleepProvider provider;

  @override
  State<ReviewCodeDialog> createState() => _ReviewCodeDialogState();
}

class _ReviewCodeDialogState extends State<ReviewCodeDialog> {
  final _controller = TextEditingController();
  bool _wrong = false;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final navigator = Navigator.of(context); // E41：await の前に取る
    setState(() {
      _busy = true;
      _wrong = false;
    });
    final outcome =
        await widget.provider.unlockWithReviewCode(_controller.text);
    debugPrint('[ReviewCode] 🔑 審査用コードの結果: ${outcome.name}');
    switch (outcome) {
      case ReviewUnlockOutcome.wrongCode:
        if (mounted) {
          setState(() {
            _busy = false;
            _wrong = true;
          });
        }
      case ReviewUnlockOutcome.unlocked:
        navigator.pop(ReviewCodeDialogResult.unlocked);
      case ReviewUnlockOutcome.unlockedThisSessionOnly:
        navigator.pop(ReviewCodeDialogResult.unlockedThisSessionOnly);
    }
  }

  Future<void> _clear() async {
    final navigator = Navigator.of(context); // E41：await の前に取る
    setState(() => _busy = true);
    final cleared = await widget.provider.clearReviewUnlock();
    debugPrint('[ReviewCode] 🔑 審査用の解放を解除（保存を消せたか: $cleared）');
    navigator.pop(cleared
        ? ReviewCodeDialogResult.cleared
        : ReviewCodeDialogResult.clearNotSaved);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text(reviewCodeDialogTitle),
        content: TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _unlock(),
          decoration: InputDecoration(
            labelText: reviewCodeFieldLabel,
            errorText: _wrong ? reviewCodeWrongText : null,
            errorMaxLines: 2,
          ),
        ),
        actions: [
          if (widget.provider.isReviewUnlocked)
            TextButton(
                onPressed: _busy ? null : _clear,
                child: const Text(reviewCodeClearLabel)),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text(reviewCodeCancelLabel),
          ),
          TextButton(
              onPressed: _busy ? null : _unlock,
              child: const Text(reviewCodeUnlockLabel)),
        ],
      ),
    );
  }
}
