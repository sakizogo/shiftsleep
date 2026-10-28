import 'package:flutter/foundation.dart';
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
    double daysGranted, {
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

    // N64：保存する日はローカルの 0 時にそろえる（カレンダーの日は UTC の 0 時で来ることがあるため）
    // 年・月・日の数字をそのまま使う（toLocal() は通さない）
    final normalizedDate = DateTime(usageDate.year, usageDate.month, usageDate.day);

    final usage = VacationUsage.create(
      userId: userId,
      usageDate: normalizedDate,
      daysUsed: daysUsed,
      reason: reason,
    );

    // N68：同じ日の行が増え続けないように、その日の既存行を消してから入れる
    // 条件は deleteVacationUsageByDate と同じ（その日の 'YYYY-MM-DD' 以上、翌日の 'YYYY-MM-DD' 未満。Z ありの行にも当たる）
    final nextDay = DateTime(usageDate.year, usageDate.month, usageDate.day + 1);
    final dateString = normalizedDate.toIso8601String().split('T')[0];
    final nextDateString = nextDay.toIso8601String().split('T')[0];

    await db.transaction((txn) async {
      final deletedCount = await txn.delete(
        'vacation_usage',
        where: 'user_id = ? AND usage_date >= ? AND usage_date < ?',
        whereArgs: [userId, dateString, nextDateString],
      );
      debugPrint('🗑️ N68: 同じ日の既存行を $deletedCount 件削除');

      await txn.insert(
        'vacation_usage',
        usage.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

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

  /// ========== 今年の使用日数合計を計算 ==========
  /// ✅ 【修正版：ステップ1～3のデバッグログ付き】
  Future<double> getTotalDaysUsedThisYear(String userId) async {
    print('🔍 [DEBUG] getTotalDaysUsedThisYear() 開始');
    print('🔍 [DEBUG] userId=$userId');
    
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final endOfYear = DateTime(now.year, 12, 31);

    print('📅 [DEBUG] 検索範囲: ${startOfYear.toIso8601String()} ～ ${endOfYear.toIso8601String()}');

    // ========== ステップ1：全件データを確認 ==========
    print('🔍 [DEBUG] ステップ1：vacation_usage テーブル全件表示');
    final allUsage = await db.query('vacation_usage');
    print('📊 [DEBUG] vacation_usage 全件数: ${allUsage.length}件');
    for (final row in allUsage) {
      print('📊 [DEBUG]   - user_id=${row['user_id']}, usage_date=${row['usage_date']}, days_used=${row['days_used']}');
    }

    // ========== ステップ2：WHERE 条件で抽出 ==========
    print('🔍 [DEBUG] ステップ2：WHERE 条件で抽出（userId=$userId で絞り込み）');
    final filteredUsage = await db.query(
      'vacation_usage',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    print('📊 [DEBUG] user_id=$userId の件数: ${filteredUsage.length}件');
    for (final row in filteredUsage) {
      print('📊 [DEBUG]   - usage_date=${row['usage_date']}, days_used=${row['days_used']}');
    }

    // ========== ステップ3：SUM でデータベース集計 ==========
    print('🔍 [DEBUG] ステップ3：rawQuery で SUM(days_used) を計算');
    final result = await db.rawQuery(
      'SELECT SUM(days_used) as total FROM vacation_usage WHERE user_id = ? AND usage_date BETWEEN ? AND ?',
      [
        userId,
        startOfYear.toIso8601String(),
        endOfYear.toIso8601String(),
      ],
    );

    print('📊 [DEBUG] rawQuery 結果: $result');

    if (result.isEmpty || result.first['total'] == null) {
      print('⚠️  [DEBUG] 使用日数 = 0.0（レコードなしまたは NULL）');
      return 0.0;
    }

    final usedDays = (result.first['total'] as num).toDouble();
    print('✅ [DEBUG] 使用日数 = $usedDays 日');
    
    return usedDays;
  }

  /// ========== 有給残日数を計算（持ち越し対応版）==========
  Future<double> getRemainingDaysThisYear(String userId) async {
    print('🔍 [DEBUG] getRemainingDaysThisYear() 開始 (userId=$userId)');
    
    // ステップ1：今年の付与日数を取得
    final settings = await getVacationSettings(userId);
    if (settings == null) {
      print('⚠️ [DEBUG] VacationSettings not found for userId=$userId');
      return 0.0;
    }
    print('📊 [DEBUG] 今年の付与日数: ${settings.annualDays}日');

    // ステップ2：使用日数を取得
    final usedDays = await getTotalDaysUsedThisYear(userId);
    print('📊 [DEBUG] 使用日数: $usedDays日');

    // ステップ3：持ち越し有休を取得
    final carriedOverDays = await getCarriedOverDays(userId) ?? 0.0;
    print('📊 [DEBUG] 持ち越し有休: $carriedOverDays日');

    // ステップ4：残日数を計算（正しい式）
    // 残日数 = (今年の付与 + 持ち越し) - 使用日数
    final remaining = (settings.annualDays + carriedOverDays - usedDays).toDouble();
    print('📊 [DEBUG] 計算式: (${settings.annualDays} + $carriedOverDays) - $usedDays = $remaining');
    print('✅ getRemainingDaysThisYear() 完了 → remaining=$remaining日');
    
    return remaining;
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
    // N64：保存されている usage_date は時刻つき（…T00:00:00.000 や …T00:00:00.000Z）なので、
    // 「その日の 'YYYY-MM-DD' 以上、翌日の 'YYYY-MM-DD' 未満」で比べる（Z があってもなくても当たる）
    // 年・月・日の数字をそのまま使う（UTC の値も toLocal() は通さない）
    final day = DateTime(usageDate.year, usageDate.month, usageDate.day);
    final nextDay = DateTime(usageDate.year, usageDate.month, usageDate.day + 1);
    final dateString = day.toIso8601String().split('T')[0];
    final nextDateString = nextDay.toIso8601String().split('T')[0];

    final deletedCount = await db.delete(
      'vacation_usage',
      where: 'user_id = ? AND usage_date >= ? AND usage_date < ?',
      whereArgs: [userId, dateString, nextDateString],
    );

    print('[VacationRepository] ✅ 有給使用を削除: $userId の${usageDate.month}月${usageDate.day}日分（$deletedCount 件）');
  }

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

    final totalGranted = accruals.fold<double>(
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
      
      // app_settings から直接取得
      final results = await db.query(
        'app_settings',
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
        // レコードがない場合は INSERT（デフォルト値を含める）
        await db.insert(
          'app_settings',
          {
            'user_id': userId,
            'alarm_time_before_shift': 30,  // デフォルト値
            'wake_up_time': '07:00',  // デフォルト値
            'selected_alarm_sound': 'default',  // デフォルト値
            'advice_promo_visible': 1,  // デフォルト値
            'is_premium_user': 0,  // デフォルト値
            'carried_over_days': carriedOverDays,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        print('✅ app_settings を新規作成（持ち越し有休: $carriedOverDays日）');
      } else {
        // レコードがある場合は UPDATE
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

  // ========== Week 16 追加: 初回付与日管理 ==========
  
  /// 初回付与日を保存（有給設定画面から）
  /// 
  /// 例：初回付与日が2026年10月1日の場合
  /// - 2026年度の付与日：10月1日
  /// - 2027年度の付与日：10月1日（1年後）
  /// - 2028年度の付与日：10月1日（2年後）...
  Future<void> saveFirstAccrualDate(String userId, DateTime firstAccrualDate) async {
    try {
      final db = await _dbHelper.database;
      final now = DateTime.now();
      
      // app_settings のレコード存在確認
      final results = await db.query(
        'app_settings',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      
      if (results.isEmpty) {
        // レコードがない場合は INSERT（デフォルト値を含める）
        await db.insert(
          'app_settings',
          {
            'user_id': userId,
            'alarm_time_before_shift': 30,
            'wake_up_time': '07:00',
            'selected_alarm_sound': 'default',
            'advice_promo_visible': 1,
            'is_premium_user': 0,
            'carried_over_days': 0,
            'first_accrual_date': firstAccrualDate.toIso8601String(),
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        print('✅ 初回付与日を新規作成: ${firstAccrualDate.year}年${firstAccrualDate.month}月${firstAccrualDate.day}日');
      } else {
        // レコードがある場合は UPDATE
        await db.update(
          'app_settings',
          {
            'first_accrual_date': firstAccrualDate.toIso8601String(),
            'updated_at': now.toIso8601String(),
          },
          where: 'user_id = ?',
          whereArgs: [userId],
        );
        print('✅ 初回付与日を更新: ${firstAccrualDate.year}年${firstAccrualDate.month}月${firstAccrualDate.day}日');
      }
    } catch (e) {
      print('❌ Error saving first accrual date: $e');
    }
  }

  /// 初回付与日を読み込み
  Future<DateTime?> getFirstAccrualDate(String userId) async {
    try {
      final db = await _dbHelper.database;
      
      final results = await db.query(
        'app_settings',
        columns: ['first_accrual_date'],
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      
      if (results.isEmpty || results.first['first_accrual_date'] == null) {
        print('⚠️ getFirstAccrualDate: 初回付与日が未登録 (userId=$userId)');
        return null;
      }
      
      final dateStr = results.first['first_accrual_date'] as String;
      final firstAccrualDate = DateTime.parse(dateStr);
      print('✅ getFirstAccrualDate: ${firstAccrualDate.year}年${firstAccrualDate.month}月${firstAccrualDate.day}日');
      return firstAccrualDate;
    } catch (e) {
      print('❌ Error getting first accrual date: $e');
      return null;
    }
  }

  /// ========== Week 16 消滅予定スケジュール ==========
  
  /// 【重要】全ての付与分の消滅予定を一覧表示
  /// 
  /// 戻り値：
  /// [
  ///   {
  ///     'accrualDate': '2026-10-01',  // 付与日
  ///     'daysGranted': 10,             // 付与日数
  ///     'expiryDate': '2027-09-30',   // 消滅日
  ///     'daysRemaining': 8,            // 残日数（使用後）
  ///     'isExpired': false,            // 失効済みか
  ///     'daysUntilExpiry': 35,        // 消滅までの日数
  ///   },
  ///   ...
  /// ]
  Future<List<Map<String, dynamic>>> getExpirationSchedule(String userId) async {
    try {
      final accruals = await getVacationAccrualsByUser(userId);
      if (accruals.isEmpty) {
        print('⚠️ getExpirationSchedule: 付与履歴がありません (userId=$userId)');
        return [];
      }

      List<Map<String, dynamic>> schedule = [];
      final now = DateTime.now();

      for (final accrual in accruals) {
        // この付与期間内の使用日数を計算
        final usageInPeriod = await _getTotalDaysUsedInRange(
          userId,
          accrual.accrualDate,
          accrual.expiryDate,
        );

        final isExpired = now.isAfter(accrual.expiryDate);
        final daysUntilExpiry = accrual.expiryDate.difference(now).inDays;
        final daysRemaining = accrual.daysGranted - usageInPeriod;

        schedule.add({
          'accrualDate': accrual.accrualDate.toIso8601String().split('T')[0],
          'accrualMonth': accrual.accrualDate.month,
          'accrualDay': accrual.accrualDate.day,
          'daysGranted': accrual.daysGranted,
          'expiryDate': accrual.expiryDate.toIso8601String().split('T')[0],
          'expiryMonth': accrual.expiryDate.month,
          'expiryDay': accrual.expiryDate.day,
          'daysRemaining': daysRemaining,
          'daysUsed': usageInPeriod,
          'isExpired': isExpired,
          'daysUntilExpiry': daysUntilExpiry,
        });

        print('📅 [Expiration Schedule] ${accrual.accrualDate.month}月${accrual.accrualDate.day}日付与: ${accrual.daysGranted}日 → ${accrual.expiryDate.month}月${accrual.expiryDate.day}日失効（残${daysRemaining}日）');
      }

      // 消滅日順でソート
      schedule.sort((a, b) {
        final expiryA = DateTime.parse(a['expiryDate'] as String);
        final expiryB = DateTime.parse(b['expiryDate'] as String);
        return expiryA.compareTo(expiryB);
      });

      print('✅ getExpirationSchedule: ${schedule.length}件の付与スケジュール取得');
      return schedule;
    } catch (e) {
      print('❌ Error getting expiration schedule: $e');
      return [];
    }
  }

  /// 近い消滅予定（30日以内）を簡潔にまとめたメッセージを生成
  /// 
  /// 返り値例：
  /// "8月30日までに有休10日が消滅します。\n9月30日までに有休11日が消滅します。"
  Future<String?> getExpirationWarningMessages(String userId) async {
    try {
      final schedule = await getExpirationSchedule(userId);
      if (schedule.isEmpty) return null;

      final now = DateTime.now();
      final messages = <String>[];

      for (final item in schedule) {
        final daysUntilExpiry = item['daysUntilExpiry'] as int;
        
        // 30日以内のみを対象
        if (daysUntilExpiry <= 30 && daysUntilExpiry >= 0) {
          final expiryMonth = item['expiryMonth'] as int;
          final expiryDay = item['expiryDay'] as int;
          final daysRemaining = item['daysRemaining'] as double;
          
          messages.add('${expiryMonth}月${expiryDay}日までに有休${daysRemaining.toStringAsFixed(1)}日が消滅します。');
        }
      }

      if (messages.isEmpty) return null;

      return messages.join('\n');
    } catch (e) {
      print('❌ Error getting expiration warning messages: $e');
      return null;
    }
  }

  /// ========== Week 16 付与日数の自動計算ヘルパー ==========
  
  /// hire_date から、経過年数に応じた付与日数を計算
  /// 
  /// 日本の法定最低付与日数：
  /// - 6ヶ月後（1年目）：10日
  /// - 1年6ヶ月後（2年目）：11日
  /// - 2年6ヶ月後（3年目）：12日
  /// - 3年6ヶ月後（4年目）：14日
  /// - 4年6ヶ月後（5年目）：16日
  /// - 5年6ヶ月後（6年目）：18日
  /// - 6年6ヶ月以降（7年目以降）：20日（MAX）
  static int calculateDaysGranted(DateTime hireDate, DateTime accrualDate) {
    // hire_date から accrual_date までの月数を計算
    final monthsSinceHire = (accrualDate.year - hireDate.year) * 12 +
                           (accrualDate.month - hireDate.month);

    // 付与日数を決定（初回6ヶ月後、以降1年ごと）
    if (monthsSinceHire < 6) {
      return 0;  // 6ヶ月未満は付与対象外
    } else if (monthsSinceHire < 18) {
      return 10;  // 6ヶ月～18ヶ月未満（初回 + 1年以内）
    } else if (monthsSinceHire < 30) {
      return 11;  // 18ヶ月～30ヶ月未満（初回 + 1～2年）
    } else if (monthsSinceHire < 42) {
      return 12;  // 30ヶ月～42ヶ月未満（初回 + 2～3年）
    } else if (monthsSinceHire < 54) {
      return 14;  // 42ヶ月～54ヶ月未満（初回 + 3～4年）
    } else if (monthsSinceHire < 66) {
      return 16;  // 54ヶ月～66ヶ月未満（初回 + 4～5年）
    } else if (monthsSinceHire < 78) {
      return 18;  // 66ヶ月～78ヶ月未満（初回 + 5～6年）
    } else {
      return 20;  // 78ヶ月以上（初回 + 6年以上）
    }
  }

  /// 最初の付与日から yearOffset 年後の付与日を計算する（N61）
  /// 最初の付与日が 2/29 のとき、うるう年でない年は月末（2/28）にそろえる
  static DateTime accrualDateForYear(DateTime firstAccrualDate, int yearOffset) {
    final year = firstAccrualDate.year + yearOffset;
    final lastDayOfMonth = DateTime(year, firstAccrualDate.month + 1, 0).day;
    final day = firstAccrualDate.day > lastDayOfMonth
        ? lastDayOfMonth
        : firstAccrualDate.day;
    return DateTime(year, firstAccrualDate.month, day);
  }

  /// 法定の付与日数（初回、1 年後、2 年後…。7 回目以降は 20 日）（N62・N63）
  static const List<int> _legalDaysByYear = [10, 11, 12, 14, 16, 18, 20];

  /// 最初の付与日から i 回目（0 が初回）の付与日と付与日数（N62・N63 の共通の関数）
  /// 付与日は accrualDateForYear（2/29 → うるう年でない年は 2/28）、日数は i で法定の表を引く
  static ({DateTime date, int days}) accrualForYear(DateTime first, int i) {
    final days = i < _legalDaysByYear.length ? _legalDaysByYear[i] : _legalDaysByYear.last;
    return (date: accrualDateForYear(first, i), days: days);
  }

  /// 最初の付与日から、今日までに来た付与の一覧（古い順）（N61・N62）
  static List<({DateTime date, int days})> accrualsUntilToday(DateTime firstAccrualDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final accruals = <({DateTime date, int days})>[];
    for (int i = 0; i < 100; i++) {  // 万一のための上限
      final accrual = accrualForYear(firstAccrualDate, i);
      if (accrual.date.isAfter(today)) break;
      accruals.add(accrual);
    }
    return accruals;
  }

  /// 最初の付与日から、今日までに来た付与日の一覧（古い順）（N61）
  static List<DateTime> accrualDatesUntilToday(DateTime firstAccrualDate) {
    return accrualsUntilToday(firstAccrualDate).map((a) => a.date).toList();
  }

  /// 最初の付与日から、今日より後の最初の付与日と付与日数（N63）
  static ({DateTime date, int days})? nextAccrualAfterToday(DateTime firstAccrualDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (int i = 0; i < 100; i++) {  // 万一のための上限
      final accrual = accrualForYear(firstAccrualDate, i);
      if (accrual.date.isAfter(today)) return accrual;
    }
    return null;
  }

  /// 次の付与日と付与日数（N63）。初回付与日（app_settings.first_accrual_date）がなければ null
  Future<({DateTime date, int days})?> getNextAccrual(String userId) async {
    final firstAccrualDate = await getFirstAccrualDate(userId);
    if (firstAccrualDate == null) return null;
    return nextAccrualAfterToday(firstAccrualDate);
  }

  /// 処理中の自動生成（userId ごと）。もう一度呼ばれたら同じ Future を返して 1 回にまとめる（N62）
  static final Map<String, Future<int>> _autoGenerateInFlight = {};

  /// DB の入社日（vacation_settings.hired_date）と初回付与日（app_settings.first_accrual_date）から
  /// 今日までの付与を自動生成する（N62）。どちらかがなければ何もしない。作った件数を返す
  Future<int> autoGenerateAccrualsFromSettings(String userId) {
    return _autoGenerateInFlight.putIfAbsent(
      userId,
      () => _autoGenerateAccrualsFromSettings(userId)
          .whenComplete(() => _autoGenerateInFlight.remove(userId)),
    );
  }

  Future<int> _autoGenerateAccrualsFromSettings(String userId) async {
    final settings = await getVacationSettings(userId);
    final firstAccrualDate = await getFirstAccrualDate(userId);
    if (settings == null || firstAccrualDate == null) {
      debugPrint('🗓️ N62: 入社日または初回付与日が未設定のため、自動生成しません');
      return 0;
    }
    final createdCount = await autoGenerateAccruals(userId, settings.hiredDate, firstAccrualDate);
    debugPrint('🗓️ N62: 付与を $createdCount 件自動生成');
    return createdCount;
  }

    /// ========== Week 16 修正版：hire_date と first_accrual_date から各年度の付与を自動生成 ==========
  /// 
  /// 修正版（1年ごとに付与）：
  /// 例：
  /// - hireDate: 2026年4月1日
  /// - firstAccrualDate: 2026年10月1日（入社6ヶ月後）
  /// 
  /// 生成されるスケジュール：
  /// - 2026年10月1日：10日（初回）
  /// - 2027年10月1日：11日（1年後）
  /// - 2028年10月1日：12日（2年後）
  /// ...
  /// 付与日数は初回からの回数で法定の表を引く（N62・N63 の accrualForYear）。作った件数を返す
  Future<int> autoGenerateAccruals(
    String userId,
    DateTime hireDate,
    DateTime firstAccrualDate,
  ) async {
    var createdCount = 0;
    try {
      print('🔄 autoGenerateAccruals() 開始: userId=$userId');

      // 既存の付与履歴を確認
      final existingAccruals = await getVacationAccrualsByUser(userId);
      print('📊 既存の付与履歴: ${existingAccruals.length}件');

      // 今日までに来た付与日を、古い順に処理する（N61）
      for (final accrual in accrualsUntilToday(firstAccrualDate)) {
        final accrualDate = accrual.date;

        // この年の付与日数（N62・N63：初回からの回数で法定の表を引く）
        final daysGranted = accrual.days;

        // 失効日（最後に使える日）。DB に入る値も VacationAccrual.create で同じ計算（N60）
        final expiryDate = VacationAccrual.calculateExpiryDate(accrualDate);

        // 既に同じ日付の付与があるかチェック
        final isDuplicate = existingAccruals.any((accrual) {
          return accrual.accrualDate.year == accrualDate.year &&
                 accrual.accrualDate.month == accrualDate.month &&
                 accrual.accrualDate.day == accrualDate.day;
        });

        if (isDuplicate) {
          print('✅ スキップ（既に登録済み）：${accrualDate.year}年${accrualDate.month}月${accrualDate.day}日 $daysGranted日');
          continue;
        }

        // 付与を記録
        await recordVacationAccrual(
          userId,
          accrualDate,
          daysGranted.toDouble(),
          notes: '自動生成：${accrualDate.year}年度付与',
        );
        createdCount++;

        print('✅ 付与を自動生成：${accrualDate.year}年${accrualDate.month}月${accrualDate.day}日 → ${expiryDate.year}年${expiryDate.month}月${expiryDate.day}日 ($daysGranted日)');
      }

      print('✅ autoGenerateAccruals() 完了');
    } catch (e) {
      print('❌ Error auto-generating accruals: $e');
    }
    return createdCount;
  }
    /// ========== Week 16 修正版：来年度付与までに消滅する付与を取得 ==========
  /// 
  /// 返り値：来年度の付与日までに消滅する「1つの付与分」のデータ
  /// null の場合は消滅予定なし
  Future<Map<String, dynamic>?> getNextExpiringAccrual(String userId) async {
    try {
      final accruals = await getVacationAccrualsByUser(userId);
      if (accruals.isEmpty) {
        print('⚠️ getNextExpiringAccrual: 付与履歴がありません (userId=$userId)');
        return null;
      }

      final now = DateTime.now();

      // 来年度付与までに消滅する付与を探す（失効日が未来で、最も近い1件）
      Map<String, dynamic>? nextExpiring;
      DateTime? closestExpiryDate;

      for (final accrual in accruals) {
        // 失効日が過去か現在かチェック
        if (now.isAfter(accrual.expiryDate)) {
          continue;  // 既に失効済みはスキップ
        }

        // この付与期間内の使用日数を計算
        final usageInPeriod = await _getTotalDaysUsedInRange(
          userId,
          accrual.accrualDate,
          accrual.expiryDate,
        );

        final daysRemaining = accrual.daysGranted - usageInPeriod;
        final expiryDate = accrual.expiryDate;

        // 最も近い失効日を更新
        if (closestExpiryDate == null || expiryDate.isBefore(closestExpiryDate)) {
          closestExpiryDate = expiryDate;
          nextExpiring = {
            'accrualDate': accrual.accrualDate.toIso8601String().split('T')[0],
            'accrualMonth': accrual.accrualDate.month,
            'accrualDay': accrual.accrualDate.day,
            'daysGranted': accrual.daysGranted,
            'expiryDate': expiryDate.toIso8601String().split('T')[0],
            'expiryMonth': expiryDate.month,
            'expiryDay': expiryDate.day,
            'daysRemaining': daysRemaining,
            'daysUsed': usageInPeriod,
            'isExpired': false,
            'daysUntilExpiry': expiryDate.difference(now).inDays,
          };
        }
      }

      if (nextExpiring != null) {
        print('📅 [getNextExpiringAccrual] ${nextExpiring['accrualMonth']}月${nextExpiring['accrualDay']}日付与：残${nextExpiring['daysRemaining']}日 → ${nextExpiring['expiryMonth']}月${nextExpiring['expiryDay']}日失効');
      }

      return nextExpiring;
    } catch (e) {
      print('❌ Error getting next expiring accrual: $e');
      return null;
    }
  }
}

/// 付与サマリー（UI表示用）
class VacationSummary {
  final double totalGranted;        // 累計付与日数
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