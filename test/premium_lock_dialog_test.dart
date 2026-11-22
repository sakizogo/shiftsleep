// N138＋N139 4b：🔒 のダイアログ（showPremiumLockDialog）の［プレミアム版に登録］から購入画面を開く
//
// PremiumService を偽のものに差し替え、configure しているかで、購入画面を開くか「ℹ️ 準備中です」かが分かれることを確かめる
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/screens/premium_purchase_screen.dart';
import 'package:shiftsleep/services/premium_purchase.dart';
import 'package:shiftsleep/services/premium_service.dart';
import 'package:shiftsleep/widgets/premium_lock_dialog.dart';

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

  int fetchCalls = 0;

  @override
  Future<bool> isRevenueCatConfigured() async => true;

  @override
  Future<List<PremiumPlan>> fetchPremiumPlans() async {
    fetchCalls++;
    return [_monthly];
  }

  @override
  Future<bool> purchase(PremiumPlan plan, {String userId = 'test_user'}) async => true;
}

final _monthly = PremiumPlan(
  PremiumPlanKind.monthly,
  const Package(
    r'$rc_monthly',
    PackageType.monthly,
    StoreProduct('shiftsleep_test_monthly', '', '', 6.99, 'US\$6.99', 'USD'),
    PresentedOfferingContext('default', null, null),
  ),
);

void main() {
  late _FakePremiumService service;
  late SleepProvider provider;
  late bool configured;
  late int configuredCalls;

  const openLabel = '🔒 を開く';
  final dialog = find.byType(AlertDialog);
  final registerButton = find.widgetWithText(ElevatedButton, 'プレミアム版に登録');
  final purchaseScreen = find.byType(PremiumPurchaseScreen);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _FakePremiumService();
    provider = SleepProvider(_NoRepository(), premiumService: service);
    configured = true;
    configuredCalls = 0;
  });

  /// 幅 360dp の端末で、ボタンから 🔒 のダイアログを出す
  Future<void> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<SleepProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showPremiumLockDialog(
                    context,
                    title: 'ロックの見出し',
                    message: 'ロックの案内',
                    isRevenueCatConfigured: () async {
                      configuredCalls++;
                      return configured;
                    },
                  ),
                  child: const Text(openLabel),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(openLabel));
    await tester.pumpAndSettle();
    expect(dialog, findsOneWidget);
  }

  testWidgets('configure 済み：ダイアログが閉じ、購入画面が 1 枚開いて商品を読み込む', (tester) async {
    await openDialog(tester);

    await tester.tap(registerButton);
    await tester.pumpAndSettle();

    expect(dialog, findsNothing);
    expect(purchaseScreen, findsOneWidget);
    expect(find.text(premiumPurchaseScreenTitle), findsOneWidget);
    expect(service.fetchCalls, 1);
    expect(configuredCalls, 1);
  });

  testWidgets('D31 A・D32 A：configure していない → ダイアログが閉じ、青の「ℹ️ 準備中です」で、購入画面は開かない', (tester) async {
    configured = false;
    await openDialog(tester);

    await tester.tap(registerButton);
    await tester.pumpAndSettle();

    expect(dialog, findsNothing);
    expect(purchaseScreen, findsNothing);
    expect(find.text(premiumNotReadyText), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.blue);
    expect(service.fetchCalls, 0);
  });

  testWidgets('［閉じる］→ ダイアログが閉じ、何も開かず、何も出さない', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();

    expect(dialog, findsNothing);
    expect(purchaseScreen, findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(configuredCalls, 0);
  });

  testWidgets('D33 A：続けて 2 回押しても、閉じる途中に押しても、購入画面は 1 枚だけ', (tester) async {
    // 続けて 2 回（間にフレームを進めない）
    await openDialog(tester);
    await tester.tap(registerButton);
    await tester.tap(registerButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(purchaseScreen, findsOneWidget);
    expect(configuredCalls, 1);

    // 閉じる途中（閉じるアニメーションの最中）にもう一度押す
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text(openLabel));
    await tester.pumpAndSettle();
    await tester.tap(registerButton);
    await tester.pump(const Duration(milliseconds: 50));
    expect(dialog, findsOneWidget, reason: 'まだ閉じる途中');
    final button = tester.renderObject(registerButton);
    final hit = tester.hitTestOnBinding(tester.getCenter(registerButton));
    final reachesButton = hit.path.any((entry) => entry.target == button);
    debugPrint('[test] 4b D33：閉じる途中の［プレミアム版に登録］に押した位置が届くか: $reachesButton');
    expect(reachesButton, isFalse, reason: '閉じる途中のダイアログは押せない（印がなくても防げる）');
    await tester.tap(registerButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(purchaseScreen, findsOneWidget);
    expect(configuredCalls, 2);
  });

  testWidgets('購入画面から戻ると元の画面に戻り、ダイアログはもう一度出ない', (tester) async {
    await openDialog(tester);
    await tester.tap(registerButton);
    await tester.pumpAndSettle();
    expect(purchaseScreen, findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(purchaseScreen, findsNothing);
    expect(dialog, findsNothing);
    expect(find.text(openLabel), findsOneWidget);
  });

  testWidgets('購入画面で購入が成功 → 購入画面が閉じ、元の画面に ✨ が出て、プレミアム版になる', (tester) async {
    await openDialog(tester);
    await tester.tap(registerButton);
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: purchaseScreen, matching: find.byType(ElevatedButton)));
    await tester.pumpAndSettle();

    expect(purchaseScreen, findsNothing);
    expect(find.text(openLabel), findsOneWidget);
    expect(find.text(premiumPurchaseMessage(PremiumPurchaseOutcome.success)!.text), findsOneWidget);
    expect(provider.isPremiumUser, isTrue);
  });
}
