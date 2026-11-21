// N138＋N139 4a：購入画面（D17 A：purchases_flutter だけで作る）
//
// - 設定の［✨ プレミアム版にアップグレード］から開く（configure していないときは設定画面で「準備中です」。D25 B・E25 A）
// - 月額・年額は SleepProvider.loadPremiumPlans() で出す（D19 A'）。値段・トライアルの日数はストアの値（D27〜D29）
// - 最初に選んでおくのは月額（E28 B）。年額には、値段から計算した「お得」の率を付ける（E29 A）
// - 購入の前に条件をはっきり書き、その下に Google Play の定期購入の画面へのリンクを置く（E31 B）
// - ［購入を復元］はこの画面だけ（D26 A）。プライバシーポリシーの行は設定画面と共通（E27 A）
// - 結果の出し分けはコミット 2 の PremiumPurchaseOutcome・PremiumRestoreOutcome のとおり（キャンセルと処理中は何も出さない）
//   成功したら画面を閉じて ✨。SnackBar に例外の中身は出さない（debugPrint だけ）
// - 処理中は SleepProvider.isPremiumBusy でボタンを押せなくする
// - 色だけで区別しない（Wong 2011 の色＋文字・アイコン）。文字の大きさ 1.0・1.3・2.0 倍と幅 360dp で崩れない
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/services/about_app.dart';
import 'package:shiftsleep/services/premium_purchase.dart';
import 'package:shiftsleep/widgets/premium_status_panel.dart';
import 'package:shiftsleep/widgets/privacy_policy_tile.dart';

/// AppBar の文字
const premiumPurchaseScreenTitle = '✨ プレミアム版';

/// 「プランを選ぶ」の見出し
const premiumPlanSectionTitle = '📋 プランを選ぶ';

/// 商品を読んでいる途中
const premiumPlansLoadingText = 'プランを読み込んでいます…';

/// 商品が読めないとき
const premiumPlansEmptyText = 'ℹ️ いまは購入できるプランがありません。しばらくしてからもう一度お試しください';
const premiumPlansNetworkText = '⚠️ 通信できませんでした。電波のよいところで［再読み込み］を押してください';
const premiumPlansFailedText = '❌ プランを読み込めませんでした。しばらくしてからもう一度お試しください';

/// configure していないとき（D25 B。設定画面でも使う）
const premiumNotReadyText = 'ℹ️ 準備中です';

/// ［再読み込み］
const premiumReloadLabel = '🔄 再読み込み';

/// 選んでいるカードの印
const premiumSelectedLabel = '選択中';

/// 「ご購入の前に」の見出し
const premiumTermsTitle = '📝 ご購入の前に';

/// ［購入を復元］
const premiumRestoreLabel = '🔄 購入を復元';

/// E31 B：Google Play の定期購入の画面
const playSubscriptionsUrl = 'https://play.google.com/store/account/subscriptions?package=jp.sakizoapps.shiftsleep';

/// 定期購入の画面へのリンクの文言（読み上げにはこの 1 つを使う）
const manageSubscriptionLabel = 'Google Play で定期購入を管理する';

/// 画面では、この区切りで折り返す。つなげると manageSubscriptionLabel と同じ
/// 「Google Play」の途中や「で」だけで割れないよう、「 で」は次の区切りの頭に付ける
const manageSubscriptionLabelParts = ['Google Play', ' で定期購入を', '管理する'];

/// 定期購入の画面を開けなかったときの知らせ（プライバシーポリシーと同じ形）
const manageSubscriptionOpenFailedText = '⚠️ 定期購入の画面を開けませんでした。ブラウザで $playSubscriptionsUrl を開いてください';

/// 選んでいるカードの色（Wong 2011: Blue。白い文字との明るさの差は 4.5:1 以上）
const Color premiumSelectedColor = Color(0xFF0072B2);

/// 「お得」のバッジの色（Wong 2011: Orange。文字は黒）
const Color premiumSavingsColor = Color(0xFFE69F00);

