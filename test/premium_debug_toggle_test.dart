// A-3 3/3：設定画面のプレミアム表示の切り替え（テスト用）のボタン
// N191 2/3：setPremiumStatus もボタンの値（デバッグの上書き）を保つ
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/widgets/premium_debug_toggle.dart';

class _NoRepository extends SleepRepository {
  @override
  Future<SleepRecord?> getLatestSleepRecord(String userId) async => null;

  @override
  Future<List<SleepRecord>> getSleepRecordsByDateRange(String userId, DateTime startDate, DateTime endDate) async =>
      const [];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SleepProvider> pumpButton(WidgetTester tester, Widget button) async {
    final provider = SleepProvider(_NoRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider<SleepProvider>.value(
        value: provider,
        child: MaterialApp(home: Scaffold(body: button)),
      ),
    );
    return provider;
  }

  testWidgets('デバッグでは出て、押すとプレミアムが切り替わる（もう一度押すと戻る）', (tester) async {
    final provider = await pumpButton(tester, const PremiumDebugToggleButton(visible: true));
    expect(provider.isPremiumUser, isFalse);
    expect(find.text('$premiumDebugToggleLabel　今：無料'), findsOneWidget);

    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(provider.isPremiumUser, isTrue);
    expect(find.text(premiumDebugToggledText(true)), findsOneWidget);
    expect(find.text('$premiumDebugToggleLabel　今：プレミアム'), findsOneWidget);

    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(provider.isPremiumUser, isFalse);
    expect(find.text('$premiumDebugToggleLabel　今：無料'), findsOneWidget);
  });

  testWidgets('F6：デバッグでは、切り替えた値を loadAllSleepData のあとも、もう一度押すまで保つ', (tester) async {
    final provider = await pumpButton(tester, const PremiumDebugToggleButton(visible: true));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(provider.isPremiumUser, isTrue);

    // テストでは RevenueCat がないので、PremiumService は無料（false）を返す。それでもプレミアムのまま
    await tester.runAsync(provider.loadAllSleepData);
    await tester.pump();
    expect(provider.isPremiumUser, isTrue);
    expect(find.text('$premiumDebugToggleLabel　今：プレミアム'), findsOneWidget);

    // もう一度押すと無料になり、読み直しても無料のまま
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    await tester.runAsync(provider.loadAllSleepData);
    await tester.pump();
    expect(provider.isPremiumUser, isFalse);
  });

  testWidgets('F6：押していなければ、loadAllSleepData は PremiumService の値のまま', (tester) async {
    final provider = await pumpButton(tester, const PremiumDebugToggleButton(visible: true));
    await tester.runAsync(provider.loadAllSleepData);
    expect(provider.isPremiumUser, isFalse);
  });

  // N191 2/3：setPremiumStatus もデバッグの上書きを通す
  testWidgets('N191 2/3：上書きなし（リリース版と同じ道）なら、setPremiumStatus の値をそのまま使う', (tester) async {
    final provider = await pumpButton(tester, const PremiumDebugToggleButton(visible: true));
    provider.setPremiumStatus(true);
    expect(provider.isPremiumUser, isTrue);
    provider.setPremiumStatus(false);
    expect(provider.isPremiumUser, isFalse);
  });

  testWidgets('N191 2/3：ボタンでプレミアムにしていたら、setPremiumStatus(false) でもプレミアムのまま', (tester) async {
    final provider = await pumpButton(tester, const PremiumDebugToggleButton(visible: true));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();

    provider.setPremiumStatus(false);
    await tester.pump();
    expect(provider.isPremiumUser, isTrue);
    expect(find.text('$premiumDebugToggleLabel　今：プレミアム'), findsOneWidget);
  });

  testWidgets('D13 B：ボタンを 2 回押して本当の値（無料）に戻すと上書きが外れ、setPremiumStatus(true) でプレミアムになる', (tester) async {
    final provider = await pumpButton(tester, const PremiumDebugToggleButton(visible: true));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();

    provider.setPremiumStatus(true);
    expect(provider.isPremiumUser, isTrue);
  });

  testWidgets('D13 B：途中で購入したら、本当の値（プレミアム）と同じになったときに上書きが外れる', (tester) async {
    final provider = await pumpButton(tester, const PremiumDebugToggleButton(visible: true));
    // 1 回目：無料 → プレミアム（上書き true）。そのあと購入（本当の値も true）
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    provider.setPremiumStatus(true);
    expect(provider.isPremiumUser, isTrue);

    // 2 回目：本当の値（true）と違う無料になるので、上書き false。購入の確認があっても無料のまま
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    provider.setPremiumStatus(true);
    expect(provider.isPremiumUser, isFalse);

    // 3 回目：本当の値と同じプレミアムに戻るので上書きが外れ、以後は本当の値に従う
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(provider.isPremiumUser, isTrue);
    provider.setPremiumStatus(false);
    expect(provider.isPremiumUser, isFalse);
  });

  testWidgets('D13 B：loadAllSleepData の値も本当の値として扱う', (tester) async {
    final provider = await pumpButton(tester, const PremiumDebugToggleButton(visible: true));
    provider.setPremiumStatus(true);
    // テストでは RevenueCat がないので、PremiumService は無料（false）を返す。本当の値は false になる
    await tester.runAsync(provider.loadAllSleepData);
    await tester.pump();
    expect(provider.isPremiumUser, isFalse);

    // 本当の値（false）と違うプレミアムになるので、上書きとして保つ
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    provider.setPremiumStatus(false);
    expect(provider.isPremiumUser, isTrue);
  });

  testWidgets('N191 2/3：上書きで値が変わらなくても、setPremiumStatus は 1 回知らせる', (tester) async {
    final provider = await pumpButton(tester, const PremiumDebugToggleButton(visible: true));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    var notified = 0;
    provider.addListener(() => notified++);

    provider.setPremiumStatus(false);
    expect(provider.isPremiumUser, isTrue);
    expect(notified, 1);
  });

  testWidgets('visible が false（リリース版と同じ）なら何も出ない', (tester) async {
    await pumpButton(tester, const PremiumDebugToggleButton(visible: false));
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.textContaining(premiumDebugToggleLabel), findsNothing);
  });

  testWidgets('既定（visible は kDebugMode）では、テストはデバッグで動くので出る', (tester) async {
    expect(kDebugMode, isTrue);
    await pumpButton(tester, const PremiumDebugToggleButton());
    expect(find.byType(OutlinedButton), findsOneWidget);
  });
}
