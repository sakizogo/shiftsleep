// lib/services/premium_service.dart
// 有料版（プレミアム）の RevenueCat と DB の窓口
//
// 責務:
// - RevenueCat との連携（ユーザーの購読情報を確認）
// - DB に有料版ステータスを保存・読み込み（is_premium_user の列だけを書く。1a）
// - 例外処理（ネットワークエラーなど）
//
// プレミアムの値は SleepProvider に集める（D1 A）。ここでは読み口を持たない
//
// Week 7 Phase 3: 新規作成

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/services/premium_purchase.dart';

class PremiumService {
  // ========== シングルトンパターン ==========
  static final PremiumService _instance = PremiumService._internal(ShiftRepository());

  factory PremiumService() {
    return _instance;
  }

  PremiumService._internal(this._shiftRepository);

  /// 1b：テスト用。ShiftRepository を差し替えた別のインスタンスを作る（シングルトンの値には触らない）
  @visibleForTesting
  PremiumService.withRepository(ShiftRepository repository) : this._internal(repository);
  // ==========================================

  /// RevenueCat ダッシュボードで設定した entitlement の ID
  static const String _entitlementId = 'ShiftSleep Pro';

  /// 最後に確かめた値（RevenueCat の確認に失敗したときに返す）
  bool _isPremiumUser = false;

  /// 2b E21 A：この起動中に RevenueCat で確かめた値（確認・購入・復元。まだなければ null）
  /// loadPremiumStatusFromDatabase は、これがあれば DB の値より優先する
  bool? _verifiedPremium;

  final ShiftRepository _shiftRepository;

  // ========================
  // メイン機能
  // ========================

  /// N26：RevenueCat が configure 済みか
  ///
  /// キーが空で configure していないとき、configure に失敗したとき、確認自体に失敗したときは false。
  Future<bool> isRevenueCatConfigured() async {
    try {
      return await Purchases.isConfigured;
    } catch (e) {
      debugPrint('[PremiumService] ⚠️ RevenueCat の configure 状態を確認できません: $e');
      return false;
    }
  }

  /// N26：configure していないときは無料版として扱う（DB の値は書き換えない）
  bool _treatAsFreeUser() {
    _isPremiumUser = false;
    return false;
  }

  /// 【重要】RevenueCat からユーザーの有料版ステータスを確認して DB に保存
  ///
  /// RevenueCat が configure されていないときは、呼ばずに false を返す（N26）
  ///
  /// 処理フロー（2b：verifyPremiumStatus を使う。動きは今までと同じ）:
  /// 1. RevenueCat の CustomerInfo を取得（失敗したら前の値を返す）
  /// 2. entitlements から 'ShiftSleep Pro' が有効かチェック
  /// 3. 結果をキャッシュに入れる
  /// 4. DB に保存（D22 A：失敗しても 2 の結果を返す。失敗は debugPrint だけに出す）
  ///
  /// 返り値: 有料版フラグ（true = 有料ユーザー）
  Future<bool> checkPremiumStatus({String userId = 'test_user'}) async {
    switch (await verifyPremiumStatus(userId: userId)) {
      case PremiumVerification.premium:
        return true;
      case PremiumVerification.free:
        return false;
      case PremiumVerification.notConfigured:
        return _treatAsFreeUser();
      case PremiumVerification.unavailable:
        return _isPremiumUser;
    }
  }

  /// 2b：RevenueCat に確かめる（「確かめられた」と「確かめられなかった」を分けて返す）
  ///
  /// - configure していない → notConfigured（RevenueCat を呼ばず、キャッシュも DB も変えない）
  /// - 確かめられた → premium / free（キャッシュと DB に入れる。D22 A）
  /// - 確かめられなかった（オフラインなど）→ unavailable（キャッシュも DB も変えない）
  Future<PremiumVerification> verifyPremiumStatus({String userId = 'test_user'}) async {
    if (!await isRevenueCatConfigured()) return PremiumVerification.notConfigured;

    final bool hasPremium;
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      hasPremium = hasPremiumEntitlement(customerInfo);
      debugPrint('[PremiumService] ✅ RevenueCat 確認完了: '
          'entitlementId=$_entitlementId, hasEntitlement=$hasPremium, active=${customerInfo.entitlements.active.keys.toList()}');
    } catch (e) {
      debugPrint('[PremiumService] ❌ RevenueCat の確認に失敗（値は変えない）: $e');
      return PremiumVerification.unavailable;
    }