/// 解約の方法
const premiumCancelHowToText =
    '解約の方法：Google Play ストア アプリ → プロフィールのアイコン → お支払いと定期購入 → 定期購入 → ShiftSleep → 定期購入を解約';

/// 定期購入の画面を開く。開けなかった・例外のときは false（例外は外に出さない）
Future<bool> openPlaySubscriptions({UrlOpener open = openInExternalBrowser}) async {
  try {
    return await open(Uri.parse(playSubscriptionsUrl));
  } catch (e) {
    debugPrint('⚠️ N138＋N139 4a: 定期購入の画面を開けませんでした: $e');
    return false;
  }
}

/// プランの名前
String premiumPlanName(PremiumPlanKind kind) => switch (kind) {
      PremiumPlanKind.monthly => '月額プラン',
      PremiumPlanKind.annual => '年額プラン',
    };

/// 値段と期間（例：US$6.99／月）
String premiumPlanPriceText(PremiumPlan plan) => '${plan.priceString}／${plan.periodLabel}';

/// カードのトライアルの行（例：🎁 最初の 14 日間 無料）
String premiumTrialText(PremiumTrial trial) => '🎁 最初の ${trial.label} 無料';

/// 年額のバッジ（例：🏷️ 16% お得）
String premiumSavingsText(int percent) => '🏷️ $percent% お得';

/// 最初に選んでおくプラン（E28 B：月額。どちらか 1 つしかないときはそれ）
PremiumPlanKind? defaultSelectedPlanKind(List<PremiumPlan> plans) {
  if (plans.isEmpty) return null;
  for (final plan in plans) {
    if (plan.kind == PremiumPlanKind.monthly) return plan.kind;
  }
  return plans.first.kind;
}

/// 年額の「お得」の率（月額と年額の両方があるときだけ）
int? premiumSavingsPercentOf(List<PremiumPlan> plans) {
  PremiumPlan? monthly;
  PremiumPlan? annual;
  for (final plan in plans) {
    if (plan.kind == PremiumPlanKind.monthly) monthly = plan;
    if (plan.kind == PremiumPlanKind.annual) annual = plan;
  }
  if (monthly == null || annual == null) return null;
  return annualSavingsPercent(monthly.package.storeProduct, annual.package.storeProduct);
}

/// 「ご購入の前に」の文（上から順に。選んだプランとトライアルで変わる）
List<String> premiumTermsLines(PremiumPlan plan) {
  final price = premiumPlanPriceText(plan);
  final trial = plan.trial;
  final renewEvery = switch (plan.kind) {
    PremiumPlanKind.monthly => '1 か月ごとに',
    PremiumPlanKind.annual => '1 年ごとに',
  };
  return [
    if (trial != null) ...[
      '${trial.label}の無料期間のあと、$price で自動的に更新されます。無料期間が終わった日に、最初の料金が請求されます。',
      '無料期間が終わる前に解約すれば、料金はかかりません。',
    ] else
      '$price で、$renewEvery自動的に更新されます。',
    'お支払いは Google Play のアカウントに請求されます。',
    'いつでも解約できます。解約しても、その期間の終わりまではプレミアム版を使えます。',
    premiumCancelHowToText,
  ];
}

/// 購入のボタンの文字の区切り（つなげたものを読み上げに使う）
List<String> premiumPurchaseButtonParts(PremiumPlan plan) {
  final trial = plan.trial;
  if (trial != null) return ['🎁 ${trial.label}', '無料で始める'];
  return ['✨ ${premiumPlanName(plan.kind)}を', '購入する'];
}

/// カードの読み上げ（1 つにまとめる。絵文字は入れない）
String premiumPlanSemanticsLabel(PremiumPlan plan, {int? savingsPercent, required bool selected}) {
  final trial = plan.trial;
  return [
    premiumPlanName(plan.kind),
    premiumPlanPriceText(plan),
    if (trial != null) '最初の ${trial.label} 無料',
    if (savingsPercent != null) '$savingsPercent% お得',
    if (selected) premiumSelectedLabel,
  ].join('、');
}

