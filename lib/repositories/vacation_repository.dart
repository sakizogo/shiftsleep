import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shiftsleep/database/database_helper.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/services/vacation_allocation.dart';

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

  /// 日付の範囲を SQL の文字列で比べるための値（N70）
  /// 開始日の 'YYYY-MM-DD' と、終了日の翌日の 'YYYY-MM-DD' を返す。「列 >= start AND 列 < endExclusive」で使うと、
  /// 終了日の日が丸ごと入る（…Z つきの行や 23:59:59.999 の行も当たる）
  /// 時刻は捨てて年・月・日だけを使う（toLocal() は通さない。N64 と同じ）
  static ({String start, String endExclusive}) dayRangeForSql(DateTime start, DateTime end) {
    final startDay = DateTime(start.year, start.month, start.day);
    final nextDay = DateTime(end.year, end.month, end.day + 1);
    return (
      start: startDay.toIso8601String().split('T')[0],
      endExclusive: nextDay.toIso8601String().split('T')[0],
    );
  }

  /// 失効の警告に使う失効日を選ぶ（N89）
  /// 残りがある（0.5 日でも）付与のうち、失効日が today〜today+daysThreshold 日のいちばん早いもの。なければ null
  /// 日付は年・月・日だけで比べる（失効日の当日は入る・翌日からは入らない）
  static DateTime? expiryDateForWarning(
    Iterable<AccrualBalance> accruals,
    DateTime today, {
    int daysThreshold = 30,
  }) {
    final todayDate = DateTime(today.year, today.month, today.day);
    final lastDate = DateTime(today.year, today.month, today.day + daysThreshold);

    DateTime? earliest;
    for (final a in accruals) {
      if (a.remainingDays <= 0) continue;
      final expiry = a.accrual.expiryDate;
      final expiryDate = DateTime(expiry.year, expiry.month, expiry.day);
      if (expiryDate.isBefore(todayDate) || expiryDate.isAfter(lastDate)) continue;
      if (earliest == null || expiry.isBefore(earliest)) earliest = expiry;
    }
    return earliest;
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
  /// N70：開始日〜終了日の日付で比べる（時刻は見ない。終了日の日は Z つきの行も含めて丸ごと入る）
  Future<List<VacationUsage>> getVacationUsageInRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await _dbHelper.database;
    final range = dayRangeForSql(startDate, endDate);
    final result = await db.query(
      'vacation_usage',
      where: 'user_id = ? AND usage_date >= ? AND usage_date < ?',
      whereArgs: [userId, range.start, range.endExclusive],
      orderBy: 'usage_date DESC',
    );
    debugPrint('🔍 N70: 有給使用 usage_date ${range.start} 以上 ${range.endExclusive} 未満 → ${result.length} 件');

    return result.map((map) => VacationUsage.fromMap(map)).toList();
  }

  /// いまの付与年度（N66）。初回付与日がないか、まだ初回の付与が来ていなければ暦年（1/1〜12/31）
  Future<FiscalYear> getCurrentFiscalYear(String userId) async {
    final now = DateTime.now();
    final firstAccrualDate = await getFirstAccrualDate(userId);
    final fiscalYear =
        firstAccrualDate == null ? null : fiscalYearOn(firstAccrualDate, now);
    return fiscalYear ??
        FiscalYear(
          start: DateTime(now.year, 1, 1),
          end: DateTime(now.year, 12, 31),
          isCalendarYear: true,
        );
  }

  /// 付与年度の有給使用（新しい順）（N66）。今日より後の使用（予定）も入れる
  /// dayRangeForSql で比べる（半開区間：開始日以上・終了日の翌日未満。Z があってもなくても当たる）
  Future<List<VacationUsage>> getVacationUsageInFiscalYear(
    String userId,
    FiscalYear fiscalYear,
  ) async {
    final db = await _dbHelper.database;
    final range = dayRangeForSql(fiscalYear.start, fiscalYear.end);

    final result = await db.query(
      'vacation_usage',
      where: 'user_id = ? AND usage_date >= ? AND usage_date < ?',
      whereArgs: [userId, range.start, range.endExclusive],
      orderBy: 'usage_date DESC',
    );

    return result.map((map) => VacationUsage.fromMap(map)).toList();
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

  /// 付与の行・使用の行（全件）・持ち越しを読み、使用を付与に割り当てる（N80）
  Future<VacationBalance> getVacationBalance(String userId) async {
    final db = await _dbHelper.database;
    final accruals = await getVacationAccrualsByUser(userId);
    final usageRows = await db.query(
      'vacation_usage',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final usages = usageRows.map((map) => VacationUsage.fromMap(map)).toList();
    final carryOver = await getCarryOver(userId);

    return allocateUsage(
      accruals: accruals,
      usages: usages,
      today: DateTime.now(),
      carryOver: carryOver,
    );
  }

  /// 付与ごとの割り当て結果をログに出す（N80）
  void _printBalance(VacationBalance balance) {
    for (final a in balance.accruals) {
      final date = a.accrual.accrualDate.toIso8601String();
      final carryOverMark = a.isCarryOverTarget ? '（持ち越し）' : '';
      if (a.isExpired) {
        debugPrint('⏰ Accrual expired: date=$date, starting=${a.startingDays}$carryOverMark, used=${a.usedDays}, expiry_date=${a.accrual.expiryDate.toIso8601String()}');
      } else {
        debugPrint('📊 Accrual: date=$date, starting=${a.startingDays}$carryOverMark, used=${a.usedDays}, remaining=${a.remainingDays}');
      }
    }
    if (balance.unallocatedDays > 0) {
      debugPrint('ℹ️ 付与が足りず割り当てなかった使用: ${balance.unallocatedDays}日');
    }
    debugPrint('✅ Total remaining days: ${balance.totalRemaining}');
  }

  /// 🌟 現在の残日数を計算（N80：使用を古い付与から順に割り当て、有効な付与の残りを合計）
  Future<double> calculateRemainingDays(String userId) async {
    final balance = await getVacationBalance(userId);

    if (balance.accruals.isEmpty) {
      print('⚠️ No vacation accruals found for userId=$userId');
      return 0.0;
    }

    _printBalance(balance);
    return balance.totalRemaining;
  }

  /// 付与サマリーを取得（UI表示用）
  /// N80：付与・使用・残りは有効な付与だけで数える（付与 − 使用 = 残り）
  Future<VacationSummary?> getAccrualSummary(String userId) async {
    final balance = await getVacationBalance(userId);
    if (balance.accruals.isEmpty) return null;

    _printBalance(balance);
    // N89：使い切った付与は警告に出さない（残りは allocateUsage の割り当て結果）
    final nextExpiryDate = expiryDateForWarning(balance.validAccruals, DateTime.now());
    debugPrint('⏰ N89: 失効の警告に使う失効日 → ${nextExpiryDate?.toIso8601String() ?? 'なし'}');

    return VacationSummary(
      totalGranted: balance.totalGranted,
      totalUsed: balance.totalUsed,
      totalRemaining: balance.totalRemaining,
      nextExpiryDate: nextExpiryDate,
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

  /// 持ち越し日数と基準日を読む（N80）。日数が 0 以下か、基準日がなければ null
  Future<CarryOver?> getCarryOver(String userId) async {
    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'app_settings',
        columns: ['carried_over_days', 'carried_over_base_date'],
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      if (results.isEmpty) return null;

      final days = (results.first['carried_over_days'] as num?)?.toDouble() ?? 0.0;
      final baseDateStr = results.first['carried_over_base_date'] as String?;
      if (days <= 0 || baseDateStr == null) return null;

      return CarryOver(baseDate: DateTime.parse(baseDateStr), days: days);
    } catch (e) {
      debugPrint('❌ Error getting carry over: $e');
      return null;
    }
  }

  /// 今日の時点の直近の付与日（初回付与日から 1 年ごと）。初回付与日がないか、まだ付与が来ていなければ null（N80）
  Future<DateTime?> _latestAccrualDateUntilToday(String userId) async {
    final firstAccrualDate = await getFirstAccrualDate(userId);
    if (firstAccrualDate == null) return null;
    final accruals = accrualsUntilToday(firstAccrualDate);
    return accruals.isEmpty ? null : accruals.last.date;
  }

  /// 持ち越しを保存するときの基準日を決める（N80）
  /// - 日数が 0 なら null
  /// - 日数が DB の値と同じで、対象の付与（基準日より前でいちばん新しい付与）がまだ有効なら、基準日を変えない
  /// - それ以外（日数が変わった・基準日が空・対象の付与が失効した）は、その時点の直近の付与日
  Future<DateTime?> _carriedOverBaseDateToSave(
    String userId,
    int carriedOverDays,
    Map<String, Object?>? stored,
  ) async {
    if (carriedOverDays <= 0) return null;

    final storedDays = (stored?['carried_over_days'] as num?)?.toInt() ?? 0;
    final storedBaseDateStr = stored?['carried_over_base_date'] as String?;
    if (storedDays == carriedOverDays && storedBaseDateStr != null) {
      final storedBaseDate = DateTime.parse(storedBaseDateStr);
      final balance = allocateUsage(
        accruals: await getVacationAccrualsByUser(userId),
        usages: const [],
        today: DateTime.now(),
        carryOver: CarryOver(baseDate: storedBaseDate, days: storedDays.toDouble()),
      );
      final targetIsValid = balance.accruals.any((a) => a.isCarryOverTarget && !a.isExpired);
      if (targetIsValid) {
        debugPrint('ℹ️ N80: 持ち越しの日数が同じで対象の付与も有効なので、基準日は ${storedBaseDateStr.split('T')[0]} のまま');
        return storedBaseDate;
      }
    }

    final latestAccrualDate = await _latestAccrualDateUntilToday(userId);
    if (latestAccrualDate == null) {
      debugPrint('⚠️ N80: 直近の付与日がわからないため、持ち越しの基準日は空のまま');
    } else {
      debugPrint('🔄 N80: 持ち越しの基準日を ${latestAccrualDate.toIso8601String().split('T')[0]} に設定');
    }
    return latestAccrualDate;
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

      // N80：持ち越しの基準日
      final baseDate = await _carriedOverBaseDateToSave(
        userId,
        carriedOverDays,
        results.isEmpty ? null : results.first,
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
            'carried_over_base_date': baseDate?.toIso8601String(),
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
            'carried_over_base_date': baseDate?.toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'user_id = ?',
          whereArgs: [userId],
        );
        print('✅ 持ち越し有休数を更新: $carriedOverDays日');
      }
    } catch (e) {
      print('❌ Error saving carried over days: $e');
      rethrow;  // N82：画面で失敗を知らせる
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
      rethrow;  // N82：画面で失敗を知らせる
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

  /// ========== Week 16 付与日数の自動計算ヘルパー ==========
  
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

  /// today を含む付与年度（N66）：今日以前でいちばん新しい付与日 〜 次の付与日の前日
  /// 今日が初回付与日より前なら null。日付は年・月・日だけで比べる
  static FiscalYear? fiscalYearOn(DateTime firstAccrualDate, DateTime today) {
    final todayDate = DateTime(today.year, today.month, today.day);
    DateTime? start;
    for (int i = 0; i < 100; i++) {  // 万一のための上限
      final date = accrualDateForYear(firstAccrualDate, i);
      if (date.isAfter(todayDate)) {
        if (start == null) return null;
        return FiscalYear(
          start: start,
          end: DateTime(date.year, date.month, date.day - 1),
        );
      }
      start = date;
    }
    return null;
  }

  /// 付与年度に入る使用の合計（N66）。今日より後の使用（予定）も足す
  /// 使用日は年・月・日のまま比べる（toLocal() は通さない。Z つきの行も同じ日になる）
  static double usedDaysInFiscalYear(List<VacationUsage> usages, FiscalYear fiscalYear) {
    return usages
        .where((u) => fiscalYear.contains(u.usageDate))
        .fold(0.0, (sum, u) => sum + u.daysUsed);
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
      final balance = await getVacationBalance(userId);
      if (balance.accruals.isEmpty) {
        print('⚠️ getNextExpiringAccrual: 付与履歴がありません (userId=$userId)');
        return null;
      }

      // N80：有効な付与のうち失効がいちばん早いもの（残りは allocateUsage の割り当て結果）
      final next = balance.nextExpiring;
      final nextExpiring = next == null ? null : _accrualBalanceToMap(next, DateTime.now());

      if (nextExpiring != null) {
        print('📅 [getNextExpiringAccrual] ${nextExpiring['accrualMonth']}月${nextExpiring['accrualDay']}日付与：残${nextExpiring['daysRemaining']}日 → ${nextExpiring['expiryMonth']}月${nextExpiring['expiryDay']}日失効');
      }

      return nextExpiring;
    } catch (e) {
      print('❌ Error getting next expiring accrual: $e');
      return null;
    }
  }

  /// 付与の割り当て結果を、消滅予定の画面で使う Map にする（N80）
  /// daysGranted は最初の日数（持ち越しの対象なら持ち越し日数）
  static Map<String, dynamic> _accrualBalanceToMap(AccrualBalance a, DateTime now) {
    final accrual = a.accrual;
    return {
      'accrualDate': accrual.accrualDate.toIso8601String().split('T')[0],
      'accrualMonth': accrual.accrualDate.month,
      'accrualDay': accrual.accrualDate.day,
      'daysGranted': a.startingDays,
      'expiryDate': accrual.expiryDate.toIso8601String().split('T')[0],
      'expiryMonth': accrual.expiryDate.month,
      'expiryDay': accrual.expiryDate.day,
      'daysRemaining': a.remainingDays,
      'daysUsed': a.usedDays,
      'isExpired': a.isExpired,
      'daysUntilExpiry': accrual.expiryDate.difference(now).inDays,
    };
  }
}

/// 付与年度（N66）。start〜end はどちらもその日を含む（年・月・日だけ）
class FiscalYear {
  final DateTime start;
  final DateTime end;
  final bool isCalendarYear;  // 付与年度が求まらず、暦年（1/1〜12/31）にしたとき true

  const FiscalYear({
    required this.start,
    required this.end,
    this.isCalendarYear = false,
  });

  /// その日が付与年度に入るか（年・月・日だけで比べる。toLocal() は通さない）
  bool contains(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return !date.isBefore(start) && !date.isAfter(end);
  }
}

/// 付与サマリー（UI表示用）
class VacationSummary {
  final double totalGranted;        // 累計付与日数
  final double totalUsed;        // 累計使用日数
  final double totalRemaining;   // 累計残日数
  final DateTime? nextExpiryDate; // 次の失効日

  VacationSummary({
    required this.totalGranted,
    required this.totalUsed,
    required this.totalRemaining,
    this.nextExpiryDate,
  });

  /// 失効予定がある場合、警告メッセージを生成
  String? get expiryWarningMessage {
    if (nextExpiryDate == null) return null;
    return expiryWarningMessageFor(nextExpiryDate!, DateTime.now());
  }

  /// 失効日と today から警告の文言を作る（N90）
  /// 日数は年・月・日だけで数える（失効日は最後に使える日の 23:59:59.999 なので、時刻込みだと当日が 0 になる）
  /// 当日：最後の日、1〜30 日前：消滅の予告、それ以外（失効した翌日以降・31 日以上先）：null
  static String? expiryWarningMessageFor(DateTime expiryDate, DateTime today) {
    final expiryDay = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    final todayDate = DateTime(today.year, today.month, today.day);
    final days = expiryDay.difference(todayDate).inDays;

    if (days == 0) {
      return '⚠️ 本日が有給を使える最後の日です';
    } else if (days >= 1 && days <= 30) {
      final monthStr = '${expiryDate.month}月${expiryDate.day}日';
      return '⚠️ $monthStr までに使わないと有給が消滅してしまいます。計画的に使いましょう！';
    }

    return null;
  }
}