    return await _applyResult(userId, hasPremium) ? PremiumVerification.premium : PremiumVerification.free;
  }

  /// D23 A：entitlement（ShiftSleep Pro）が active か（確認・購入・復元で使う）
  static bool hasPremiumEntitlement(CustomerInfo customerInfo) =>
      customerInfo.entitlements.active.containsKey(_entitlementId);

  /// RevenueCat の結果をキャッシュに入れてから DB に保存する
  /// D22 A：DB に保存できなくても、結果をそのまま返す（失敗は debugPrint だけに出す）
  Future<bool> _applyResult(String userId, bool hasPremium) async {
    _isPremiumUser = hasPremium;
    _verifiedPremium = hasPremium;  // 2b E21 A

    try {
      await updatePremiumStatusToDatabase(userId, hasPremium);
    } catch (e) {
      debugPrint('[PremiumService] ⚠️ DB に保存できませんでした（RevenueCat の結果はそのまま返す）: $e');
    }

    return hasPremium;
  }

  /// N138＋N139 2：D19 A'：offerings.current の月額・年額（ないものは入れない。月額・年額の順）
  /// RevenueCat の例外は外に伝える（判定は呼び出し元）
  Future<List<PremiumPlan>> fetchPremiumPlans() async {
    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) return const [];
    final monthly = current.monthly;
    final annual = current.annual;
    return [
      if (monthly != null) PremiumPlan(PremiumPlanKind.monthly, monthly),
      if (annual != null) PremiumPlan(PremiumPlanKind.annual, annual),
    ];
  }

  /// N138＋N139 2：購入して entitlement を見て、キャッシュと DB に入れる（D23 A・D22 A・E16 A）
  /// RevenueCat の例外（キャンセルなど）は外に伝える（判定は呼び出し元）
  Future<bool> purchase(PremiumPlan plan, {String userId = 'test_user'}) async {
    final result = await Purchases.purchase(PurchaseParams.package(plan.package));
    final hasPremium = hasPremiumEntitlement(result.customerInfo);
    debugPrint('[PremiumService] ✅ 購入完了: plan=${plan.kind.name}, hasEntitlement=$hasPremium');
    return _applyResult(userId, hasPremium);
  }

  /// N138＋N139 2：復元して entitlement を見て、キャッシュと DB に入れる（D22 A）
  /// RevenueCat の例外は外に伝える（判定は呼び出し元）
  Future<bool> restore({String userId = 'test_user'}) async {
    final customerInfo = await Purchases.restorePurchases();
    final hasPremium = hasPremiumEntitlement(customerInfo);
    debugPrint('[PremiumService] ✅ 復元完了: hasEntitlement=$hasPremium');
    return _applyResult(userId, hasPremium);
  }

  /// DB に有料版ステータスを保存
  ///
  /// 1b：is_premium_user の列だけを書く（行がなければ既定の行を作る。ShiftRepository.updateIsPremiumUser）
  /// 失敗は呼び出し元に上げる
  Future<void> updatePremiumStatusToDatabase(
    String userId,
    bool isPremium,
  ) async {
    await _shiftRepository.updateIsPremiumUser(userId, isPremium);
  }

  /// 有料版ステータスを DB から読み込む（アプリ起動時に実行）
  ///
  /// RevenueCat が configure されていないときは、DB の値によらず false を返す（N26）
  /// 2b E21 A：この起動中に RevenueCat で確かめた値があれば、DB より優先する
  /// （DB を読んでいる途中で確かめ終わったときも、読み終わったあとで確かめた値を返す）
  Future<bool> loadPremiumStatusFromDatabase(String userId) async {
    if (!await isRevenueCatConfigured()) return _treatAsFreeUser();
    final verifiedBefore = _verifiedPremium;
    if (verifiedBefore != null) return _isPremiumUser = verifiedBefore;

    try {
      final settings = await _shiftRepository.getAppSettings(userId);

      final verifiedAfter = _verifiedPremium;
      if (verifiedAfter != null) {
        debugPrint('[PremiumService] ℹ️ DB を読む途中で RevenueCat で確かめたので、確かめた値を使う: $verifiedAfter');
        return _isPremiumUser = verifiedAfter;
      }

      if (settings == null) {
        debugPrint('[PremiumService] ⚠️ AppSettings が見つかりません（無料版として扱う）');
        _isPremiumUser = false;
        return false;
      }

      _isPremiumUser = settings.isPremiumUser;
      debugPrint('[PremiumService] ✅ DB 読み込み完了: isPremium=$_isPremiumUser');

      return _isPremiumUser;
    } catch (e) {
      debugPrint('[PremiumService] ❌ DB 読み込みエラー: $e');
      return _verifiedPremium ?? _isPremiumUser;
    }
  }
}
