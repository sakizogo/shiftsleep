// N138＋N139 4a：外部のページを開く行（E27 A：AboutAppSection から切り出し、購入画面と共通にする）
//
// - 行全体を押せる（ListTile。余白は既定のまま）。右の ↗ は外部のブラウザ・アプリで開くことを示す
// - 文言は区切りで Wrap に並べ、大きい文字でも最後の 1〜2 文字だけが落ちないようにする。読み上げは 1 つにまとめる
// - 開いている途中は、もう一度押しても何もしない
// - 開けなかったら、URL つきの ⚠️ をオレンジで 6 秒。［コピー］で URL をクリップボードに入れる（N210 D21 B と同じ）
// - 枠（白地・枠線・角丸）は置く側が付ける
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/services/about_app.dart';

/// 外部のページを開く行
class ExternalLinkTile extends StatefulWidget {
  const ExternalLinkTile({
    super.key,
    required this.url,
    required this.label,
    required this.labelParts,
    required this.leadingIcon,
    required this.open,
    required this.openFailedText,
  });

  /// 開く URL（［コピー］でクリップボードに入れる）
  final String url;

  /// 行の文言（読み上げにはこの 1 つを使う）
  final String label;

  /// 画面では、この区切りで折り返す。つなげると label と同じ
  final List<String> labelParts;

  final IconData leadingIcon;

  /// 開く処理。開けたら true（例外は外に出さない）
  final Future<bool> Function() open;

  /// 開けなかったときの知らせ
  final String openFailedText;

  @override
  State<ExternalLinkTile> createState() => _ExternalLinkTileState();
}

class _ExternalLinkTileState extends State<ExternalLinkTile> {
  bool _isOpening = false;

  Future<void> _openLink() async {
    if (_isOpening) return;
    final messenger = ScaffoldMessenger.of(context);  // await 前に取得
    _isOpening = true;
    try {
      final opened = await widget.open();
      if (opened) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(widget.openFailedText),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: copyUrlActionLabel,
            textColor: Colors.white,
            onPressed: () => _copyUrl(messenger),
          ),
        ),
      );
    } finally {
      _isOpening = false;
    }
  }

  Future<void> _copyUrl(ScaffoldMessengerState messenger) async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.url));
    } catch (e) {
      debugPrint('⚠️ N210: URL をコピーできませんでした: $e');
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text(urlCopiedText), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(widget.leadingIcon, color: AppColors.textSecondary),
      title: Semantics(
        label: widget.label,
        excludeSemantics: true,
        child: Wrap(
          children: [
            for (final part in widget.labelParts)
              Text(
                part,
                style: AppTextStyles.bodyTextStyle.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
          ],
        ),
      ),
      trailing: const Icon(
        Icons.open_in_new,
        color: AppColors.textSecondary,
        semanticLabel: externalLinkSemanticLabel,
      ),
      onTap: _openLink,
    );
  }
}

/// プライバシーポリシーの行（設定画面の「ℹ️ このアプリについて」と購入画面）
class PrivacyPolicyTile extends StatelessWidget {
  const PrivacyPolicyTile({super.key, this.opener = openInExternalBrowser});

  /// 開く関数（テストで差し替える）
  final UrlOpener opener;

  @override
  Widget build(BuildContext context) {
    return ExternalLinkTile(
      url: privacyPolicyUrl,
      label: privacyPolicyLabel,
      labelParts: privacyPolicyLabelParts,
      leadingIcon: Icons.privacy_tip_outlined,
      open: () => openPrivacyPolicy(open: opener),
      openFailedText: privacyPolicyOpenFailedText,
    );
  }
}