/// logcat で見る、トライアルの取り出し元の 1 行（キーは出さない）
String premiumPlanLogLine(PremiumPlan plan) {
  final trial = plan.trial;
  return '[PremiumPurchase] 🎁 商品: plan=${plan.kind.name}, price=${plan.priceString}, '
      'trial=${trial?.label ?? 'なし'}, source=${trial?.source.name ?? '-'}';
}

/// 購入の結果の知らせ（null なら何も出さない：キャンセル・処理中）
({String text, Color color})? premiumPurchaseMessage(PremiumPurchaseOutcome outcome) {
  switch (outcome) {
    case PremiumPurchaseOutcome.success:
      return (text: '✨ プレミアム版になりました。ありがとうございます！', color: Colors.green);
    case PremiumPurchaseOutcome.notEntitled:
      return (
        text: '❌ 購入は完了しましたが、プレミアム版を有効にできませんでした。［購入を復元］をお試しください',
        color: AppColors.warningRed,
      );
    case PremiumPurchaseOutcome.network:
      return (text: '⚠️ 通信できませんでした。電波のよいところでもう一度お試しください', color: Colors.orange);
    case PremiumPurchaseOutcome.pending:
      return (text: 'ℹ️ お支払いの確認待ちです。確認が終わるとプレミアム版になります', color: Colors.blue);
    case PremiumPurchaseOutcome.ownedByOtherAccount:
      return (text: '⚠️ この定期購入は別の Google アカウントで購入されています', color: Colors.orange);
    case PremiumPurchaseOutcome.notConfigured:
      return (text: premiumNotReadyText, color: Colors.blue);
    case PremiumPurchaseOutcome.failed:
      return (text: '❌ 購入できませんでした。しばらくしてからもう一度お試しください', color: AppColors.warningRed);
    case PremiumPurchaseOutcome.cancelled:
    case PremiumPurchaseOutcome.inProgress:
      return null;
  }
}

/// 復元の結果の知らせ（null なら何も出さない：処理中）
({String text, Color color})? premiumRestoreMessage(PremiumRestoreOutcome outcome) {
  switch (outcome) {
    case PremiumRestoreOutcome.restored:
      return (text: '✨ 購入を復元しました。プレミアム版をご利用いただけます', color: Colors.green);
    case PremiumRestoreOutcome.nothingToRestore:
      return (text: 'ℹ️ 復元できる購入が見つかりませんでした', color: Colors.blue);
    case PremiumRestoreOutcome.network:
      return (text: '⚠️ 通信できませんでした。電波のよいところでもう一度お試しください', color: Colors.orange);
    case PremiumRestoreOutcome.notConfigured:
      return (text: premiumNotReadyText, color: Colors.blue);
    case PremiumRestoreOutcome.failed:
      return (text: '❌ 復元できませんでした。しばらくしてからもう一度お試しください', color: AppColors.warningRed);
    case PremiumRestoreOutcome.inProgress:
      return null;
  }
}

class PremiumPurchaseScreen extends StatefulWidget {
  const PremiumPurchaseScreen({super.key, this.opener = openInExternalBrowser});

  /// 外部のページを開く関数（テストで差し替える）
  final UrlOpener opener;

  @override
  State<PremiumPurchaseScreen> createState() => _PremiumPurchaseScreenState();
}

