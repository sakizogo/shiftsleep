// N138＋N139 2：SleepProvider の購入・復元・商品の取得の入口（D14 B）
//
// PremiumService を偽のものに差し替え、結果の種類と Provider の値を確かめる
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/premium_purchase.dart';
import 'package:shiftsleep/services/premium_service.dart';

class _NoRepository extends SleepRepository {
  @override
  Future<SleepRecord?> getLatestSleepRecord(String userId) async => null;

  @override
  Future<List<SleepRecord>> getSleepRecordsByDateRange(String userId, DateTime startDate, DateTime endDate) async =>
      const [];
}

/// RevenueCat を呼ばない偽の PremiumService（呼ばれた回数を数える）
class _FakePremiumService extends PremiumService {
  _FakePremiumService() : super.withRepository(ShiftRepository());

  bool configured = true;
  Future<bool> Function() onPurchase = () async => true;
  Future<bool> Function() onRestore = () async => true;
  Future<List<PremiumPlan>> Function() onFetchPlans = () async => const [];
  int purchaseCalls = 0;
  int restoreCalls = 0;
  int fetchPlansCalls = 0;

  @override
  Future<bool> isRevenueCatConfigured() async => configured;

  @override
  Future<bool> purchase(PremiumPlan plan, {String userId = 'test_user'}) {
    purchaseCalls++;
    return onPurchase();
  }

  @override
  Future<bool> restore({String userId = 'test_user'}) {
    restoreCalls++;
    return onRestore();
  }

  @override
  Future<List<PremiumPlan>> fetchPremiumPlans() {
    fetchPlansCalls++;
    return onFetchPlans();
  }
}

/// RevenueCat と同じ形の例外（code は PurchasesErrorCode の番号）
PlatformException _error(PurchasesErrorCode code) => PlatformException(code: '${code.index}');

PremiumPlan _plan(PremiumPlanKind kind, String identifier, String priceString) => PremiumPlan(
      kind,
      Package(
        identifier,
        kind == PremiumPlanKind.monthly ? PackageType.monthly : PackageType.annual,
        StoreProduct('shiftsleep_$identifier', '', '', 0, priceString, 'JPY'),
        const PresentedOfferingContext('default', null, null),
      ),
    );

