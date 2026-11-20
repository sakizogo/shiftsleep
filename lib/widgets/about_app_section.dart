// N210：設定画面の一番下（［設定を保存］の下）の「ℹ️ このアプリについて」の欄（D5 A）
//
// - 見出しと白地・枠・角丸は、ほかの欄（💼 有給管理など）とそろえる
// - 行全体を押せる（ListTile。余白は既定のまま）。右の ↗ は外部のブラウザで開くことを示す
// - 「プライバシー」「ポリシー」の区切りで折り返す（幅 360dp・2.0 倍で「ー」だけが落ちないように）
// - 開いている途中は、もう一度押しても何もしない
// - 開けなかったら、URL つきの ⚠️ をオレンジで 6 秒。［コピー］で URL をクリップボードに入れる（D21 B）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/services/about_app.dart';

class AboutAppSection extends StatefulWidget {
  const AboutAppSection({super.key, this.opener = openInExternalBrowser});

  /// 開く関数（テストで差し替える）
  final UrlOpener opener;

  @override
  State<AboutAppSection> createState() => _AboutAppSectionState();
}

class _AboutAppSectionState extends State<AboutAppSection> {
  bool _isOpening = false;

  Future<void> _openPrivacyPolicy() async {
    if (_isOpening) return;
    final messenger = ScaffoldMessenger.of(context);  // await 前に取得
    _isOpening = true;
    try {
      final opened = await openPrivacyPolicy(open: widget.opener);
      if (opened) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: const Text(privacyPolicyOpenFailedText),
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
      await Clipboard.setData(const ClipboardData(text: privacyPolicyUrl));
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
    final radius = BorderRadius.circular(AppDimensions.borderRadiusMedium);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(aboutAppSectionTitle, style: AppTextStyles.sectionTitleStyle),
        const SizedBox(height: AppDimensions.paddingMedium),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: const BorderSide(color: AppColors.borderDefault),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.textSecondary),
            // 区切りで Wrap に並べ、大きい文字でも「ー」だけが落ちないようにする。読み上げは 1 つにまとめる
            title: Semantics(
              label: privacyPolicyLabel,
              excludeSemantics: true,
              child: Wrap(
                children: [
                  for (final part in privacyPolicyLabelParts)
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
            onTap: _openPrivacyPolicy,
          ),
        ),
      ],
    );
  }
}
