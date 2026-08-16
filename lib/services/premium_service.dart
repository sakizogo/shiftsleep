/// lib/services/premium_service.dart
/// 有料版（プレミアム）機能管理サービス
/// 
/// 責務:
/// - RevenueCat との連携（ユーザーの購読情報を確認）
/// - DB に有料版ステータスを保存・読み込み
/// - メモリキャッシュで効率化
/// - 例外処理（ネットワークエラーなど）
///
/// Week 7 Phase 3: 新規作成

import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';

class PremiumService {
  // ========== シングルトンパターン ==========
  static final PremiumService _instance = PremiumService._internal();

  factory PremiumService() {
    return _instance;
  }

  PremiumService._internal();
  // ==========================================

  // メモリキャッシュ
  bool _isPremiumUser = false;
  String? _entitlementId = 'ShiftSleep Pro';  // ← RevenueCat ダッシュボードで設定
  DateTime? _lastCheckTime;

  final ShiftRepository _shiftRepository = ShiftRepository();

  // ========================
  // Getter
  // ========================

  /// メモリキャッシュから現在の有料版ステータスを取得
  bool get isPremiumUser => _isPremiumUser;

  /// 最後にチェックした時刻（null の場合はまだチェックしていない）
  DateTime? get lastCheckTime => _lastCheckTime;

  // ========================
  // メイン機能
  // ========================

  /// 【重要】RevenueCat からユーザーの有料版ステータスを確認して DB に保存
  /// 
  /// 処理フロー:
  /// 1. RevenueCat の CustomerInfo を取得
  /// 2. entitlements から 'ShiftSleep Pro' が有効かチェック
  /// 3. 結果を DB に保存
  /// 4. メモリキャッシュを更新
  /// 
  /// 返り値: 有料版フラグ（true = 有料ユーザー）
  Future<bool> checkPremiumStatus({String userId = 'test_user'}) async {
    try {
      print('[PremiumService] 🔍 有料版ステータスをチェック中...');

      // 1️⃣ RevenueCat から CustomerInfo を取得
      final customerInfo = await Purchases.getCustomerInfo();

      // 2️⃣ entitlements から 'ShiftSleep Pro' を確認
      final entitlements = customerInfo.entitlements.active;
      final hasPremium = entitlements.containsKey(_entitlementId);

      print('[PremiumService] ✅ RevenueCat 確認完了');
      print('   - entitlementId: $_entitlementId');
      print('   - hasEntitlement: $hasPremium');
      print('   - activeEntitlements: ${entitlements.keys.toList()}');

      // 3️⃣ 結果を DB に保存
      await updatePremiumStatusToDatabase(userId, hasPremium);

      // 4️⃣ メモリキャッシュを更新
      _isPremiumUser = hasPremium;
      _lastCheckTime = DateTime.now();

      return hasPremium;
    } catch (e) {
      print('[PremiumService] ❌ RevenueCat エラー: $e');

      // ネットワークエラーなどの場合は、既存のメモリキャッシュを返す
      return _isPremiumUser;
    }
  }

  /// DB に有料版ステータスを保存
  /// 
  /// 処理:
  /// 1. AppSettings を DB から取得
  /// 2. isPremiumUser を更新
  /// 3. DB に保存
  Future<void> updatePremiumStatusToDatabase(
    String userId,
    bool isPremium,
  ) async {
    try {
      print('[PremiumService] 💾 DB に有料版ステータスを保存中... (isPremium=$isPremium)');

      // 1️⃣ 現在の AppSettings を取得
      final settings = await _shiftRepository.getAppSettings(userId);

      if (settings == null) {
        print('[PremiumService] ⚠️  AppSettings が見つかりません（新規作成します）');
        return;
      }

      // 2️⃣ isPremiumUser を更新
      final updatedSettings = settings.copyWith(isPremiumUser: isPremium);

      // 3️⃣ DB に保存 (updateAppSettings → createOrUpdateAppSettings に修正)
      await _shiftRepository.createOrUpdateAppSettings(updatedSettings);

      print('[PremiumService] ✅ DB 保存完了');
    } catch (e) {
      print('[PremiumService] ❌ DB 保存エラー: $e');
      rethrow;
    }
  }

  /// 有料版ステータスを DB から読み込む（アプリ起動時に実行）
  Future<bool> loadPremiumStatusFromDatabase(String userId) async {
    try {
      print('[PremiumService] 📖 DB から有料版ステータスを読み込み中...');

      final settings = await _shiftRepository.getAppSettings(userId);

      if (settings == null) {
        print('[PremiumService] ⚠️  AppSettings が見つかりません');
        _isPremiumUser = false;
        return false;
      }

      _isPremiumUser = settings.isPremiumUser;
      _lastCheckTime = DateTime.now();

      print('[PremiumService] ✅ DB 読み込み完了: isPremium=$_isPremiumUser');

      return _isPremiumUser;
    } catch (e) {
      print('[PremiumService] ❌ DB 読み込みエラー: $e');
      return _isPremiumUser;
    }
  }

  /// 有料版ステータスをリセット（テスト用）
  void resetCache() {
    _isPremiumUser = false;
    _lastCheckTime = null;
    print('[PremiumService] 🔄 キャッシュをリセット');
  }

  // ========================
  // ユーティリティ
  // ========================

  /// 最後のチェックからの経過時間（分）
  int? get minutesSinceLastCheck {
    if (_lastCheckTime == null) return null;

    final now = DateTime.now();
    final diff = now.difference(_lastCheckTime!);

    return diff.inMinutes;
  }

  /// キャッシュが古いかチェック（5分以上経過していたら true）
  bool get isCacheStale {
    final minutes = minutesSinceLastCheck;
    if (minutes == null) return true;  // 一度もチェックしていない場合は古い

    return minutes >= 5;
  }

  @override
  String toString() => '''
PremiumService(
  isPremiumUser: $_isPremiumUser,
  lastCheckTime: $_lastCheckTime,
  minutesSinceLastCheck: $minutesSinceLastCheck
)
''';
}