void main() {
  late _FakePremiumService service;
  late SleepProvider provider;
  final monthly = _plan(PremiumPlanKind.monthly, r'$rc_monthly', '¥980');
  final annual = _plan(PremiumPlanKind.annual, r'$rc_annual', '¥9,800');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _FakePremiumService();
    provider = SleepProvider(_NoRepository(), premiumService: service);
  });

  group('purchasePremium', () {
    test('entitlement あり → success でプレミアムになる', () async {
      expect(await provider.purchasePremium(monthly), PremiumPurchaseOutcome.success);

      expect(provider.isPremiumUser, isTrue);
      expect(service.purchaseCalls, 1);
    });

    test('購入は通ったが entitlement なし → notEntitled で無料のまま', () async {
      service.onPurchase = () async => false;

      expect(await provider.purchasePremium(monthly), PremiumPurchaseOutcome.notEntitled);

      expect(provider.isPremiumUser, isFalse);
    });

    test('キャンセル → cancelled で値は変えず、復元もしない', () async {
      service.onPurchase = () async => throw _error(PurchasesErrorCode.purchaseCancelledError);

      expect(await provider.purchasePremium(monthly), PremiumPurchaseOutcome.cancelled);

      expect(provider.isPremiumUser, isFalse);
      expect(service.restoreCalls, 0);
    });

    test('ネットワーク → network', () async {
      service.onPurchase = () async => throw _error(PurchasesErrorCode.networkError);

      expect(await provider.purchasePremium(monthly), PremiumPurchaseOutcome.network);
    });

    test('保留中 → pending でプレミアムにはしない', () async {
      service.onPurchase = () async => throw _error(PurchasesErrorCode.paymentPendingError);

      expect(await provider.purchasePremium(monthly), PremiumPurchaseOutcome.pending);

      expect(provider.isPremiumUser, isFalse);
    });

    test('購入済み → 復元して entitlement あり → success でプレミアムになる', () async {
      service.onPurchase = () async => throw _error(PurchasesErrorCode.productAlreadyPurchasedError);

      expect(await provider.purchasePremium(monthly), PremiumPurchaseOutcome.success);

      expect(provider.isPremiumUser, isTrue);
      expect(service.restoreCalls, 1);
    });

    test('購入済み → 復元しても entitlement なし → ownedByOtherAccount', () async {
      service.onPurchase = () async => throw _error(PurchasesErrorCode.receiptAlreadyInUseError);
      service.onRestore = () async => false;

      expect(await provider.purchasePremium(monthly), PremiumPurchaseOutcome.ownedByOtherAccount);

      expect(provider.isPremiumUser, isFalse);
    });

    test('購入済み → 復元がネットワークで失敗 → network（E13 A）', () async {
      service.onPurchase = () async => throw _error(PurchasesErrorCode.productAlreadyPurchasedError);
      service.onRestore = () async => throw _error(PurchasesErrorCode.networkError);

      expect(await provider.purchasePremium(monthly), PremiumPurchaseOutcome.network);
    });

    test('処理中の 2 回目 → inProgress で、購入は 1 回だけ（E12 A）', () async {
      final completer = Completer<bool>();
      service.onPurchase = () => completer.future;

      final first = provider.purchasePremium(monthly);
      expect(await provider.purchasePremium(annual), PremiumPurchaseOutcome.inProgress);
      expect(await provider.restorePremium(), PremiumRestoreOutcome.inProgress);
      completer.complete(true);

      expect(await first, PremiumPurchaseOutcome.success);
      expect(service.purchaseCalls, 1);
      expect(service.restoreCalls, 0);
    });

    test('configure していない → notConfigured で購入を呼ばない（D25 B）', () async {
      service.configured = false;

      expect(await provider.purchasePremium(monthly), PremiumPurchaseOutcome.notConfigured);

      expect(service.purchaseCalls, 0);
      expect(provider.isPremiumBusy, isFalse);
    });

    test('そのほかの例外 → failed', () async {
      service.onPurchase = () async => throw _error(PurchasesErrorCode.storeProblemError);

      expect(await provider.purchasePremium(monthly), PremiumPurchaseOutcome.failed);
    });

    test('途中は isPremiumBusy が true で知らせ、終わったら false に戻す', () async {
      final completer = Completer<bool>();
      service.onPurchase = () => completer.future;
      var notified = 0;
      provider.addListener(() => notified++);

      final purchase = provider.purchasePremium(monthly);
      expect(provider.isPremiumBusy, isTrue);
      expect(notified, 1);
      completer.complete(true);
      await purchase;

      expect(provider.isPremiumBusy, isFalse);
    });
  });

  group('restorePremium', () {
    test('entitlement あり → restored でプレミアムになる', () async {
      expect(await provider.restorePremium(), PremiumRestoreOutcome.restored);

      expect(provider.isPremiumUser, isTrue);
    });

    test('entitlement なし → nothingToRestore', () async {
      service.onRestore = () async => false;

      expect(await provider.restorePremium(), PremiumRestoreOutcome.nothingToRestore);

      expect(provider.isPremiumUser, isFalse);
    });

    test('ネットワーク → network', () async {
      service.onRestore = () async => throw _error(PurchasesErrorCode.networkError);

      expect(await provider.restorePremium(), PremiumRestoreOutcome.network);
    });

    test('そのほかの例外 → failed', () async {
      service.onRestore = () async => throw _error(PurchasesErrorCode.storeProblemError);

      expect(await provider.restorePremium(), PremiumRestoreOutcome.failed);
    });

    test('configure していない → notConfigured で復元を呼ばない', () async {
      service.configured = false;

      expect(await provider.restorePremium(), PremiumRestoreOutcome.notConfigured);

      expect(service.restoreCalls, 0);
    });
  });

  group('loadPremiumPlans', () {
    test('月額・年額 → ready で premiumPlans に入る', () async {
      service.onFetchPlans = () async => [monthly, annual];

      expect(await provider.loadPremiumPlans(), PremiumPlansOutcome.ready);

      expect(provider.premiumPlans.map((plan) => plan.kind), [PremiumPlanKind.monthly, PremiumPlanKind.annual]);
    });

    test('商品がない → empty', () async {
      expect(await provider.loadPremiumPlans(), PremiumPlansOutcome.empty);

      expect(provider.premiumPlans, isEmpty);
    });

    test('configure していない → notConfigured で取得を呼ばない', () async {
      service.configured = false;

      expect(await provider.loadPremiumPlans(), PremiumPlansOutcome.notConfigured);

      expect(service.fetchPlansCalls, 0);
    });

    test('ネットワーク → network で premiumPlans は空にする', () async {
      service.onFetchPlans = () async => [monthly, annual];
      await provider.loadPremiumPlans();
      service.onFetchPlans = () async => throw _error(PurchasesErrorCode.networkError);

      expect(await provider.loadPremiumPlans(), PremiumPlansOutcome.network);

      expect(provider.premiumPlans, isEmpty);
    });
  });
}
