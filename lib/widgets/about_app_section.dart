// N210：設定画面の一番下（［設定を保存］の下）の「ℹ️ このアプリについて」の欄（D5 A）
//
// - 見出しと白地・枠・角丸は、ほかの欄（💼 有給管理など）とそろえる
// - 行全体を押せる（ListTile。余白は既定のまま）。右の ↗ は外部のブラウザで開くことを示す
// - 「プライバシー」「ポリシー」の区切りで折り返す（幅 360dp・2.0 倍で「ー」だけが落ちないように）
// - 開いている途中は、もう一度押しても何もしない
// - 開けなかったら、URL つきの ⚠️ をオレンジで 6 秒。［コピー］で URL をクリップボードに入れる（D21 B）
// - N138＋N139 4a：行は PrivacyPolicyTile に切り出した（購入画面と共通。E27 A）
import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/services/about_app.dart';
import 'package:shiftsleep/widgets/privacy_policy_tile.dart';

class AboutAppSection extends StatefulWidget {
  const AboutAppSection({super.key, this.opener = openInExternalBrowser});

  /// 開く関数（テストで差し替える）
  final UrlOpener opener;

  @override
  State<AboutAppSection> createState() => _AboutAppSectionState();
}

class _AboutAppSectionState extends State<AboutAppSection> {
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
          child: PrivacyPolicyTile(opener: widget.opener),
        ),
      ],
    );
  }
}
