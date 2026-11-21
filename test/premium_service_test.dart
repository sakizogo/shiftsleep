import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
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

  // 1b：ShiftRepository を差し替えて、RevenueCat の結果と DB の保存を確かめる
  group('1b：checkPremiumStatus と DB の保存', () {
    // null なら getCustomerInfo を失敗させる
    List<String>? activeEntitlementIds;
    late _FakeShiftRepository repository;
    late PremiumService service;

    setUp(() {
      activeEntitlementIds = const [];
      repository = _FakeShiftRepository();
      service = PremiumService.withRepository(repository);
      messenger.setMockMethodCallHandler(purchasesChannel, (call) async {
        purchasesCalls.add(call.method);
        if (call.method == 'isConfigured') return true;
        final ids = activeEntitlementIds;
        if (call.method == 'getCustomerInfo' && ids != null) return _customerInfoJson(ids);
        throw PlatformException(code: 'unexpected', message: call.method);
      });
    });

    test('entitlement（ShiftSleep Pro）あり → true を返し、true を保存する', () async {
      activeEntitlementIds = ['ShiftSleep Pro'];

      expect(await service.checkPremiumStatus(), true);

      expect(repository.saved, [('test_user', true)]);
    });

    test('active が空 → false を返し、false を保存する', () async {
      expect(await service.checkPremiumStatus(), false);

      expect(repository.saved, [('test_user', false)]);
    });

    test('別の entitlement だけが active → false', () async {
      activeEntitlementIds = ['Other Pro'];

      expect(await service.checkPremiumStatus(), false);

      expect(repository.saved, [('test_user', false)]);
    });

    test('行をまるごと書かない：AppSettings を読まずに保存する（行がなくても保存される）', () async {
      activeEntitlementIds = ['ShiftSleep Pro'];

      expect(await service.checkPremiumStatus(), true);

      expect(repository.getAppSettingsCalls, 0);
      expect(repository.saved, [('test_user', true)]);
    });

    test('D22 A：DB に保存できなくても RevenueCat の結果を返し、例外は外に出ない', () async {
      activeEntitlementIds = ['ShiftSleep Pro'];
      repository.saveError = Exception('db');

      expect(await service.checkPremiumStatus(), true);

      expect(repository.saved, [('test_user', true)]);
    });

    test('D22 A：保存に失敗したあと RevenueCat の確認が失敗したら、キャッシュの true を返す', () async {
      activeEntitlementIds = ['ShiftSleep Pro'];
      repository.saveError = Exception('db');
      expect(await service.checkPremiumStatus(), true);

      activeEntitlementIds = null;
      expect(await service.checkPremiumStatus(), true);

      expect(repository.saved, hasLength(1));
    });

    test('RevenueCat の確認が失敗したら、保存は呼ばず、前の値（初期は false）を返す', () async {
      activeEntitlementIds = null;

      expect(await service.checkPremiumStatus(), false);

      expect(repository.saved, isEmpty);
    });

    test('updatePremiumStatusToDatabase は失敗を外に伝える', () async {
      final error = Exception('db');
      repository.saveError = error;

      await expectLater(service.updatePremiumStatusToDatabase('test_user', true), throwsA(same(error)));
      expect(repository.saved, [('test_user', true)]);
    });
  });
}

/// 1b：updateIsPremiumUser の呼び出しを記録し、getAppSettings を数える偽の ShiftRepository（DB は開かない）
class _FakeShiftRepository extends ShiftRepository {
  final saved = <(String, bool)>[];
  Object? saveError;
  int getAppSettingsCalls = 0;

  @override
  Future<void> updateIsPremiumUser(String userId, bool isPremium) async {
    saved.add((userId, isPremium));
    if (saveError != null) throw saveError!;
  }

  @override
  Future<AppSettings?> getAppSettings(String userId) async {
    getAppSettingsCalls++;
    return null;
  }
}

/// getCustomerInfo がチャンネルから返す JSON（CustomerInfo.fromJson が読む最小限）
Map<String, Object?> _customerInfoJson(List<String> activeEntitlementIds) {
  const date = '2026-11-21T00:00:00Z';
  final entitlements = {
    for (final id in activeEntitlementIds)
      id: {
        'identifier': id,
        'isActive': true,
        'willRenew': true,
        'latestPurchaseDate': date,
        'originalPurchaseDate': date,
        'productIdentifier': 'shiftsleep_monthly',
        'isSandbox': true,
      },
  };
  return {
    'entitlements': {'all': entitlements, 'active': entitlements},
    'allPurchaseDates': <String, Object?>{},
    'activeSubscriptions': <String>[],
    'allPurchasedProductIdentifiers': <String>[],
    'nonSubscriptionTransactions': <Object?>[],
    'firstSeen': date,
    'originalAppUserId': 'test_app_user',
    'allExpirationDates': <String, Object?>{},
    'requestDate': date,
  };
}
