// N138＋N139 4a：購入画面（PremiumPurchaseScreen）
//
// PremiumService を偽のものに差し替え、商品・購入・復元の結果で画面と SnackBar が出し分けられることを確かめる
// 幅は 360dp の端末。テスト用のフォントは 1 文字 1em 四方
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/screens/premium_purchase_screen.dart';
import 'package:shiftsleep/services/about_app.dart';
import 'package:shiftsleep/services/premium_purchase.dart';
import 'package:shiftsleep/services/premium_service.dart';
import 'package:shiftsleep/services/review_unlock.dart';
import 'package:shiftsleep/widgets/review_code_dialog.dart';

class _NoRepository extends SleepRepository {
  @override
  Future<SleepRecord?> getLatestSleepRecord(String userId) async => null;

  @override
  Future<List<SleepRecord>> getSleepRecordsByDateRange(String userId, DateTime startDate, DateTime endDate) async =>
      const [];
}

/// RevenueCat と DB を呼ばない偽の PremiumService
class _FakePremiumService extends PremiumService {
  _FakePremiumService() : super.withRepository(ShiftRepository());

  bool configured = true;
  Future<List<PremiumPlan>> Function() onFetch = () async => const [];
  Future<bool> Function() onPurchase = () async => true;
  Future<bool> Function() onRestore = () async => false;
  int fetchCalls = 0;

  @override
  Future<bool> isRevenueCatConfigured() async => configured;

  @override
  Future<List<PremiumPlan>> fetchPremiumPlans() {
    fetchCalls++;
    return onFetch();
  }

  @override
  Future<bool> purchase(PremiumPlan plan, {String userId = 'test_user'}) => onPurchase();

  @override
  Future<bool> restore({String userId = 'test_user'}) => onRestore();
}

PlatformException _error(PurchasesErrorCode code) => PlatformException(code: '${code.index}');

/// N213：テスト用の審査用コード（本物のコードはテストにも書かない）
const _reviewCode = 'TEST-CODE-1A';

/// N213：保存に失敗する store
class _FailingReviewStore extends ReviewUnlockStore {
  const _FailingReviewStore();

  @override
  Future<bool> save() async => false;
}

/// N213：保存を待たせる store（complete するまで処理中のまま）
class _WaitingReviewStore extends ReviewUnlockStore {
  _WaitingReviewStore();

  final saving = Completer<bool>();

  @override
  Future<bool> save() => saving.future;
}

/// 0 円・2 週間のトライアル（Test Store の形：introductoryPrice）
const _twoWeeksFree = IntroductoryPrice(0, 'US\$0.00', 'P2W', 1, PeriodUnit.week, 2);

PremiumPlan _plan(PremiumPlanKind kind, {bool trial = true}) {
  final monthly = kind == PremiumPlanKind.monthly;
  return PremiumPlan(
    kind,
    Package(
      monthly ? r'$rc_monthly' : r'$rc_annual',
      monthly ? PackageType.monthly : PackageType.annual,
      StoreProduct(
        monthly ? 'shiftsleep_test_monthly' : 'shiftsleep_test_yearly',
        '',
        '',
        monthly ? 6.99 : 69.99,
        monthly ? 'US\$6.99' : 'US\$69.99',
        'USD',
        introductoryPrice: trial ? _twoWeeksFree : null,
      ),
      const PresentedOfferingContext('default', null, null),
    ),
  );
}

final _monthly = _plan(PremiumPlanKind.monthly);
final _annual = _plan(PremiumPlanKind.annual);

const _monthlyTrialTerms = '14 日間の無料期間のあと、US\$6.99／月 で自動的に更新されます。無料期間が終わった日に、最初の料金が請求されます。';
const _annualTrialTerms = '14 日間の無料期間のあと、US\$69.99／年 で自動的に更新されます。無料期間が終わった日に、最初の料金が請求されます。';

/// ボタンの文字の大きさと行の高さ
const double _fontSize = 14;
const double _lineHeightRatio = 1.5;

