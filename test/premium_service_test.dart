import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/services/premium_purchase.dart';
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

  // N138＋N139 2：購入・復元・商品の取得（チャンネルの mock から JSON を返す）
  group('2：購入・復元・商品の取得', () {
    // メソッド名 → 返す値（Exception なら投げる）
    final responses = <String, Object?>{};
    final purchaseArguments = <Object?>[];
    late _FakeShiftRepository repository;
    late PremiumService service;
    final networkError = PlatformException(code: '${PurchasesErrorCode.networkError.index}');
    // チャンネルを通ると例外は作り直されるので、code で比べる
    final throwsNetworkError =
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', networkError.code));
    final monthlyPlan = PremiumPlan(
      PremiumPlanKind.monthly,
      Package.fromJson(_packageJson(r'$rc_monthly', 'MONTHLY', '¥980')),
    );

    setUp(() {
      responses.clear();
      purchaseArguments.clear();
      repository = _FakeShiftRepository();
      service = PremiumService.withRepository(repository);
      messenger.setMockMethodCallHandler(purchasesChannel, (call) async {
        purchasesCalls.add(call.method);
        if (call.method == 'isConfigured') return true;
        if (call.method == 'purchasePackage') purchaseArguments.add(call.arguments);
        if (responses.containsKey(call.method)) {
          final response = responses[call.method];
          if (response is Exception) throw response;
          return response;
        }
        throw PlatformException(code: 'unexpected', message: call.method);
      });
    });

    test('購入：entitlement あり → true を返し、package を渡し、true を保存する', () async {
      responses['purchasePackage'] = _purchaseResultJson(['ShiftSleep Pro']);

      expect(await service.purchase(monthlyPlan), true);

      expect((purchaseArguments.single as Map)['packageIdentifier'], r'$rc_monthly');
      expect(repository.saved, [('test_user', true)]);
    });

    test('購入：entitlement なし → false を返し、false を保存する（E16 A）', () async {
      responses['purchasePackage'] = _purchaseResultJson(const []);

      expect(await service.purchase(monthlyPlan), false);

      expect(repository.saved, [('test_user', false)]);
    });

    test('購入：D22 A：DB に保存できなくても true を返す', () async {
      responses['purchasePackage'] = _purchaseResultJson(['ShiftSleep Pro']);
      repository.saveError = Exception('db');

      expect(await service.purchase(monthlyPlan), true);
    });

    test('購入：RevenueCat の例外は外に伝え、保存しない', () async {
      responses['purchasePackage'] = networkError;

      await expectLater(service.purchase(monthlyPlan), throwsNetworkError);
      expect(repository.saved, isEmpty);
    });

    test('復元：entitlement あり → true を返し、true を保存する', () async {
      responses['restorePurchases'] = _customerInfoJson(['ShiftSleep Pro']);

      expect(await service.restore(), true);

      expect(repository.saved, [('test_user', true)]);
    });

    test('復元：entitlement なし → false を返し、false を保存する', () async {
      responses['restorePurchases'] = _customerInfoJson(const []);

      expect(await service.restore(), false);

      expect(repository.saved, [('test_user', false)]);
    });

    test('復元：RevenueCat の例外は外に伝え、保存しない', () async {
      responses['restorePurchases'] = networkError;

      await expectLater(service.restore(), throwsNetworkError);
      expect(repository.saved, isEmpty);
    });

    test('商品：current の月額・年額を、月額・年額の順で返す（値段はストアの文字）', () async {
      responses['getOfferings'] = _offeringsJson(
        monthly: _packageJson(r'$rc_monthly', 'MONTHLY', '¥980'),
        annual: _packageJson(r'$rc_annual', 'ANNUAL', '¥9,800'),
      );

      final plans = await service.fetchPremiumPlans();

      expect(plans.map((plan) => plan.kind), [PremiumPlanKind.monthly, PremiumPlanKind.annual]);
      expect(plans.map((plan) => plan.priceString), ['¥980', '¥9,800']);
      expect(plans.map((plan) => plan.package.identifier), [r'$rc_monthly', r'$rc_annual']);
    });

    test('商品：current がない → 空', () async {
      responses['getOfferings'] = _offeringsJson(hasCurrent: false);

      expect(await service.fetchPremiumPlans(), isEmpty);
    });

    test('商品：RevenueCat の例外は外に伝える', () async {
      responses['getOfferings'] = networkError;

      await expectLater(service.fetchPremiumPlans(), throwsNetworkError);
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

/// 2：purchasePackage がチャンネルから返す JSON（PurchaseResult.fromJson が読む最小限）
Map<String, Object?> _purchaseResultJson(List<String> activeEntitlementIds) => {
      'customerInfo': _customerInfoJson(activeEntitlementIds),
      'transaction': {
        'transactionIdentifier': 'test_transaction',
        'productIdentifier': 'shiftsleep_monthly',
        'purchaseDate': '2026-11-21T00:00:00Z',
      },
    };

/// 2：Package の JSON（Package.fromJson が読む最小限）
Map<String, Object?> _packageJson(String identifier, String packageType, String priceString) => {
      'identifier': identifier,
      'packageType': packageType,
      'product': {
        'identifier': 'shiftsleep_$identifier',
        'description': '',
        'title': '',
        'price': 0,
        'priceString': priceString,
        'currencyCode': 'JPY',
      },
      'presentedOfferingContext': {'offeringIdentifier': 'default'},
    };

/// 2：getOfferings がチャンネルから返す JSON（Offerings.fromJson が読む最小限）
Map<String, Object?> _offeringsJson({
  Map<String, Object?>? monthly,
  Map<String, Object?>? annual,
  bool hasCurrent = true,
}) {
  final offering = {
    'identifier': 'default',
    'serverDescription': '',
    'metadata': <String, Object>{},
    'availablePackages': [if (monthly != null) monthly, if (annual != null) annual],
    'monthly': monthly,
    'annual': annual,
  };
  return {
    'all': hasCurrent ? {'default': offering} : <String, Object?>{},
    'current': hasCurrent ? offering : null,
  };
}
