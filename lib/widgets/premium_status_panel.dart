// N138＋N139 3：設定画面の「💳 プレミアム版ステータス」の欄（D16 B：設定画面から切り出し）
//
// - 見出し・枠（プレミアムは緑、無料は灰色）・プランの表示・できること・ボタン（利用中なら「ご利用中」）
// - 枠の中の一番下には footer を置く（設定画面の 🧪 と「💡 改善アドバイス表示設定」。E22 A）
// - P2（D18 A）：ボタンから値段を外す（値段は 4a の購入画面でストアの値を出す）
// - ボタンと「ご利用中」は区切りで折り返し、大きい文字でも最後の 1〜2 文字だけが落ちないようにする（E23 A・E24 A。P1 と同じやり方）
// - 色だけで区別しない（バッジは文字つき、アイコンも変える）
// - N138＋N139 4c：プレミアムのときは「ご利用中」の下に「Google Play で定期購入を管理する ↗」を出す
//   - 4a の購入画面と同じ部品・URL（固定）・文言・開けなかったときの知らせを使う（D34 A・D35 A・D37 A・D38 A）
//   - isPremium で出し分ける（🧪 の上書きでプレミアムの表示でも出す。無料では出さない。D36 A）
// - N213 D48 B：プレミアムの表示で、審査用コードだけで解放中（isReviewUnlockOnly）なら「✅ 審査用コードで解放中です」を出し、
//   定期購入の管理のリンクは出さない。🧪 で無料の表示にしているときは、いつもの無料のパネル
//   - D47 A：その文字だけを 2 秒の長押しで包み、onReviewLongPress を呼ぶ（リリース版でも購入画面を通らずに解除できる。読み上げは今のまま）
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/screens/premium_purchase_screen.dart';
import 'package:shiftsleep/services/about_app.dart';
import 'package:shiftsleep/widgets/privacy_policy_tile.dart';
import 'package:shiftsleep/widgets/review_code_dialog.dart';

/// 欄の見出し
const premiumStatusSectionTitle = '💳 プレミアム版ステータス';

/// バッジの文字
const premiumPlanFreeLabel = '無料版';
const premiumPlanPremiumLabel = 'プレミアム版 ✨';

/// 無料のときに出す、プレミアム版でできること
const premiumBenefitsIntro = 'プレミアム版でできることは：';
const premiumBenefits = ['📊 改善アドバイスをすべて表示', '💡 アドバイスごとの実行ヒント', '🛏️ 睡眠の目安の理由・仮眠・3日分の目安'];

/// アップグレード ボタンの文字（読み上げにはこの 1 つを使う）。P2：値段は入れない
const premiumUpgradeLabel = '✨ プレミアム版にアップグレード';

/// 画面では、この区切りで折り返す。つなげると premiumUpgradeLabel と同じ
const premiumUpgradeLabelParts = ['✨ プレミアム版に', 'アップグレード'];

/// プレミアムのときの文字（読み上げにはこの 1 つを使う）
const premiumInUseLabel = '✅ プレミアム版をご利用中です';

/// 画面では、この区切りで折り返す。つなげると premiumInUseLabel と同じ
const premiumInUseLabelParts = ['✅ プレミアム版を', 'ご利用中です'];

/// N213 D48 B：審査用コードだけで解放中のときの文字（読み上げにはこの 1 つを使う）
const premiumReviewUnlockLabel = '✅ 審査用コードで解放中です';

/// 画面では、この区切りで折り返す。つなげると premiumReviewUnlockLabel と同じ
const premiumReviewUnlockLabelParts = ['✅ 審査用コードで', '解放中です'];

class PremiumStatusPanel extends StatelessWidget {
  const PremiumStatusPanel({
    super.key,
    required this.isPremium,
    required this.onUpgrade,
    this.isLoading = false,
    this.footer,
    this.opener = openInExternalBrowser,
    this.isReviewUnlockOnly = false,
    this.onReviewLongPress,
  });

  /// プレミアムか（設定画面は SleepProvider の値を渡す）
  final bool isPremium;

  /// N213：審査用コードだけで解放中か（設定画面は SleepProvider.isReviewUnlockOnly を渡す。isPremium のときだけ効く）
  final bool isReviewUnlockOnly;

  /// N213 D47 A：「審査用コードで解放中です」を 2 秒長押ししたときの処理（設定画面は審査用コードのダイアログを開く）
  final VoidCallback? onReviewLongPress;

  /// アップグレード ボタンを押したときの処理（null なら押せない）。4a で購入画面を開く処理に替える
  final VoidCallback? onUpgrade;

