// N213：SleepProvider の審査用コードでの解放（D43 A：基準 = 本当の値 || 審査用、画面の値 = 🧪 の上書き ?? 基準）
//
// PremiumService を偽のものに差し替え、審査用の解放が RevenueCat・DB・購入・復元に触れないことも確かめる
// コードは dart-define に頼らず、reviewCode で渡す
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/premium_purchase.dart';
import 'package:shiftsleep/services/premium_service.dart';
import 'package:shiftsleep/services/review_unlock.dart';

const _code = 'TEST-CODE-1A';

class _NoRepository extends SleepRepository {
  @override
  Future<SleepRecord?> getLatestSleepRecord(String userId) async => null;

  @override
  Future<List<SleepRecord>> getSleepRecordsByDateRange(String userId, DateTime startDate, DateTime endDate) async =>
      const [];
}

/// RevenueCat と DB を呼ばない偽の PremiumService（呼ばれた回数を数える）
class _FakePremiumService extends PremiumService {
  _FakePremiumService() : super.withRepository(ShiftRepository());

  /// DB に入っている値（loadAllSleepData が読む）
  bool databasePremium = false;
  bool databaseThrows = false;
  PremiumVerification verification = PremiumVerification.free;
  int purchaseCalls = 0;
  int restoreCalls = 0;
  int verifyCalls = 0;
  int databaseWrites = 0;

  @override
  Future<bool> isRevenueCatConfigured() async => true;

  @override
  Future<bool> loadPremiumStatusFromDatabase(String userId) async {
    if (databaseThrows) throw Exception('DB を読めない');
    return databasePremium;
  }

  @override
  Future<void> updatePremiumStatusToDatabase(String userId, bool isPremium) async => databaseWrites++;

  @override
  Future<PremiumVerification> verifyPremiumStatus({String userId = 'test_user'}) async {
    verifyCalls++;
    return verification;
  }

  @override
  Future<bool> purchase(PremiumPlan plan, {String userId = 'test_user'}) async {
    purchaseCalls++;
    return true;
  }

  @override
  Future<bool> restore({String userId = 'test_user'}) async {
    restoreCalls++;
    return true;
  }
}

/// 保存・解除に失敗する store（読むと false）
class _FailingStore extends ReviewUnlockStore {
  const _FailingStore();

  @override
  Future<bool> load() async => false;

  @override
  Future<bool> save() async => false;

  @override
  Future<bool> clear() async => false;
}

