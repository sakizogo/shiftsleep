// A-3 2/3：改善アドバイスの詳細（AdviceDetailScreen）のダイアログ
// 🔒 のダイアログを共通の関数（showPremiumLockDialog）にしたあとも、動きが変わらないことを確かめる
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/screens/advice_detail_screen.dart';
import 'package:shiftsleep/services/sleep_advisory_service.dart';
import 'package:shiftsleep/widgets/action_tip_locked_label.dart';  // P1
import 'package:shiftsleep/widgets/premium_lock_dialog.dart';

class _NoRepository extends SleepRepository {}

/// SleepProvider の偽物（画面が読む値だけを持つ）
class _TestProvider extends SleepProvider {
  _TestProvider(this.advices, {this.all}) : super(_NoRepository());

  final List<SleepAdvice> advices;
  final List<SleepAdvice>? all;  // N203：作れたアドバイス（null なら advices と同じ）
  bool premium = false;
  bool promoVisible = true;  // N186

  @override
  List<SleepAdvice> get displayedAdvice => advices;
  @override
  List<SleepAdvice> get allAdvice => all ?? advices;
  @override
  bool get isPremiumUser => premium;
  @override
  bool get advicePromoVisible => promoVisible;
}

void main() {
  final locked = SleepAdvice(
    title: 'ロックされたアドバイス',
    description: 'ロックされた説明',
    category: 'debt',
    priority: 1,
    isPremiumOnly: true,
  );
  final open = SleepAdvice(
    title: 'ふつうのアドバイス',
    description: 'ふつうの説明',
    category: 'sri',
    priority: 1,
    actionTip: 'ヒントの中身',
  );

  // N138＋N139 4b：🔒 の［プレミアム版に登録］が configure を確かめるので、RevenueCat は configure していない扱いにする
  const purchasesChannel = MethodChannel('purchases_flutter');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        purchasesChannel, (call) async => call.method == 'isConfigured' ? false : null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(purchasesChannel, null);
  });

  Future<_TestProvider> pumpScreen(
    WidgetTester tester, {
    bool premium = false,
    bool promoVisible = true,
    List<SleepAdvice>? advices,
    List<SleepAdvice>? all,
  }) async {
    final provider = _TestProvider(advices ?? [locked, open], all: all)
      ..premium = premium
      ..promoVisible = promoVisible;
    await tester.pumpWidget(
      ChangeNotifierProvider<SleepProvider>.value(
        value: provider,
        child: const MaterialApp(home: AdviceDetailScreen()),
      ),
    );
    await tester.pump();
    return provider;
  }

  testWidgets('無料でロックされたアドバイスを押すと、鍵・説明・案内と［閉じる］［プレミアム版に登録］', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('ロックされたアドバイス'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('ロックされたアドバイス')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.byIcon(Icons.lock)), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('ロックされた説明')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text(adviceLockedMessage)), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('閉じる')), findsOneWidget);

    await tester.tap(find.text('プレミアム版に登録'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(premiumComingSoonText), findsOneWidget);
  });

  testWidgets('ロックされていないアドバイスは説明と実行ヒント（無料はロック）で、［閉じる］だけ', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('ふつうのアドバイス'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('ふつうの説明')), findsOneWidget);
    // N186：実行ヒントは 🔒 のアイコン＋文言（中身は出さない）
    expect(find.descendant(of: dialog, matching: find.byType(ActionTipLockedLabel)), findsOneWidget);  // P1
    expect(find.descendant(of: dialog, matching: find.byIcon(Icons.lock)), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('ヒントの中身')), findsNothing);
    expect(find.descendant(of: dialog, matching: find.text('プレミアム版に登録')), findsNothing);

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('N186：無料で案内が OFF なら、実行ヒントは 🔒 の案内も中身も出さない', (tester) async {
    await pumpScreen(tester, promoVisible: false);
    await tester.tap(find.text('ふつうのアドバイス'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('ふつうの説明')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.byType(ActionTipLockedLabel)), findsNothing);  // P1
    expect(find.descendant(of: dialog, matching: find.text('💡 実行ヒント')), findsNothing);
    expect(find.descendant(of: dialog, matching: find.text('ヒントの中身')), findsNothing);
    expect(find.descendant(of: dialog, matching: find.byIcon(Icons.lock)), findsNothing);
  });

  testWidgets('プレミアムではロックされず、実行ヒントの中身が見える', (tester) async {
    await pumpScreen(tester, premium: true);
    await tester.tap(find.text('ロックされたアドバイス'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text(adviceLockedMessage)), findsNothing);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ふつうのアドバイス'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('ヒントの中身')), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(ActionTipLockedLabel)), findsNothing);  // P1
  });

  testWidgets('N189：実行ヒントの鍵の枠は白地で、鍵は textSecondary（amber を使わない）', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('ふつうのアドバイス'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    final lock = tester.widget<Icon>(find.descendant(of: dialog, matching: find.byIcon(Icons.lock)));
    expect(lock.color, AppColors.textSecondary);
    final box = tester.widget<Container>(
      find.ancestor(of: find.byType(ActionTipLockedLabel), matching: find.byType(Container)).first,  // P1
    );
    expect((box.decoration as BoxDecoration).color, Colors.white);
  });

  testWidgets('N189：優先度の札は「優先度 高／中／低」の文字つきで、地は白（【重要】は出さない）', (tester) async {
    SleepAdvice advice(String title, int priority, String category) =>
        SleepAdvice(title: title, description: '$title の説明', category: category, priority: priority);
    await pumpScreen(tester, premium: true, advices: [
      advice('高い', 1, 'debt'),
      advice('中くらい', 2, 'sjl'),
      advice('低い', 3, 'sri'),
    ]);

    expect(find.text('優先度 高・睡眠負債（DEBT）'), findsOneWidget);
    expect(find.text('優先度 中・体内時計のズレ（SJL）'), findsOneWidget);
    expect(find.text('優先度 低・睡眠の規則性（SRI）'), findsOneWidget);
    expect(find.textContaining('【重要】'), findsNothing);

    for (final (label, color) in [
      ('優先度 高・睡眠負債（DEBT）', advicePriorityColor(1)),
      ('優先度 中・体内時計のズレ（SJL）', advicePriorityColor(2)),
      ('優先度 低・睡眠の規則性（SRI）', advicePriorityColor(3)),
    ]) {
      expect(tester.widget<Text>(find.text(label)).style?.color, color);
      final badge = tester.widget<Container>(find.ancestor(of: find.text(label), matching: find.byType(Container)).first);
      expect((badge.decoration as BoxDecoration).color, Colors.white);
    }
    expect([1, 2, 3].map(advicePriorityColor), [Colors.red.shade700, Colors.deepOrange.shade900, Colors.green.shade800]);
  });

  testWidgets('N203：記録が足りずアドバイスが作れないときは N197 の文', (tester) async {
    await pumpScreen(tester, advices: const [], all: const []);
    expect(find.text(adviceNotEnoughRecordsText), findsOneWidget);
    expect(find.textContaining('蓄積'), findsNothing);
  });

  testWidgets('N203：作れたのに出せるものが 0 件なら「今は大きな改善点はありません」', (tester) async {
    await pumpScreen(tester, advices: const [], all: [locked]);
    expect(find.text(adviceNothingToImproveText), findsOneWidget);
    expect(find.text(adviceNotEnoughRecordsText), findsNothing);
  });
}