class _PremiumPurchaseScreenState extends State<PremiumPurchaseScreen> {
  /// 商品の読み込みの結果（null は読んでいる途中）
  PremiumPlansOutcome? _plansOutcome;
  PremiumPlanKind? _selectedKind;
  bool _purchasing = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPlans();
    });
  }

  Future<void> _loadPlans() async {
    setState(() => _plansOutcome = null);
    final provider = context.read<SleepProvider>();
    final outcome = await provider.loadPremiumPlans();
    if (!mounted) return;
    final plans = provider.premiumPlans;
    debugPrint('[PremiumPurchase] 📦 商品の読み込み: outcome=${outcome.name}, plans=${plans.length}');
    for (final plan in plans) {
      debugPrint(premiumPlanLogLine(plan));
    }
    setState(() {
      _plansOutcome = outcome;
      // 読み直しても、選んでいたプランがあればそのまま
      if (!plans.any((plan) => plan.kind == _selectedKind)) {
        _selectedKind = defaultSelectedPlanKind(plans);
      }
    });
  }

  Future<void> _purchase(PremiumPlan plan) async {
    final provider = context.read<SleepProvider>();
    final messenger = ScaffoldMessenger.of(context);  // await 前に取得（閉じたあと設定画面に出す）
    final navigator = Navigator.of(context);
    setState(() => _purchasing = true);
    PremiumPurchaseOutcome outcome;
    try {
      outcome = await provider.purchasePremium(plan);
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
    debugPrint('[PremiumPurchase] 💳 購入の結果: plan=${plan.kind.name}, outcome=${outcome.name}');
    if (outcome == PremiumPurchaseOutcome.success && mounted) navigator.pop();
    _showMessage(messenger, premiumPurchaseMessage(outcome));
  }

  Future<void> _restore() async {
    final provider = context.read<SleepProvider>();
    final messenger = ScaffoldMessenger.of(context);  // await 前に取得
    final navigator = Navigator.of(context);
    setState(() => _restoring = true);
    PremiumRestoreOutcome outcome;
    try {
      outcome = await provider.restorePremium();
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
    debugPrint('[PremiumPurchase] 🔄 復元の結果: outcome=${outcome.name}');
    if (outcome == PremiumRestoreOutcome.restored && mounted) navigator.pop();
    _showMessage(messenger, premiumRestoreMessage(outcome));
  }

  void _showMessage(ScaffoldMessengerState messenger, ({String text, Color color})? message) {
    if (message == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message.text),
        backgroundColor: message.color,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SleepProvider>();
    final busy = provider.isPremiumBusy;
    final plans = _plansOutcome == PremiumPlansOutcome.ready ? provider.premiumPlans : const <PremiumPlan>[];
    PremiumPlan? selected;
    for (final plan in plans) {
      if (plan.kind == _selectedKind) selected = plan;
    }

    return Scaffold(
      appBar: AppBar(title: const Text(premiumPurchaseScreenTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBenefits(),
              const SizedBox(height: AppDimensions.paddingLarge),
              Text(premiumPlanSectionTitle, style: AppTextStyles.sectionTitleStyle),
              const SizedBox(height: AppDimensions.paddingMedium),
              _buildPlans(plans, selected, busy),
              if (selected case final plan?) ...[
                const SizedBox(height: AppDimensions.paddingLarge),
                Text(premiumTermsTitle, style: AppTextStyles.sectionTitleStyle),
                const SizedBox(height: AppDimensions.paddingMedium),
                _buildTerms(plan),
                const SizedBox(height: AppDimensions.paddingLarge),
                _buildPurchaseButton(plan, busy),
              ],
              const SizedBox(height: AppDimensions.paddingMedium),
              OutlinedButton(
                onPressed: busy ? null : _restore,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppDimensions.paddingMedium),
                ),
                child: _restoring ? _buildSpinner(AppColors.textSecondary) : const Text(premiumRestoreLabel),
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _framed(PrivacyPolicyTile(opener: widget.opener)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefits() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          premiumBenefitsIntro,
          style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8.0),
        for (final benefit in premiumBenefits)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(
              benefit,
              style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 14, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }

  Widget _buildPlans(List<PremiumPlan> plans, PremiumPlan? selected, bool busy) {
    final outcome = _plansOutcome;
    if (outcome == null) {
      return Row(
        children: [
          _buildSpinner(AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(premiumPlansLoadingText, style: AppTextStyles.bodyTextStyle)),
        ],
      );
    }
    if (outcome == PremiumPlansOutcome.ready && plans.isNotEmpty) {
      final savings = premiumSavingsPercentOf(plans);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final plan in plans)
            _buildPlanCard(
              plan,
              selected: identical(plan, selected),
              savingsPercent: plan.kind == PremiumPlanKind.annual ? savings : null,
              busy: busy,
            ),
        ],
      );
    }
    final message = switch (outcome) {
      PremiumPlansOutcome.network => premiumPlansNetworkText,
      PremiumPlansOutcome.failed => premiumPlansFailedText,
      PremiumPlansOutcome.notConfigured => premiumNotReadyText,
      PremiumPlansOutcome.empty || PremiumPlansOutcome.ready => premiumPlansEmptyText,
    };
    return Container(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: AppTextStyles.bodyTextStyle),
          // configure していないときは読み直しても同じなので出さない
          if (outcome != PremiumPlansOutcome.notConfigured) ...[
            const SizedBox(height: 8.0),
            TextButton(onPressed: _loadPlans, child: const Text(premiumReloadLabel)),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanCard(
    PremiumPlan plan, {
    required bool selected,
    required int? savingsPercent,
    required bool busy,
  }) {
    final trial = plan.trial;
    final radius = BorderRadius.circular(AppDimensions.borderRadiusMedium);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Semantics(
        label: premiumPlanSemanticsLabel(plan, savingsPercent: savingsPercent, selected: selected),
        button: true,
        selected: selected,
        excludeSemantics: true,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: selected ? premiumSelectedColor : AppColors.borderDefault,
              width: selected ? 3 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: busy ? null : () => setState(() => _selectedKind = plan.kind),
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.paddingMedium),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: selected ? premiumSelectedColor : AppColors.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              premiumPlanName(plan.kind),
                              style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                            if (selected)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: premiumSelectedColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  premiumSelectedLabel,
                                  style: AppTextStyles.bodyTextStyle.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          premiumPlanPriceText(plan),
                          style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w700, fontSize: 18),
                        ),
                        if (trial != null) ...[
                          const SizedBox(height: 4),
                          Text(premiumTrialText(trial), style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 14)),
                        ],
                        if (savingsPercent != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: premiumSavingsColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              premiumSavingsText(savingsPercent),
                              style: AppTextStyles.bodyTextStyle.copyWith(
                                color: Colors.black,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTerms(PremiumPlan plan) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in premiumTermsLines(plan))
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Text('・$line', style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 13)),
            ),
          const SizedBox(height: 4.0),
          _framed(
            ExternalLinkTile(
              url: playSubscriptionsUrl,
              label: manageSubscriptionLabel,
              labelParts: manageSubscriptionLabelParts,
              leadingIcon: Icons.subscriptions_outlined,
              open: () => openPlaySubscriptions(open: widget.opener),
              openFailedText: manageSubscriptionOpenFailedText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseButton(PremiumPlan plan, bool busy) {
    final parts = premiumPurchaseButtonParts(plan);
    return ElevatedButton(
      onPressed: busy ? null : () => _purchase(plan),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryGradientStart,
        disabledBackgroundColor: AppColors.textMuted,
        padding: const EdgeInsets.symmetric(vertical: AppDimensions.paddingMedium),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium)),
      ),
      child: _purchasing
          ? _buildSpinner(Colors.white)
          : Semantics(
              label: parts.join(),
              excludeSemantics: true,
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (final part in parts)
                    Text(
                      part,
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildSpinner(Color color) {
    return SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(color),
        strokeWidth: 2,
      ),
    );
  }

  /// 白地・枠線・角丸（設定画面の「ℹ️ このアプリについて」と同じ）
  Widget _framed(Widget child) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
        side: const BorderSide(color: AppColors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