  /// ボタンの中にぐるぐるを出すか
  final bool isLoading;

  /// 枠の中の一番下に置くもの
  final Widget? footer;

  /// 4c：定期購入の画面を開く関数（テストで差し替える）
  final UrlOpener opener;

  @override
  Widget build(BuildContext context) {
    final reviewUnlockOnly = isPremium && isReviewUnlockOnly;  // N213 D48 B
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          premiumStatusSectionTitle,
          style: AppTextStyles.sectionTitleStyle,
        ),
        const SizedBox(height: AppDimensions.paddingMedium),

        Container(
          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
          decoration: BoxDecoration(
            color: isPremium
                ? Colors.green.withValues(alpha: 0.05)
                : Colors.grey.withValues(alpha: 0.05),
            border: Border.all(
              color: isPremium
                  ? Colors.green
                  : AppColors.borderDefault,
            ),
            borderRadius: BorderRadius.circular(
              AppDimensions.borderRadiusMedium,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'あなたのプラン',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 4.0,
                        ),
                        decoration: BoxDecoration(
                          color: isPremium
                              ? Colors.green
                              : AppColors.textMuted,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: Text(
                          isPremium ? premiumPlanPremiumLabel : premiumPlanFreeLabel,
                          style: AppTextStyles.bodyTextStyle.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    isPremium ? Icons.check_circle : Icons.info,
                    color: isPremium ? Colors.green : AppColors.textMuted,
                    size: 40,
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.paddingMedium),

              if (!isPremium) ...[
                Text(
                  premiumBenefitsIntro,
                  style: AppTextStyles.bodyTextStyle.copyWith(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8.0),
                for (final benefit in premiumBenefits) _buildBenefitItem(benefit),
                const SizedBox(height: AppDimensions.paddingMedium),
              ],

              if (!isPremium)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onUpgrade,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGradientStart,
                      disabledBackgroundColor: AppColors.textMuted,
                      padding: EdgeInsets.symmetric(
                        vertical: AppDimensions.paddingMedium,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDimensions.borderRadiusMedium,
                        ),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              strokeWidth: 2,
                            ),
                          )
                        : _buildWrappedLabel(
                            label: premiumUpgradeLabel,
                            parts: premiumUpgradeLabelParts,
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    vertical: AppDimensions.paddingMedium,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      AppDimensions.borderRadiusMedium,
                    ),
                  ),
                  child: Center(
                    child: reviewUnlockOnly
                        ? _buildReviewLongPress(
                            _buildWrappedLabel(
                              label: premiumReviewUnlockLabel,
                              parts: premiumReviewUnlockLabelParts,
                              style: AppTextStyles.bodyTextStyle.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : _buildWrappedLabel(
                            label: premiumInUseLabel,
                            parts: premiumInUseLabelParts,
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              if (isPremium && !reviewUnlockOnly) ...[
                const SizedBox(height: AppDimensions.paddingMedium),
                _buildManageSubscriptionLink(),
              ],
              if (footer case final footer?) footer,
            ],
          ),
        ),
      ],
    );
  }

  /// 4c：定期購入の画面へのリンク（白地・枠・角丸は 4a の購入画面と同じ。ListTile の波紋のために Material で包む）
  Widget _buildManageSubscriptionLink() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
        side: const BorderSide(color: AppColors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExternalLinkTile(
        url: playSubscriptionsUrl,
        label: manageSubscriptionLabel,
        labelParts: manageSubscriptionLabelParts,
        leadingIcon: Icons.subscriptions_outlined,
        open: () => openPlaySubscriptions(open: opener),
        openFailedText: manageSubscriptionOpenFailedText,
      ),
    );
  }

  /// N213 D47 A：2 秒の長押しで onReviewLongPress を呼ぶ（読み上げの動きは足さない）
  Widget _buildReviewLongPress(Widget child) {
    return RawGestureDetector(
      excludeFromSemantics: true,
      gestures: {
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: reviewCodeLongPressDuration),
          (recognizer) => recognizer.onLongPress = onReviewLongPress,
        ),
      },
      child: child,
    );
  }

  /// 区切りで Wrap に並べ、中央にそろえる。読み上げは label の 1 つにまとめる
  Widget _buildWrappedLabel({
    required String label,
    required List<String> parts,
    required TextStyle style,
  }) {
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (final part in parts) Text(part, style: style),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(String benefit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(
        benefit,
        style: AppTextStyles.bodyTextStyle.copyWith(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
