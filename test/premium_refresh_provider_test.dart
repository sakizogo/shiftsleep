// 2b D20 B：SleepProvider.refreshPremiumStatus（裏で RevenueCat に確かめ、違えば setPremiumStatus で更新する）
//
// PremiumService を偽のものに差し替え、値・知らせ・間引き（15 分）を確かめる
import 'dart:async';

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

/// RevenueCat と DB を呼ばない偽の PremiumService
class _FakePremiumService extends PremiumService {
  _FakePremiumService() : super.withRepository(ShiftRepository());

  /// DB に入っている値（loadAllSleepData が読む）
  bool databasePremium = false;
  Future<PremiumVerification> Function() onVerify = () async => PremiumVerification.free;
  Future<bool> Function() onPurchase = () async => true;
  int verifyCalls = 0;

  @override
  Future<bool> isRevenueCatConfigured() async => true;

  @override
  Future<bool> loadPremiumStatusFromDatabase(String userId) async => databasePremium;

  @override
  Future<PremiumVerification> verifyPremiumStatus({String userId = 'test_user'}) {
    verifyCalls++;
    return onVerify();
  }

  @override
  Future<bool> purchase(PremiumPlan plan, {String userId = 'test_user'}) => onPurchase();
}

void main() {
  late _FakePremiumService service;
  late SleepProvider provider;
  final start = DateTime(2026, 11, 21, 8);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _FakePremiumService();
    provider = SleepProvider(_NoRepository(), premiumService: service);
  });

  test('DB は無料で RevenueCat はプレミアム → updated でプレミアムになり、1 回だけ知らせる', () async {
    await provider.loadAllSleepData();
    service.onVerify = () async => PremiumVerification.premium;
    var notified = 0;
    provider.addListener(() => notified++);

    expect(await provider.refreshPremiumStatus(now: start), PremiumRefreshOutcome.updated);

    expect(provider.isPremiumUser, isTrue);
    expect(notified, 1);
  });

  test('DB と RevenueCat が同じ → unchanged で知らせない（ちらつかない）', () async {
    service.databasePremium = true;
    await provider.loadAllSleepData();
    service.onVerify = () async => PremiumVerification.premium;
    var notified = 0;
    provider.addListener(() => notified++);

    expect(await provider.refreshPremiumStatus(now: start), PremiumRefreshOutcome.unchanged);

    expect(provider.isPremiumUser, isTrue);
    expect(notified, 0);
  });

  test('DB はプレミアムでオフライン → unavailable でプレミアムのまま（無料に落とさない）', () async {
    service.databasePremium = true;
    await provider.loadAllSleepData();
    service.onVerify = () async => PremiumVerification.unavailable;

    expect(await provider.refreshPremiumStatus(now: start), PremiumRefreshOutcome.unavailable);

    expect(provider.isPremiumUser, isTrue);
  });

  test('configure していない → notConfigured で値を変えない', () async {
    service.onVerify = () async => PremiumVerification.notConfigured;

    expect(await provider.refreshPremiumStatus(now: start), PremiumRefreshOutcome.notConfigured);

    expect(provider.isPremiumUser, isFalse);
  });

  test('確かめられてから 15 分以内の 2 回目 → skipped で確かめない', () async {
    await provider.refreshPremiumStatus(now: start);

    expect(
      await provider.refreshPremiumStatus(now: start.add(const Duration(minutes: 14, seconds: 59))),
      PremiumRefreshOutcome.skipped,
    );

    expect(service.verifyCalls, 1);
  });

  test('確かめられてから 15 分たったら、もう一度確かめる', () async {
    await provider.refreshPremiumStatus(now: start);

    expect(
      await provider.refreshPremiumStatus(now: start.add(const Duration(minutes: 15))),
      PremiumRefreshOutcome.unchanged,
    );

    expect(service.verifyCalls, 2);
  });

  test('確かめられなかったら間隔を進めず、すぐ次でまた確かめる（E19 A）', () async {
    service.onVerify = () async => PremiumVerification.unavailable;
    await provider.refreshPremiumStatus(now: start);
    service.onVerify = () async => PremiumVerification.premium;

    expect(
      await provider.refreshPremiumStatus(now: start.add(const Duration(minutes: 1))),
      PremiumRefreshOutcome.updated,
    );

    expect(service.verifyCalls, 2);
  });

  test('確かめている途中の 2 回目 → skipped', () async {
    final verification = Completer<PremiumVerification>();
    service.onVerify = () => verification.future;

    final first = provider.refreshPremiumStatus(now: start);
    expect(await provider.refreshPremiumStatus(now: start), PremiumRefreshOutcome.skipped);
    verification.complete(PremiumVerification.free);

    expect(await first, PremiumRefreshOutcome.unchanged);
    expect(service.verifyCalls, 1);
  });

  test('購入の途中 → skipped で確かめない', () async {
    final purchase = Completer<bool>();
    service.onPurchase = () => purchase.future;
    final plan = PremiumPlan(
      PremiumPlanKind.monthly,
      const Package(
        r'$rc_monthly',
        PackageType.monthly,
        StoreProduct('shiftsleep_monthly', '', '', 0, '¥980', 'JPY'),
        PresentedOfferingContext('default', null, null),
      ),
    );

    final purchasing = provider.purchasePremium(plan);
    await pumpEventQueue();
    expect(await provider.refreshPremiumStatus(now: start), PremiumRefreshOutcome.skipped);
    purchase.complete(true);
    await purchasing;

    expect(service.verifyCalls, 0);
  });

  test('D13：🧪 の上書きがあるときは表示を変えず、本当の値だけ更新する', () async {
    // 本当の値は無料。🧪 でプレミアムの表示にする（上書き true）
    provider.togglePremiumStatusForTest();
    expect(provider.isPremiumUser, isTrue);
    service.onVerify = () async => PremiumVerification.premium;

    expect(await provider.refreshPremiumStatus(now: start), PremiumRefreshOutcome.updated);
    expect(provider.isPremiumUser, isTrue);

    // 本当の値はプレミアムになっているので、15 分後にもう一度確かめても unchanged
    expect(
      await provider.refreshPremiumStatus(now: start.add(const Duration(minutes: 15))),
      PremiumRefreshOutcome.unchanged,
    );

    // 🧪 で無料にすると、本当の値（プレミアム）と違うので上書き false になり、表示は無料
    provider.togglePremiumStatusForTest();
    expect(provider.isPremiumUser, isFalse);
  });
}
