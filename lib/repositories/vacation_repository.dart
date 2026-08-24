import 'package:sqflite/sqflite.dart';
import 'package:shiftsleep/database/database_helper.dart';
import 'package:shiftsleep/models/vacation_model.dart';

class VacationRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// ========== 有給設定管理 ==========

  /// 有給設定を取得（存在しなければ null）
  Future<VacationSettings?> getVacationSettings(String userId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'vacation_settings',
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    if (result.isEmpty) return null;
    return VacationSettings.fromMap(result.first);
  }

  /// 有給設定を保存（入社日と付与日数を記録）
  Future<void> saveVacationSettings(
    String userId,
    DateTime hiredDate,
    int annualDays,
  ) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();

    final settings = VacationSettings(
      userId: userId,
      hiredDate: hiredDate,
      annualDays: annualDays,
      manualOverride: false,
      lastCalculationDate: now,
      createdAt: now,
      updatedAt: now,
    );

    await db.insert(
      'vacation_settings',
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    print('✅ VacationSettings saved: userId=$userId, annualDays=$annualDays');
  }

  /// 有給日数を手入力で更新
  Future<void> updateAnnualDays(String userId, int newAnnualDays) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();

    await db.update(
      'vacation_settings',
      {
        'annual_days': newAnnualDays,
        'manual_override': 1,  // 手入力フラグをON
        'updated_at': now.toIso8601String(),
      },
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    print('✅ AnnualDays updated: userId=$userId, newAnnualDays=$newAnnualDays');
  }

  /// 自動計算で有給日数を更新（毎年4月1日など）
  Future<void> recalculateAnnualDays(String userId) async {
    final db = await _dbHelper.database;
    final settings = await getVacationSettings(userId);

    if (settings == null) {
      print('⚠️ VacationSettings not found for userId=$userId');
      return;
    }

    final newAnnualDays = VacationSettings.calculateAnnualDays(settings.hiredDate);
    final now = DateTime.now();

    await db.update(
      'vacation_settings',
      {
        'annual_days': newAnnualDays,
        'manual_override': 0,  // 手入力フラグをOFF
        'last_calculation_date': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    print('✅ AnnualDays recalculated: userId=$userId, newAnnualDays=$newAnnualDays');
  }

  /// ========== 有給付与管理（新規：Week 12） ==========

  /// 有給付与を記録
  Future<void> recordVacationAccrual(
    String userId,
    DateTime accrualDate,
    int daysGranted, {
    String? notes,
  }) async {
    final db = await _dbHelper.database;

    final accrual = VacationAccrual.create(
      userId: userId,
      accrualDate: accrualDate,
      daysGranted: daysGranted,
      notes: notes,
    );

    await db.insert(
      'vacation_accruals',
      accrual.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    print('✅ VacationAccrual recorded: userId=$userId, daysGranted=$daysGranted, accrualDate=${accrualDate.toIso8601String()}');
  }

  /// ユーザーの有給付与履歴を全て取得
  Future<List<VacationAccrual>> getVacationAccrualsByUser(String userId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'vacation_accruals',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'accrual_date DESC',
    );

    return result.map((map) => VacationAccrual.fromMap(map)).toList();
  }

  /// 指定期間内の有給付与を取得
  Future<List<VacationAccrual>> getVacationAccrualsInRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'vacation_accruals',
      where: 'user_id = ? AND accrual_date BETWEEN ? AND ?',
      whereArgs: [
        userId,
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'accrual_date DESC',
    );

    return result.map((map) => VacationAccrual.fromMap(map)).toList();
  }

  /// 🌟 失効予定の付与（残り30日以内）を取得
  Future<List<VacationAccrual>> getExpiringAccruals(
    String userId, {
    int daysThreshold = 30,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final thirtyDaysLater = now.add(Duration(days: daysThreshold));

    final result = await db.query(
      'vacation_accruals',
      where: 'user_id = ? AND expiry_date BETWEEN ? AND ?',
      whereArgs: [
        userId,
        now.toIso8601String(),
        thirtyDaysLater.toIso8601String(),
      ],
      orderBy: 'expiry_date ASC',
    );

    return result.map((map) => VacationAccrual.fromMap(map)).toList();
  }

  /// ========== 有給使用管理 ==========

  /// 有給使用を記録
  Future<void> recordVacationUsage(
    String userId,
    DateTime usageDate,
    double daysUsed,
    String? reason,
  ) async {
    final db = await _dbHelper.database;

    final usage = VacationUsage.create(
      userId: userId,
      usageDate: usageDate,
      daysUsed: daysUsed,
      reason: reason,
    );

    await db.insert(
      'vacation_usage',
      usage.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    print('✅ VacationUsage recorded: userId=$userId, daysUsed=$daysUsed');
  }

  /// 指定期間の有給使用履歴を取得
  Future<List<VacationUsage>> getVacationUsageInRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'vacation_usage',
      where: 'user_id = ? AND usage_date BETWEEN ? AND ?',
      whereArgs: [
        userId,
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'usage_date DESC',
    );

    return result.map((map) => VacationUsage.fromMap(map)).toList();
  }

  /// 今年の使用日数合計を計算
  Future<double> getTotalDaysUsedThisYear(String userId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final endOfYear = DateTime(now.year, 12, 31);

    final result = await db.rawQuery(
      'SELECT SUM(days_used) as total FROM vacation_usage WHERE user_id = ? AND usage_date BETWEEN ? AND ?',
      [
        userId,
        startOfYear.toIso8601String(),
        endOfYear.toIso8601String(),
      ],
    );

    if (result.isEmpty || result.first['total'] == null) {
      return 0.0;
    }

    return (result.first['total'] as num).toDouble();
  }

  /// 今年の残日数を計算（後方互換性のため）
  Future<double> getRemainingDaysThisYear(String userId) async {
    final settings = await getVacationSettings(userId);
    if (settings == null) return 0.0;

    final usedDays = await getTotalDaysUsedThisYear(userId);
    return (settings.annualDays - usedDays).toDouble();
  }

  /// 使用履歴を削除
  Future<void> deleteVacationUsage(String usageId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'vacation_usage',
      where: 'id = ?',
      whereArgs: [usageId],
    );

    print('✅ VacationUsage deleted: usageId=$usageId');
  }
  
    /// 指定した日付の有給使用を削除（カレンダーからキャンセルした時など）
  /// ========== Week 14 追加 ==========
  Future<void> deleteVacationUsageByDate(String userId, DateTime usageDate) async {
    final db = await _dbHelper.database;
    final dateString = usageDate.toIso8601String().split('T')[0];

    await db.delete(
      'vacation_usage',
      where: 'user_id = ? AND usage_date = ?',
      whereArgs: [userId, dateString],
    );

    print('[VacationRepository] ✅ 有給使用を削除: $userId の${usageDate.month}月${usageDate.day}日分');
  }
  // ====================================================================

  /// ========== 🌟 メイン計算ロジック ==========

  /// 🌟 現在の残日数を計算（全付与期間を考慮）
  /// 
  /// 計算ロジック：
  /// 1. ユーザーの全付与を取得
  /// 2. 各付与ごとに：
  ///    - 失効日を過ぎていたらスキップ
  ///    - 有効な付与については、その期間内の使用日数を集計
  ///    - 付与日数 - 使用日数 = その付与の残日数
  /// 3. 全付与の残日数を合計
  Future<double> calculateRemainingDays(String userId) async {
    final accruals = await getVacationAccrualsByUser(userId);
    
    if (accruals.isEmpty) {
      print('⚠️ No vacation accruals found for userId=$userId');
      return 0.0;
    }

    double totalRemaining = 0.0;
    final now = DateTime.now();

    for (final accrual in accruals) {
      // 失効日を過ぎた付与はスキップ
      if (now.isAfter(accrual.expiryDate)) {
        print('⏰ Accrual expired: accrual_date=${accrual.accrualDate.toIso8601String()}, expiry_date=${accrual.expiryDate.toIso8601String()}');
        continue;
      }

      // この付与期間内の使用日数を計算
      // 注：付与日から失効日までの期間を対象
      final usageInPeriod = await _getTotalDaysUsedInRange(
        userId,
        accrual.accrualDate,
        accrual.expiryDate,
      );

      // この付与の残日数
      final remainingForThisAccrual = accrual.daysGranted - usageInPeriod;
      totalRemaining += remainingForThisAccrual;

      print('📊 Accrual: date=${accrual.accrualDate.toIso8601String()}, granted=${accrual.daysGranted}, used=$usageInPeriod, remaining=$remainingForThisAccrual');
    }

    print('✅ Total remaining days: $totalRemaining');
    return totalRemaining;
  }

  /// 指定期間内の使用日数を計算（ヘルパー）
  Future<double> _getTotalDaysUsedInRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT SUM(days_used) as total FROM vacation_usage WHERE user_id = ? AND usage_date BETWEEN ? AND ?',
      [
        userId,
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
    );

    if (result.isEmpty || result.first['total'] == null) {
      return 0.0;
    }

    return (result.first['total'] as num).toDouble();
  }

  /// 付与サマリーを取得（UI表示用）
  Future<VacationSummary?> getAccrualSummary(String userId) async {
    final accruals = await getVacationAccrualsByUser(userId);
    if (accruals.isEmpty) return null;

    final totalGranted = accruals.fold<int>(
      0,
      (sum, accrual) => sum + accrual.daysGranted,
    );

    final remaining = await calculateRemainingDays(userId);
    final expiringAccruals = await getExpiringAccruals(userId);

    return VacationSummary(
      totalGranted: totalGranted,
      totalUsed: totalGranted - remaining,
      totalRemaining: remaining,
      expiringCount: expiringAccruals.length,
      nextExpiryDate: expiringAccruals.isNotEmpty
          ? expiringAccruals.first.expiryDate
          : null,
    );
  }

  // ========== Week 13 追加: 持ち越し有休関連のヘルパーメソッド ==========
  /// 昨年度の持ち越し有休数を取得
  /// 
  /// 2024年度分の有休が2025年度に持ち越されている場合の日数を返す
  /// 持ち越し有休数を app_settings から取得
  Future<double?> getCarriedOverDays(String userId) async {
    try {
      final db = await _dbHelper.database;
      
      // ========== Week 13修正: app_settings から直接取得（vacation_accruals ではない） ==========
      final results = await db.query(
        'app_settings',  // ← 正しいテーブル
        columns: ['carried_over_days'],
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      
      if (results.isEmpty) {
        print('⚠️ getCarriedOverDays: app_settings レコードなし (userId=$userId)');
        return 0.0;
      }
      
      final carriedOverDays = results.first['carried_over_days'] as int? ?? 0;
      print('✅ getCarriedOverDays: $carriedOverDays日 取得成功 (userId=$userId)');
      return carriedOverDays.toDouble();
      // ===============================================================================
    } catch (e) {
      print('❌ Error getting carried over days: $e');
      return null;
    }
  }

  /// 今年度に消滅予定の日数を計算
  /// 
  /// 昨年度から持ち越された有休で、今年度中に失効する分の日数
  Future<double?> getDaysExpiringThisYear(String userId) async {
    try {
      final db = await _dbHelper.database;
      final currentYear = DateTime.now().year;
      
      // 昨年度から持ち越された、失効日が今年度のデータを取得
      final results = await db.query(
        'vacation_accruals',
        where: 'user_id = ? AND is_carried_over = 1 AND strftime("%Y", expiry_date) = ?',
        whereArgs: [userId, currentYear.toString()],
      );
      
      if (results.isEmpty) return 0.0;
      
      // 失効予定の日数を計算
      double totalExpiring = 0.0;
      for (final record in results) {
        totalExpiring += (record['days_granted'] as int).toDouble();
      }
      
      return totalExpiring;
    } catch (e) {
      print('❌ Error getting days expiring this year: $e');
      return null;
    }
  }

  /// 今年度の消滅予定日を取得
  /// 
  /// 最も早い失効日を返す
  Future<DateTime?> getExpirationDate(String userId) async {
    try {
      final db = await _dbHelper.database;
      final currentYear = DateTime.now().year;
      
      // 昨年度から持ち越された、失効日が今年度の最も早い失効日を取得
      final results = await db.query(
        'vacation_accruals',
        where: 'user_id = ? AND is_carried_over = 1 AND strftime("%Y", expiry_date) = ?',
        whereArgs: [userId, currentYear.toString()],
        orderBy: 'expiry_date ASC',
        limit: 1,
      );
      
      if (results.isEmpty) return null;
      
      final expiryDateStr = results.first['expiry_date'] as String?;
      if (expiryDateStr == null) return null;
      
      return DateTime.parse(expiryDateStr);
    } catch (e) {
      print('❌ Error getting expiration date: $e');
      return null;
    }
  }
    // ========== Week 13追加: 持ち越し有休数を保存 ==========
  /// 持ち越し有休数を app_settings に保存
  // ========== Week 13追加: 持ち越し有休数を保存 ==========
  /// 持ち越し有休数を app_settings に保存
  /// 重要：app_settings にレコードがない場合は INSERT、ある場合は UPDATE を行う
  // ========== Week 13追加: 持ち越し有休数を保存 ==========
  /// 持ち越し有休数を app_settings に保存
  /// 重要：app_settings にレコードがない場合は INSERT、ある場合は UPDATE を行う
  Future<void> saveCarriedOverDays(String userId, int carriedOverDays) async {
    try {
      final db = await _dbHelper.database;
      
      // app_settings のレコード存在確認
      final results = await db.query(
        'app_settings',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      
      if (results.isEmpty) {
        // ========== レコードがない場合は INSERT（デフォルト値を含める） ==========
        await db.insert(
          'app_settings',
          {
            'user_id': userId,
            'alarm_time_before_shift': 30,  // デフォルト値
            'wake_up_time': '07:00',  // デフォルト値
            'selected_alarm_sound': 'default',  // デフォルト値
            'advice_promo_visible': 1,  // デフォルト値
            'is_premium_user': 0,  // デフォルト値
            'carried_over_days': carriedOverDays,  // ← Week 13 追加
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        print('✅ app_settings を新規作成（持ち越し有休: $carriedOverDays日）');
      } else {
        // ========== レコードがある場合は UPDATE ==========
        await db.update(
          'app_settings',
          {
            'carried_over_days': carriedOverDays,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'user_id = ?',
          whereArgs: [userId],
        );
        print('✅ 持ち越し有休数を更新: $carriedOverDays日');
      }
    } catch (e) {
      print('❌ Error saving carried over days: $e');
    }
  }
  // ===============================================================================
}

/// 付与サマリー（UI表示用）
class VacationSummary {
  final int totalGranted;        // 累計付与日数
  final double totalUsed;        // 累計使用日数
  final double totalRemaining;   // 累計残日数
  final int expiringCount;       // 失効予定数
  final DateTime? nextExpiryDate; // 次の失効日

  VacationSummary({
    required this.totalGranted,
    required this.totalUsed,
    required this.totalRemaining,
    required this.expiringCount,
    this.nextExpiryDate,
  });

  /// 失効予定がないか判定
  bool get hasNoExpiring => expiringCount == 0;

  /// 失効予定がある場合、警告メッセージを生成
  String? get expiryWarningMessage {
    if (nextExpiryDate == null) return null;

    final accrual = nextExpiryDate!;
    final days = accrual.difference(DateTime.now()).inDays;

    if (days <= 0) {
      return '⚠️ 有給が本日失効しました！';
    } else if (days <= 30) {
      final monthStr = '${accrual.month}月${accrual.day}日';
      return '⚠️ $monthStr までに使わないと有給が消滅してしまいます。計画的に使いましょう！';
    }

    return null;
  }
}