void main() {
  late _FakePremiumService service;
  late SleepProvider provider;
  late List<Uri> opened;
  late bool openResult;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _FakePremiumService();
    service.onFetch = () async => [_monthly, _annual];
    provider = SleepProvider(_NoRepository(), premiumService: service);
    opened = [];
    openResult = true;
  });

  final purchaseButton = find.byType(ElevatedButton);
  final restoreButton = find.widgetWithText(OutlinedButton, premiumRestoreLabel);
  final screen = find.byType(PremiumPurchaseScreen);

  /// 幅 360dp の端末で、ホームから購入画面を開く
  Future<void> openScreen(WidgetTester tester, {double scale = 1.0, bool settle = true}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<SleepProvider>.value(
        value: provider,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PremiumPurchaseScreen(
                        opener: (uri) async {
                          opened.add(uri);
                          return openResult;
                        },
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 区切りの文言が 1 行に収まっている（premium_status_panel_test と同じ判定）
  /// 🎁 は 2 つの UTF-16 の単位なので、文字数は runes で数える
  void expectOneLine(WidgetTester tester, String part, double scale) {
    final size = tester.getSize(find.text(part));
    expect(size.width, greaterThanOrEqualTo(part.runes.length * _fontSize * scale - 0.01), reason: '「$part」が折り返している（幅）');
    expect(size.height, lessThan(_fontSize * scale * _lineHeightRatio * 1.5), reason: '「$part」が折り返している（高さ）');
  }

  group('文言と出し分け（純粋関数）', () {
    test('定期購入のリンクの区切りをつなげると、リンクの文言と同じ', () {
      expect(manageSubscriptionLabelParts.join(), manageSubscriptionLabel);
      expect(manageSubscriptionLabel, 'Google Play で定期購入を管理する');
    });

    test('購入の結果：キャンセルと処理中は何も出さず、ほかは絵文字つきで色を分ける', () {
      expect(premiumPurchaseMessage(PremiumPurchaseOutcome.cancelled), isNull);
      expect(premiumPurchaseMessage(PremiumPurchaseOutcome.inProgress), isNull);
      expect(premiumPurchaseMessage(PremiumPurchaseOutcome.success)!.color, Colors.green);
      expect(premiumPurchaseMessage(PremiumPurchaseOutcome.notEntitled)!.color, AppColors.warningRed);
      expect(premiumPurchaseMessage(PremiumPurchaseOutcome.network)!.color, Colors.orange);
      expect(premiumPurchaseMessage(PremiumPurchaseOutcome.pending)!.color, Colors.blue);
      expect(premiumPurchaseMessage(PremiumPurchaseOutcome.ownedByOtherAccount)!.text,
          '⚠️ この定期購入は別の Google アカウントで購入されています');
      expect(premiumPurchaseMessage(PremiumPurchaseOutcome.notConfigured)!.text, premiumNotReadyText);
      expect(premiumPurchaseMessage(PremiumPurchaseOutcome.failed)!.color, AppColors.warningRed);
      for (final outcome in PremiumPurchaseOutcome.values) {
        final text = premiumPurchaseMessage(outcome)?.text;
        if (text == null) continue;
        expect(text, matches(RegExp(r'^(✨|❌|⚠️|ℹ️) ')), reason: outcome.name);
      }
    });

    test('復元の結果：処理中は何も出さず、ほかは絵文字つきで色を分ける', () {
      expect(premiumRestoreMessage(PremiumRestoreOutcome.inProgress), isNull);
      expect(premiumRestoreMessage(PremiumRestoreOutcome.restored)!.color, Colors.green);
      expect(premiumRestoreMessage(PremiumRestoreOutcome.nothingToRestore)!.color, Colors.blue);
      expect(premiumRestoreMessage(PremiumRestoreOutcome.network)!.color, Colors.orange);
      expect(premiumRestoreMessage(PremiumRestoreOutcome.notConfigured)!.text, premiumNotReadyText);
      expect(premiumRestoreMessage(PremiumRestoreOutcome.failed)!.color, AppColors.warningRed);
    });

    test('E28 B：最初に選ぶのは月額。1 つしかないときはそれ。ないときは null', () {
      expect(defaultSelectedPlanKind([_annual, _monthly]), PremiumPlanKind.monthly);
      expect(defaultSelectedPlanKind([_annual]), PremiumPlanKind.annual);
      expect(defaultSelectedPlanKind(const []), isNull);
    });

    test('条件：トライアルありの年額', () {
      final lines = premiumTermsLines(_annual);
      expect(lines.first, _annualTrialTerms);
      expect(lines, contains('無料期間が終わる前に解約すれば、料金はかかりません。'));
      expect(lines.last, premiumCancelHowToText);
    });

    test('条件：トライアルなしの月額は、無料期間の文を出さない', () {
      final lines = premiumTermsLines(_plan(PremiumPlanKind.monthly, trial: false));
      expect(lines.first, 'US\$6.99／月 で、1 か月ごとに自動的に更新されます。');
      expect(lines.where((line) => line.contains('無料期間')), isEmpty);
      expect(lines, contains('いつでも解約できます。解約しても、その期間の終わりまではプレミアム版を使えます。'));
    });
  });

  testWidgets('読み込みの途中は、ぐるぐると「プランを読み込んでいます…」', (tester) async {
    final plans = Completer<List<PremiumPlan>>();
    service.onFetch = () => plans.future;
    await openScreen(tester, settle: false);

    expect(find.text(premiumPlansLoadingText), findsOneWidget);
    expect(purchaseButton, findsNothing);
    plans.complete([_monthly, _annual]);
    await tester.pumpAndSettle();
    expect(find.text(premiumPlansLoadingText), findsNothing);
  });

  testWidgets('2 枚のカードが出て、月額が選ばれ、お得は年額だけ、トライアルは両方', (tester) async {
    await openScreen(tester);

    expect(find.text('月額プラン'), findsOneWidget);
    expect(find.text('年額プラン'), findsOneWidget);
    expect(find.text('US\$6.99／月'), findsOneWidget);
    expect(find.text('US\$69.99／年'), findsOneWidget);
    expect(find.text('🎁 最初の 14 日間 無料'), findsNWidgets(2));
    expect(find.text('🏷️ 16% お得'), findsOneWidget);
    expect(find.text(premiumSelectedLabel), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.text('・$_monthlyTrialTerms'), findsOneWidget);
  });

  testWidgets('年額のカードを押すと選び直され、条件の文も年額になる', (tester) async {
    await openScreen(tester);

    await tapVisible(tester, find.text('年額プラン'));

    expect(find.text('・$_annualTrialTerms'), findsOneWidget);
    expect(find.text('・$_monthlyTrialTerms'), findsNothing);
    expect(find.text(premiumSelectedLabel), findsOneWidget);
  });

  testWidgets('トライアルあり：ボタンは「🎁 14 日間」「無料で始める」', (tester) async {
    await openScreen(tester);

    final texts = tester.widgetList<Text>(find.descendant(of: purchaseButton, matching: find.byType(Text)));
    expect(texts.map((text) => text.data), ['🎁 14 日間', '無料で始める']);
  });

  testWidgets('トライアルなし：トライアルの行は出ず、ボタンは「✨ 月額プランを」「購入する」', (tester) async {
    service.onFetch = () async => [
          _plan(PremiumPlanKind.monthly, trial: false),
          _plan(PremiumPlanKind.annual, trial: false),
        ];
    await openScreen(tester);

    expect(find.textContaining('🎁'), findsNothing);
    final texts = tester.widgetList<Text>(find.descendant(of: purchaseButton, matching: find.byType(Text)));
    expect(texts.map((text) => text.data), ['✨ 月額プランを', '購入する']);
    expect(find.text('・US\$6.99／月 で、1 か月ごとに自動的に更新されます。'), findsOneWidget);
  });

  testWidgets('年額しかないとき：年額が選ばれ、お得は出さない', (tester) async {
    service.onFetch = () async => [_annual];
    await openScreen(tester);

    expect(find.text('月額プラン'), findsNothing);
    expect(find.text(premiumSelectedLabel), findsOneWidget);
    expect(find.textContaining('お得'), findsNothing);
    expect(find.text('・$_annualTrialTerms'), findsOneWidget);
  });

  final failures = <String, ({Future<List<PremiumPlan>> Function() fetch, bool configured, String text, bool reload})>{
    'empty': (fetch: () async => const [], configured: true, text: premiumPlansEmptyText, reload: true),
    'network': (
      fetch: () async => throw _error(PurchasesErrorCode.networkError),
      configured: true,
      text: premiumPlansNetworkText,
      reload: true,
    ),
    'failed': (
      fetch: () async => throw _error(PurchasesErrorCode.storeProblemError),
      configured: true,
      text: premiumPlansFailedText,
      reload: true,
    ),
    'notConfigured': (fetch: () async => const [], configured: false, text: premiumNotReadyText, reload: false),
  };
  failures.forEach((name, failure) {
    testWidgets('商品が読めない（$name）：文言が出て、購入のボタンと条件は出ない。復元とプライバシーポリシーは出る', (tester) async {
      service.onFetch = failure.fetch;
      service.configured = failure.configured;
      await openScreen(tester);

      expect(find.text(failure.text), findsOneWidget);
      expect(find.text(premiumReloadLabel), failure.reload ? findsOneWidget : findsNothing);
      expect(purchaseButton, findsNothing);
      expect(find.text(premiumTermsTitle), findsNothing);
      expect(restoreButton, findsOneWidget);
      expect(find.text(privacyPolicyLabelParts.first), findsOneWidget);
    });
  });

  testWidgets('［再読み込み］でもう一度読み、読めたらカードが出る', (tester) async {
    service.onFetch = () async => throw _error(PurchasesErrorCode.networkError);
    await openScreen(tester);
    service.onFetch = () async => [_monthly, _annual];

    await tapVisible(tester, find.text(premiumReloadLabel));

    expect(service.fetchCalls, 2);
    expect(find.text('月額プラン'), findsOneWidget);
    expect(find.text(premiumPlansNetworkText), findsNothing);
  });

  testWidgets('購入の途中は、購入・復元のボタンとカードが押せない', (tester) async {
    final purchase = Completer<bool>();
    service.onPurchase = () => purchase.future;
    await openScreen(tester);

    await tester.ensureVisible(purchaseButton);
    await tester.pumpAndSettle();
    await tester.tap(purchaseButton);
    await tester.pump();

    expect(provider.isPremiumBusy, isTrue);
    expect(tester.widget<ElevatedButton>(purchaseButton).enabled, isFalse);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).enabled, isFalse);
    expect(find.descendant(of: purchaseButton, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    final card = tester.widget<InkWell>(find.ancestor(of: find.text('年額プラン'), matching: find.byType(InkWell)));
    expect(card.onTap, isNull);

    purchase.complete(false);
    await tester.pumpAndSettle();
  });

  testWidgets('購入できた：画面を閉じて ✨ を出す', (tester) async {
    service.onPurchase = () async => true;
    await openScreen(tester);

    await tapVisible(tester, purchaseButton);

    expect(screen, findsNothing);
    expect(find.text(premiumPurchaseMessage(PremiumPurchaseOutcome.success)!.text), findsOneWidget);
    expect(provider.isPremiumUser, isTrue);
  });

  testWidgets('キャンセル：何も出さず、購入画面のまま', (tester) async {
    service.onPurchase = () async => throw _error(PurchasesErrorCode.purchaseCancelledError);
    await openScreen(tester);

    await tapVisible(tester, purchaseButton);

    expect(screen, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('通信できない：⚠️ をオレンジで出し、購入画面のまま', (tester) async {
    service.onPurchase = () async => throw _error(PurchasesErrorCode.networkError);
    await openScreen(tester);

    await tapVisible(tester, purchaseButton);

    expect(screen, findsOneWidget);
    expect(find.text(premiumPurchaseMessage(PremiumPurchaseOutcome.network)!.text), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.orange);
  });

  testWidgets('復元できた：画面を閉じて ✨ を出す', (tester) async {
    service.onRestore = () async => true;
    await openScreen(tester);

    await tapVisible(tester, restoreButton);

    expect(screen, findsNothing);
    expect(find.text(premiumRestoreMessage(PremiumRestoreOutcome.restored)!.text), findsOneWidget);
  });

  testWidgets('復元できる購入がない：ℹ️ を出し、購入画面のまま', (tester) async {
    service.onRestore = () async => false;
    await openScreen(tester);

    await tapVisible(tester, restoreButton);

    expect(screen, findsOneWidget);
    expect(find.text(premiumRestoreMessage(PremiumRestoreOutcome.nothingToRestore)!.text), findsOneWidget);
  });

  testWidgets('E31 B：［Google Play で定期購入を管理する］で定期購入の画面を開く', (tester) async {
    await openScreen(tester);

    await tapVisible(tester, find.text(manageSubscriptionLabelParts.first));

    expect(opened, [Uri.parse(playSubscriptionsUrl)]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('E31 B：開けなかったら、URL つきの ⚠️ をオレンジで出す（［コピー］つき）', (tester) async {
    openResult = false;
    await openScreen(tester);

    await tapVisible(tester, find.text(manageSubscriptionLabelParts.first));

    expect(find.text(manageSubscriptionOpenFailedText), findsOneWidget);
    expect(manageSubscriptionOpenFailedText, contains(playSubscriptionsUrl));
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.orange);
    expect(find.text(copyUrlActionLabel), findsOneWidget);
  });

  testWidgets('プライバシーポリシーの行を押すと、プライバシーポリシーを開く', (tester) async {
    await openScreen(tester);

    await tapVisible(tester, find.text(privacyPolicyLabelParts.first));

    expect(opened, [Uri.parse(privacyPolicyUrl)]);
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('幅 360dp・倍率 $scale：はみ出しの例外がなく、購入のボタンの区切りがそれぞれ 1 行に収まる', (tester) async {
      await openScreen(tester, scale: scale);

      expect(tester.takeException(), isNull);
      for (final part in premiumPurchaseButtonParts(_monthly)) {
        expectOneLine(tester, part, scale);
      }
    });
  }

  testWidgets('読み上げ：カードは 1 つにまとまり、選んでいるものには「選択中」が付く', (tester) async {
    final handle = tester.ensureSemantics();
    await openScreen(tester);

    expect(find.bySemanticsLabel('月額プラン、US\$6.99／月、最初の 14 日間 無料、選択中'), findsOneWidget);
    expect(find.bySemanticsLabel('年額プラン、US\$69.99／年、最初の 14 日間 無料、16% お得'), findsOneWidget);
    expect(find.bySemanticsLabel('🎁 14 日間無料で始める'), findsOneWidget);
    handle.dispose();
  });

  // N213：AppBar の見出しを 2 秒長押しして開く、審査用コードのダイアログ
  group('N213：審査用コード', () {
    final title = find.text(premiumPurchaseScreenTitle);
    final dialog = find.byType(ReviewCodeDialog);

    /// 審査用コードを知っている provider に替える（openScreen の前に呼ぶ）
    void useReviewCode({ReviewUnlockStore? store}) {
      provider = SleepProvider(_NoRepository(), premiumService: service, reviewUnlockStore: store, reviewCode: _reviewCode);
    }

    /// 見出しを duration だけ押してから離す
    Future<void> pressTitle(WidgetTester tester, Duration duration) async {
      final gesture = await tester.startGesture(tester.getCenter(title));
      await tester.pump(duration);
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Future<void> openDialog(WidgetTester tester) => pressTitle(tester, reviewCodeLongPressDuration);

    Future<void> submit(WidgetTester tester, String code) async {
      await tester.enterText(find.byType(TextField), code);
      await tester.tap(find.text(reviewCodeUnlockLabel));
      await tester.pumpAndSettle();
    }

    test('知らせは文の頭に記号を付け、色を分ける（解除できたときだけ、いつもの色で記号なし）', () {
      expect(reviewCodeResultMessage(ReviewCodeDialogResult.unlocked), (text: '✨ 審査用コードでプレミアム版を解放しました', color: Colors.green));
      expect(reviewCodeResultMessage(ReviewCodeDialogResult.unlockedThisSessionOnly).color, Colors.orange);
      expect(reviewCodeResultMessage(ReviewCodeDialogResult.unlockedThisSessionOnly).text, matches(RegExp(r'^⚠️ .*再起動すると元に戻ります$')));
      expect(reviewCodeResultMessage(ReviewCodeDialogResult.clearNotSaved).color, Colors.orange);
      expect(reviewCodeResultMessage(ReviewCodeDialogResult.clearNotSaved).text, matches(RegExp(r'^⚠️ .*再起動すると解放された状態に戻ります$')));
      expect(reviewCodeResultMessage(ReviewCodeDialogResult.cleared), (text: '審査用コードの解放を解除しました', color: null));
      expect(reviewCodeWrongText, '❌ コードが違います');
    });

    testWidgets('2 秒の長押しで開き、1 秒では開かない', (tester) async {
      useReviewCode();
      await openScreen(tester);

      await pressTitle(tester, const Duration(seconds: 1));
      expect(dialog, findsNothing);

      await openDialog(tester);
      expect(dialog, findsOneWidget);
      expect(find.text(reviewCodeDialogTitle), findsOneWidget);
      expect(find.text(reviewCodeClearLabel), findsNothing);  // 解放していないので［解除する］は出ない
    });

    testWidgets('D49 A：正しいコードなら購入画面を閉じて、緑の ✨ を出す。購入・復元は呼ばない', (tester) async {
      useReviewCode();
      var purchases = 0;
      var restores = 0;
      service.onPurchase = () async => (++purchases) > 0;
      service.onRestore = () async => (++restores) > 0;
      await openScreen(tester);
      await openDialog(tester);

      await submit(tester, ' test-code-1a ');

      expect(dialog, findsNothing);
      expect(screen, findsNothing);
      expect(find.text(reviewUnlockedText), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.green);
      expect(provider.isPremiumUser, isTrue);
      expect(provider.isReviewUnlockOnly, isTrue);
      expect(purchases, 0);
      expect(restores, 0);
    });

    testWidgets('処理中は、戻る操作でも外のタップでも、ダイアログも購入画面も閉じない', (tester) async {
      final store = _WaitingReviewStore();
      useReviewCode(store: store);
      await openScreen(tester);
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), _reviewCode);
      await tester.tap(find.text(reviewCodeUnlockLabel));
      await tester.pump();

      await tester.binding.handlePopRoute();  // 戻るボタン
      await tester.pump();
      await tester.tapAt(const Offset(5, 400));  // ダイアログの外
      await tester.pump();

      expect(dialog, findsOneWidget);
      expect(screen, findsOneWidget);

      // 保存が終わると、ダイアログと購入画面だけが閉じる（その下の画面は残る）
      store.saving.complete(true);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(screen, findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(find.text(reviewUnlockedText), findsOneWidget);
    });

    testWidgets('D46 A：違うコードなら閉じずに、入力欄の下に「❌ コードが違います」（エラーの色）', (tester) async {
      useReviewCode();
      await openScreen(tester);
      await openDialog(tester);

      await submit(tester, 'TEST-CODE-1B');

      expect(dialog, findsOneWidget);
      expect(find.text(reviewCodeWrongText), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(reviewCodeWrongText)).style?.color,
        Theme.of(tester.element(dialog)).colorScheme.error,
      );
      expect(provider.isPremiumUser, isFalse);

      // もう一度、正しいコードなら解放できる（E39：回数の制限はない）
      await submit(tester, _reviewCode);
      expect(screen, findsNothing);
      expect(provider.isPremiumUser, isTrue);
    });

    testWidgets('［キャンセル］で閉じ、何も出さず購入画面のまま', (tester) async {
      useReviewCode();
      await openScreen(tester);
      await openDialog(tester);

      await tester.tap(find.text(reviewCodeCancelLabel));
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(screen, findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(provider.isPremiumUser, isFalse);
    });

    testWidgets('D50 A：保存に失敗したら、⚠️ をオレンジで出す（この起動中は解放）', (tester) async {
      useReviewCode(store: const _FailingReviewStore());
      await openScreen(tester);
      await openDialog(tester);

      await submit(tester, _reviewCode);

      expect(screen, findsNothing);
      expect(find.text(reviewUnlockNotSavedText), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.orange);
      expect(provider.isPremiumUser, isTrue);
    });

    testWidgets('D47 A：解放中に開くと［解除する］が出て、押すと解除し、いつもの色で知らせる（購入画面のまま）', (tester) async {
      useReviewCode();
      await provider.unlockWithReviewCode(_reviewCode);
      await openScreen(tester);
      await openDialog(tester);

      await tester.tap(find.text(reviewCodeClearLabel));
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(screen, findsOneWidget);
      expect(find.text(reviewClearedText), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, isNull);
      expect(provider.isPremiumUser, isFalse);
      expect(provider.isReviewUnlocked, isFalse);
    });

    for (final name in ['failed', 'network', 'empty']) {
      testWidgets('商品が読めない（$name）ときも、長押しで開いて解放できる', (tester) async {
        useReviewCode();
        service.onFetch = switch (name) {
          'failed' => () async => throw _error(PurchasesErrorCode.storeProblemError),
          'network' => () async => throw _error(PurchasesErrorCode.networkError),
          _ => () async => const <PremiumPlan>[],
        };
        await openScreen(tester);
        expect(purchaseButton, findsNothing);

        await openDialog(tester);
        await submit(tester, _reviewCode);

        expect(screen, findsNothing);
        expect(provider.isPremiumUser, isTrue);
      });
    }
  });
}
