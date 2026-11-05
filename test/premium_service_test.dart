import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/premium_service.dart';
import 'package:sqflite/sqflite.dart';

/// N26：RevenueCat を configure していないときの PremiumService の動き
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const purchasesChannel = MethodChannel('purchases_flutter');
  const sqfliteChannel = MethodChannel('com.tekartik.sqflite');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final purchasesCalls = <String>[];
  final sqfliteCalls = <String>[];

  void mockConfigured(bool configured) {
    messenger.setMockMethodCallHandler(purchasesChannel, (call) async {
      purchasesCalls.add(call.method);
      if (call.method == 'isConfigured') return configured;
      throw PlatformException(code: 'unexpected', message: call.method);
    });
  }

  setUp(() {
    // テスト環境でも DB の処理がチャンネルを通るようにして、読みに行ったら記録する（実際の DB は開かない）
    databaseFactoryOrNull = databaseFactorySqflitePlugin;
    messenger.setMockMethodCallHandler(sqfliteChannel, (call) async {
      sqfliteCalls.add(call.method);
      throw PlatformException(code: 'unexpected', message: call.method);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(purchasesChannel, null);
    messenger.setMockMethodCallHandler(sqfliteChannel, null);
    databaseFactoryOrNull = null;
    purchasesCalls.clear();
    sqfliteCalls.clear();
  });

  test('未 configure：checkPremiumStatus は false で getCustomerInfo を呼ばない', () async {
    mockConfigured(false);

    expect(await PremiumService().checkPremiumStatus(), false);

    expect(PremiumService().isPremiumUser, false);
    expect(purchasesCalls, ['isConfigured']);
  });

  test('未 configure：loadPremiumStatusFromDatabase は DB を読まず false', () async {
    mockConfigured(false);

    expect(await PremiumService().loadPremiumStatusFromDatabase('test_user'), false);

    expect(purchasesCalls, ['isConfigured']);
    expect(sqfliteCalls, isEmpty);
  });

  test('確認自体が失敗（プラグインなし）でも例外にならず false', () async {
    expect(await PremiumService().isRevenueCatConfigured(), false);
    expect(await PremiumService().checkPremiumStatus(), false);
    expect(await PremiumService().loadPremiumStatusFromDatabase('test_user'), false);

    expect(sqfliteCalls, isEmpty);
  });

  test('configure 済みなら getCustomerInfo と DB まで進む（失敗しても例外にせず false）', () async {
    mockConfigured(true);

    expect(await PremiumService().checkPremiumStatus(), false);
    expect(purchasesCalls, ['isConfigured', 'getCustomerInfo']);

    // DB の検出が働いていることの確認も兼ねる（ここが空なら上の isEmpty は意味がない）
    expect(await PremiumService().loadPremiumStatusFromDatabase('test_user'), false);
    expect(sqfliteCalls, isNotEmpty);
  });
}
