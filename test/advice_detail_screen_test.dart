// A-3 2/3：改善アドバイスの詳細（AdviceDetailScreen）のダイアログ
// 🔒 のダイアログを共通の関数（showPremiumLockDialog）にしたあとも、動きが変わらないことを確かめる
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/screens/advice_detail_screen.dart';
import 'package:shiftsleep/services/sleep_advisory_service.dart';

class _NoRepository extends SleepRepository {}

/// SleepProvider の偽物（画面が読む値だけを持つ）
class _TestProvider extends SleepProvider {
  _TestProvider(this.advices) : super(_NoRepository());

  final List<SleepAdvice> advices;
  bool premium = false;

  @override
  List<SleepAdvice> get displayedAdvice => advices;
  @override
  bool get isPremiumUser => premium;
  @override
  bool get advicePromoVisible => true;
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

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_TestProvider> pumpScreen(WidgetTester tester, {bool premium = false}) async {
    final provider = _TestProvider([locked, open])..premium = premium;
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
    expect(find.text('準備中です'), findsOneWidget);
  });

  testWidgets('ロックされていないアドバイスは説明と実行ヒント（無料はロック）で、［閉じる］だけ', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('ふつうのアドバイス'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('ふつうの説明')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('💡 実行ヒント（プレミアム版で解放）')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('プレミアム版に登録')), findsNothing);
    expect(find.descendant(of: dialog, matching: find.byIcon(Icons.lock)), findsNothing);

    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
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
  });
}