void main() {
  late _FakePremiumService service;

  SleepProvider createProvider({ReviewUnlockStore? store}) =>
      SleepProvider(_NoRepository(), premiumService: service, reviewUnlockStore: store, reviewCode: _code);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _FakePremiumService();
  });

  test('正しいコードで unlocked になり、プレミアムの表示になる。RevenueCat・DB・購入・復元には触れない', () async {
    final provider = createProvider();
    await provider.loadAllSleepData();
    var notified = 0;
    provider.addListener(() => notified++);

    expect(await provider.unlockWithReviewCode(' test-code-1a '), ReviewUnlockOutcome.unlocked);

    expect(provider.isPremiumUser, isTrue);
    expect(provider.isReviewUnlockOnly, isTrue);
    expect(notified, 1);
    expect((await SharedPreferences.getInstance()).getBool(reviewUnlockedKey), isTrue);
    expect(service.purchaseCalls, 0);
    expect(service.restoreCalls, 0);
    expect(service.verifyCalls, 0);
    expect(service.databaseWrites, 0);
  });

  test('違うコードなら wrongCode で、何も変えない（知らせない・保存しない）', () async {
    final provider = createProvider();
    await provider.loadAllSleepData();
    var notified = 0;
    provider.addListener(() => notified++);

    expect(await provider.unlockWithReviewCode('TEST-CODE-1B'), ReviewUnlockOutcome.wrongCode);

    expect(provider.isPremiumUser, isFalse);
    expect(provider.isReviewUnlockOnly, isFalse);
    expect(notified, 0);
    expect((await SharedPreferences.getInstance()).containsKey(reviewUnlockedKey), isFalse);
  });

  test('D45 B：コードが空（付け忘れ）の provider では、どんな入力でも解放しない', () async {
    final provider = SleepProvider(_NoRepository(), premiumService: service, reviewCode: '');

    expect(await provider.unlockWithReviewCode(''), ReviewUnlockOutcome.wrongCode);
    expect(await provider.unlockWithReviewCode(_code), ReviewUnlockOutcome.wrongCode);
    expect(provider.isPremiumUser, isFalse);
  });

  test('作り直しても（再起動）、最初の loadAllSleepData で解放が続く。DB が例外でも効く（E38）', () async {
    await createProvider().unlockWithReviewCode(_code);
    service.databaseThrows = true;

    final restarted = createProvider();
    expect(restarted.isPremiumUser, isFalse);
    await restarted.loadAllSleepData();

    expect(restarted.isPremiumUser, isTrue);
    expect(restarted.isReviewUnlockOnly, isTrue);
  });

  test('2b：RevenueCat が free でも、解放中はプレミアムのまま（unchanged の判定は本当の値と比べる）', () async {
    service.databasePremium = true;
    final provider = createProvider();
    await provider.loadAllSleepData();
    await provider.unlockWithReviewCode(_code);
    expect(provider.isReviewUnlockOnly, isFalse);  // 本当に購入しているので、審査用だけではない

    service.verification = PremiumVerification.free;
    expect(await provider.refreshPremiumStatus(now: DateTime(2026, 11, 22, 8)), PremiumRefreshOutcome.updated);

    expect(provider.isPremiumUser, isTrue);
    expect(provider.isReviewUnlockOnly, isTrue);
  });

  test('🧪：解放中に押すと無料の表示（上書き）、もう一度押すと基準（解放中）に戻って上書きが外れる', () async {
    final provider = createProvider();
    await provider.loadAllSleepData();
    await provider.unlockWithReviewCode(_code);

    provider.togglePremiumStatusForTest();
    expect(provider.isPremiumUser, isFalse);
    provider.setPremiumStatus(false);
    expect(provider.isPremiumUser, isFalse);  // 上書きを保つ

    provider.togglePremiumStatusForTest();
    expect(provider.isPremiumUser, isTrue);
    await provider.clearReviewUnlock();
    expect(provider.isPremiumUser, isFalse);  // 上書きが外れているので、基準（無料）に従う
  });

  test('解除すると本当の値に戻り、保存も消える。作り直しても無料のまま', () async {
    final provider = createProvider();
    await provider.loadAllSleepData();
    await provider.unlockWithReviewCode(_code);
    var notified = 0;
    provider.addListener(() => notified++);

    expect(await provider.clearReviewUnlock(), isTrue);

    expect(provider.isPremiumUser, isFalse);
    expect(provider.isReviewUnlockOnly, isFalse);
    expect(notified, 1);
    final restarted = createProvider();
    await restarted.loadAllSleepData();
    expect(restarted.isPremiumUser, isFalse);
  });

  test('本当に購入していれば、解除してもプレミアムのまま', () async {
    service.databasePremium = true;
    final provider = createProvider();
    await provider.loadAllSleepData();
    await provider.unlockWithReviewCode(_code);

    await provider.clearReviewUnlock();

    expect(provider.isPremiumUser, isTrue);
    expect(provider.isReviewUnlockOnly, isFalse);
  });

  test('D50 A：保存に失敗したら unlockedThisSessionOnly で、この起動中だけ解放（読み込みのあとも保つ）', () async {
    final provider = createProvider(store: const _FailingStore());

    expect(await provider.unlockWithReviewCode(_code), ReviewUnlockOutcome.unlockedThisSessionOnly);
    expect(provider.isPremiumUser, isTrue);

    // 解放のあとの最初の loadAllSleepData（保存は読めず false）でも、解放のまま
    await provider.loadAllSleepData();
    expect(provider.isPremiumUser, isTrue);
    expect(provider.isReviewUnlockOnly, isTrue);
  });

  test('解除で保存を消せなくても、この起動中は解除して false を返す', () async {
    final provider = createProvider(store: const _FailingStore());
    await provider.unlockWithReviewCode(_code);

    expect(await provider.clearReviewUnlock(), isFalse);

    expect(provider.isPremiumUser, isFalse);
    expect(provider.isReviewUnlockOnly, isFalse);
  });
}
