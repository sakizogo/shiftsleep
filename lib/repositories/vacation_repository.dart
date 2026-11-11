import 'dart:async';  // N165：FutureOr

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shiftsleep/database/database_helper.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/services/vacation_allocation.dart';
import 'package:shiftsleep/services/in_flight.dart';  // N160

/// N165：自動生成の付与の合わせ直しの計画（消す行と、足す付与の日付・日数）
typedef AccrualSyncPlan = ({
  List<VacationAccrual> toDelete,
  List<({DateTime date, int days})> toAdd,
});

/// N165：合わせ直したときの影響（確認ダイアログで知らせる）
/// - carryOverTargetLost：持ち越しの対象の付与が、今はあって有効なのに、合わせ直すとなくなる（持ち越しの入力が 0 なら false）
/// - unallocatedBefore / unallocatedAfter：どの付与にも入らない使用の日数（合わせ直す前・後）
/// - usagesBeforeFirstCount / usagesBeforeFirstDays：新しい初回付与日より前の使用の件数・日数
typedef AccrualSyncImpact = ({
  bool carryOverTargetLost,
  double unallocatedBefore,
  double unallocatedAfter,
  int usagesBeforeFirstCount,
  double usagesBeforeFirstDays,
});

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

  /// 有給設定（入社日と付与日数）を保存する（N165：saveVacationSettingsAll から呼ぶ）
  /// 渡された executor（db か txn）だけを使う
  static Future<void> _saveVacationSettingsIn(
    DatabaseExecutor db,
    String userId,
    DateTime hiredDate,
    int annualDays,
  ) async {
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
    await _insertAccrual(db, userId, accrualDate, daysGranted, notes: notes);
  }

  /// N156：付与を 1 行入れる。渡された executor（db か txn）だけを使う
  static Future<void> _insertAccrual(
    DatabaseExecutor db,
    String userId,
    DateTime accrualDate,
    double daysGranted, {
    String? notes,
  }) async {
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
    return _queryAccrualsByUser(db, userId);
  }

  /// N156：付与履歴を読む。渡された executor（db か txn）だけを使う
  static Future<List<VacationAccrual>> _queryAccrualsByUser(DatabaseExecutor db, String userId) async {
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

  /// N140 3/4：カレンダーから入れた有休・半休の使用理由
  static String calendarVacationReason(double days) =>
      days == 0.5 ? 'カレンダーから登録（半休）' : 'カレンダーから登録（有休）';

  /// N140 3/4：「シフトを確定」のトランザクションの中で、有休・半休の差分を書く
  /// 渡された txn だけを使う（トランザクションの途中で DatabaseHelper の db を呼ぶと sqflite が固まるため）
  /// 差分のある日だけ、その日の行を消してから（N68 と同じ条件）、days があれば入れ直す
  /// 失敗したら例外がそのまま上がり、トランザクションごと確定前に戻る
  static Future<void> applyVacationChanges(
    DatabaseExecutor txn,
    String userId,
    List<({DateTime date, double? days})> changes,
  ) async {
    for (final change in changes) {
      final day = DateTime(change.date.year, change.date.month, change.date.day);
      final range = dayRangeForSql(day, day);
      final deletedCount = await txn.delete(
        'vacation_usage',
        where: 'user_id = ? AND usage_date >= ? AND usage_date < ?',
        whereArgs: [userId, range.start, range.endExclusive],
      );
      final days = change.days;
      if (days != null) {
        final usage = VacationUsage.create(
          userId: userId,
          usageDate: day,
          daysUsed: days,
          reason: calendarVacationReason(days),
        );
        await txn.insert('vacation_usage', usage.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      debugPrint('📝 N140：有休の確定 ${range.start} 消した行 $deletedCount 件 → ${days ?? 'なし'}');
    }
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
  /// N118 3/4：行がなければ 0.0。読めなかったときは例外を上げる（「持ち越しなし」と分ける）
  Future<double> getCarriedOverDays(String userId) async {
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
      
      // N118 3/4：getCarryOver と同じく num で読む（REAL の値でも型の例外にしない）
      final carriedOverDays = (results.first['carried_over_days'] as num?)?.toDouble() ?? 0.0;
      print('✅ getCarriedOverDays: $carriedOverDays日 取得成功 (userId=$userId)');
      return carriedOverDays;
    } catch (e) {
      print('❌ Error getting carried over days: $e');
      rethrow;  // N118 3/4：「読めなかった」を「持ち越しなし」と分ける
    }
  }

  /// 持ち越し日数と基準日を読む（N80）。日数が 0 以下か、基準日がなければ null
  /// N118 3/4：読めなかったときは例外を上げる（null は「持ち越しなし」だけ）
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
      rethrow;  // N118 3/4：「読めなかった」を「持ち越しなし」と分ける
    }
  }

  /// today の時点の直近の付与日（初回付与日から 1 年ごと）。初回付与日がないか、まだ付与が来ていなければ null（N80）
  /// N165：DB を使わない形にした（today を渡せる）
  static DateTime? latestAccrualDateUntil(DateTime? firstAccrualDate, DateTime today) {
    if (firstAccrualDate == null) return null;
    final accruals = accrualsUntil(firstAccrualDate, today);
    return accruals.isEmpty ? null : accruals.last.date;
  }

  /// 保存済みの基準日をそのまま使えるなら、その基準日。使えなければ null（N80。N165 で DB を使わない形に切り出し）
  /// 日数が 0 より大きく DB の値と同じで、DB の基準日があり、accruals の中で対象の付与
  /// （基準日より前でいちばん新しい付与）が today の時点で有効なとき
  static DateTime? keptCarriedOverBaseDate({
    required int carriedOverDays,
    required int storedDays,
    required DateTime? storedBaseDate,
    required List<VacationAccrual> accruals,
    required DateTime today,
  }) {
    if (carriedOverDays <= 0) return null;
    if (storedDays != carriedOverDays || storedBaseDate == null) return null;
    final balance = allocateUsage(
      accruals: accruals,
      usages: const [],
      today: today,
      carryOver: CarryOver(baseDate: storedBaseDate, days: storedDays.toDouble()),
    );
    final targetIsValid = balance.accruals.any((a) => a.isCarryOverTarget && !a.isExpired);
    return targetIsValid ? storedBaseDate : null;
  }

  /// 持ち越しを保存するときの基準日を決める（N80。N165 で DB を使わない形に切り出し）
  /// - 日数が 0 以下なら null
  /// - 日数が DB の値と同じで、対象の付与（基準日より前でいちばん新しい付与）がまだ有効なら、基準日を変えない
  /// - それ以外（日数が変わった・基準日が空・対象の付与が失効した）は、初回付与日から計算した today までで最後の付与日
  /// _carriedOverBaseDateToSave と同じ判定（あちらは必要なときだけ DB を読み、ログを出す）
  static DateTime? decideCarriedOverBaseDate({
    required int carriedOverDays,
    required int storedDays,
    required DateTime? storedBaseDate,
    required List<VacationAccrual> accruals,
    required DateTime? firstAccrualDate,
    required DateTime today,
  }) {
    if (carriedOverDays <= 0) return null;
    final kept = keptCarriedOverBaseDate(
      carriedOverDays: carriedOverDays,
      storedDays: storedDays,
      storedBaseDate: storedBaseDate,
      accruals: accruals,
      today: today,
    );
    return kept ?? latestAccrualDateUntil(firstAccrualDate, today);
  }

  /// 持ち越しを保存するときの基準日を決める（N80。判定は decideCarriedOverBaseDate と同じ）
  /// N165：渡された executor（db か txn）だけを使う。付与の行・初回付与日は必要なときだけ読む
  static Future<DateTime?> _carriedOverBaseDateToSave(
    DatabaseExecutor db,
    String userId,
    int carriedOverDays,
    Map<String, Object?>? stored,
  ) async {
    if (carriedOverDays <= 0) return null;

    final storedDays = (stored?['carried_over_days'] as num?)?.toInt() ?? 0;
    final storedBaseDateStr = stored?['carried_over_base_date'] as String?;
    if (storedDays == carriedOverDays && storedBaseDateStr != null) {
      final kept = keptCarriedOverBaseDate(
        carriedOverDays: carriedOverDays,
        storedDays: storedDays,
        storedBaseDate: DateTime.parse(storedBaseDateStr),
        accruals: await _queryAccrualsByUser(db, userId),
        today: DateTime.now(),
      );
      if (kept != null) {
        debugPrint('ℹ️ N80: 持ち越しの日数が同じで対象の付与も有効なので、基準日は ${storedBaseDateStr.split('T')[0]} のまま');
        return kept;
      }
    }

    final latestAccrualDate = latestAccrualDateUntil(
      await _queryFirstAccrualDate(db, userId),
      DateTime.now(),
    );
    if (latestAccrualDate == null) {
      debugPrint('⚠️ N80: 直近の付与日がわからないため、持ち越しの基準日は空のまま');
    } else {
      debugPrint('🔄 N80: 持ち越しの基準日を ${latestAccrualDate.toIso8601String().split('T')[0]} に設定');
    }
    return latestAccrualDate;
  }

  /// 持ち越し有休数を app_settings に保存する（N165：saveVacationSettingsAll から呼ぶ）
  /// 重要：app_settings にレコードがない場合は INSERT、ある場合は UPDATE を行う
  /// 渡された executor（db か txn）だけを使う。失敗は呼んだ側に上げる
  static Future<void> _saveCarriedOverDaysIn(
    DatabaseExecutor db,
    String userId,
    int carriedOverDays,
  ) async {
    // app_settings のレコード存在確認
    final results = await db.query(
      'app_settings',
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    // N80：持ち越しの基準日
    final baseDate = await _carriedOverBaseDateToSave(
      db,
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
  }

  // ========== Week 16 追加: 初回付与日管理 ==========
  
  /// 初回付与日を保存する（N165：saveVacationSettingsAll から呼ぶ）
  ///
  /// 例：初回付与日が2026年10月1日の場合
  /// - 2026年度の付与日：10月1日
  /// - 2027年度の付与日：10月1日（1年後）
  /// - 2028年度の付与日：10月1日（2年後）...
  /// 渡された executor（db か txn）だけを使う。失敗は呼んだ側に上げる
  static Future<void> _saveFirstAccrualDateIn(
    DatabaseExecutor db,
    String userId,
    DateTime firstAccrualDate,
  ) async {
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
  }

  /// 初回付与日を読み込み
  /// N118 3/4：未登録なら null。読めなかったときは例外を上げる（「未登録」と分ける）
  Future<DateTime?> getFirstAccrualDate(String userId) {
    return _queryFirstAccrualDate(_dbHelper.database, userId);
  }

  /// N165：getFirstAccrualDate の中身。渡された executor（db か txn）だけを使う（ログ・例外の扱いは同じ）
  /// db は Future でもよい（getFirstAccrualDate では DB を開くところの失敗も同じログにするため）
  static Future<DateTime?> _queryFirstAccrualDate(FutureOr<DatabaseExecutor> executor, String userId) async {
    try {
      final db = await executor;
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
      rethrow;  // N118 3/4：「読めなかった」を「未登録」と分ける
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
    return accrualsUntil(firstAccrualDate, DateTime.now());
  }

  /// 最初の付与日から、now の日までに来た付与の一覧（古い順）（N165：accrualsUntilToday の今日を渡せる形）
  static List<({DateTime date, int days})> accrualsUntil(DateTime firstAccrualDate, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final accruals = <({DateTime date, int days})>[];
    for (int i = 0; i < 100; i++) {  // 万一のための上限
      final accrual = accrualForYear(firstAccrualDate, i);
      if (accrual.date.isAfter(today)) break;
      accruals.add(accrual);
    }
    return accruals;
  }

  /// 自動生成の付与の notes の先頭（N165。DB v18 のマイグレーションの LIKE と同じ）
  static const String autoAccrualNotesPrefix = '自動生成：';

  /// 自動生成の付与の notes（N165：_autoGenerateAccruals と合わせ直しで共通）
  static String autoAccrualNotes(DateTime accrualDate) =>
      '$autoAccrualNotesPrefix${accrualDate.year}年度付与';

  /// 自動生成の付与か（N165）。notes が null の行は自動生成ではない
  static bool isAutoGeneratedAccrual(VacationAccrual accrual) =>
      accrual.notes?.startsWith(autoAccrualNotesPrefix) ?? false;

  /// 年・月・日が同じか（N165）。toLocal() は通さず数字のまま比べる（N64 と同じ）
  static bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 付与日の年月日の古い順、同じ日付なら id 順（N165 3a）。_isSameDate と同じく数字のまま比べる
  static int _compareByDateThenId(VacationAccrual a, VacationAccrual b) {
    final byDate = DateTime(a.accrualDate.year, a.accrualDate.month, a.accrualDate.day)
        .compareTo(DateTime(b.accrualDate.year, b.accrualDate.month, b.accrualDate.day));
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  }

  /// 既存の付与の行と予定から、合わせ直しの計画を作る（N165。DB は使わない）
  /// - toDelete：自動生成の行のうち、予定のどの日付とも年月日が合わない行（付与日の古い順。同じ日付なら id 順）
  /// - toAdd：予定のうち、既存のどの行（自動生成でない行も含む）とも年月日が合わない付与（schedule の順）
  /// 既存の行の日数は見ない・変えない
  static AccrualSyncPlan planAccrualSync({
    required List<VacationAccrual> existing,
    required List<({DateTime date, int days})> schedule,
  }) {
    final toDelete = existing
        .where((a) =>
            isAutoGeneratedAccrual(a) &&
            !schedule.any((s) => _isSameDate(s.date, a.accrualDate)))
        .toList()
      ..sort(_compareByDateThenId);  // N165 3a：existing は新しい順で読むため、古い順に並べ直す
    final toAdd = schedule
        .where((s) => !existing.any((a) => _isSameDate(a.accrualDate, s.date)))
        .toList();
    return (toDelete: toDelete, toAdd: toAdd);
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
  /// N160：まとめる処理は runOnce（終わったら結果・失敗が呼び出し元に届く）
  static final Map<String, Future<int>> _autoGenerateInFlight = {};

  /// DB の入社日（vacation_settings.hired_date）と初回付与日（app_settings.first_accrual_date）から
  /// 今日までの付与を自動生成する（N62）。どちらかがなければ何もしない。作った件数を返す
  Future<int> autoGenerateAccrualsFromSettings(String userId) {
    return runOnce(_autoGenerateInFlight, userId, () => _autoGenerateAccrualsFromSettings(userId));
  }

  Future<int> _autoGenerateAccrualsFromSettings(String userId) async {
    final settings = await getVacationSettings(userId);
    final firstAccrualDate = await getFirstAccrualDate(userId);
    // 入社日（vacation_settings の行）がなければ生成しない。入社日の値そのものは使わない（N165）
    if (settings == null || firstAccrualDate == null) {
      debugPrint('🗓️ N62: 入社日または初回付与日が未設定のため、自動生成しません');
      return 0;
    }
    final createdCount = await _autoGenerateAccruals(userId, firstAccrualDate);
    debugPrint('🗓️ N62: 付与を $createdCount 件自動生成');
    return createdCount;
  }

    /// ========== Week 16 修正版：first_accrual_date から各年度の付与を自動生成 ==========
  ///
  /// 修正版（1年ごとに付与）：
  /// 例：
  /// - firstAccrualDate: 2026年10月1日（入社6ヶ月後）
  /// 
  /// 生成されるスケジュール：
  /// - 2026年10月1日：10日（初回）
  /// - 2027年10月1日：11日（1年後）
  /// - 2028年10月1日：12日（2年後）
  /// ...
  /// 付与日数は初回からの回数で法定の表を引く（N62・N63 の accrualForYear）。作った件数を返す
  /// N165：呼び出し元は _autoGenerateAccrualsFromSettings だけ（runOnce を通す）
  Future<int> _autoGenerateAccruals(
    String userId,
    DateTime firstAccrualDate,
  ) async {
    var createdCount = 0;
    try {
      print('🔄 _autoGenerateAccruals() 開始: userId=$userId');

      // N156：既存の読み取り〜足りない付与の insert を 1 つのトランザクションにする
      // （同時に 2 回呼ばれても、2 回目は 1 回目が入れた行を読んでからスキップする）
      // 中では txn だけを使う（db や db を使うメソッドを呼ぶと sqflite が固まるため）
      final db = await _dbHelper.database;
      createdCount = await db.transaction((txn) async {
        var createdInTxn = 0;

        // 既存の付与履歴を確認
        final existingAccruals = await _queryAccrualsByUser(txn, userId);
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
            return _isSameDate(accrual.accrualDate, accrualDate);
          });

          if (isDuplicate) {
            print('✅ スキップ（既に登録済み）：${accrualDate.year}年${accrualDate.month}月${accrualDate.day}日 $daysGranted日');
            continue;
          }

          // 付与を記録
          await _insertAccrual(
            txn,
            userId,
            accrualDate,
            daysGranted.toDouble(),
            notes: autoAccrualNotes(accrualDate),
          );
          createdInTxn++;

          print('✅ 付与を自動生成：${accrualDate.year}年${accrualDate.month}月${accrualDate.day}日 → ${expiryDate.year}年${expiryDate.month}月${expiryDate.day}日 ($daysGranted日)');
        }
        return createdInTxn;
      });

      print('✅ _autoGenerateAccruals() 完了');
    } catch (e) {
      print('❌ Error auto-generating accruals: $e');
      // N91：失敗を呼んだ側に伝える
      // N156：トランザクションなので、途中で失敗するとこの回に入れた付与はすべて取り消される。再実行で全部作る
      rethrow;
    }
    return createdCount;
  }

  /// firstAccrualDate の予定に合わせて、自動生成の付与を消して足す（N165）
  /// 渡された executor（db か txn）だけを使う。消す行・足す付与はここで読み直して決める
  /// 既存の行の日数は変えない。消した件数・足した件数を返す
  static Future<({int deletedCount, int addedCount})> syncAccrualsWithSchedule(
    DatabaseExecutor db,
    String userId,
    DateTime firstAccrualDate,
  ) async {
    final existing = await _queryAccrualsByUser(db, userId);
    final plan = planAccrualSync(
      existing: existing,
      schedule: accrualsUntilToday(firstAccrualDate),
    );
    debugPrint('🔄 N165: 自動生成の付与を合わせ直し 消す ${plan.toDelete.length} 件・足す ${plan.toAdd.length} 件');

    var deletedCount = 0;
    for (final accrual in plan.toDelete) {
      final count = await db.delete(
        'vacation_accruals',
        where: 'id = ? AND user_id = ? AND notes LIKE ?',
        whereArgs: [accrual.id, userId, '$autoAccrualNotesPrefix%'],
      );
      deletedCount += count;
      debugPrint('🗑️ N165: ${_dateText(accrual.accrualDate)} (${accrual.daysGranted}日) を削除（$count 件）');
    }

    var addedCount = 0;
    for (final accrual in plan.toAdd) {
      await _insertAccrual(
        db,
        userId,
        accrual.date,
        accrual.days.toDouble(),
        notes: autoAccrualNotes(accrual.date),
      );
      addedCount++;
      debugPrint('➕ N165: ${_dateText(accrual.date)} (${accrual.days}日) を追加');
    }

    // 同じ日付の自動生成の行が 2 行以上残っていたら知らせるだけ（消さない）
    final keptCountByDate = <String, int>{};
    for (final accrual in existing) {
      if (!isAutoGeneratedAccrual(accrual) || plan.toDelete.contains(accrual)) continue;
      final key = _dateText(accrual.accrualDate);
      keptCountByDate[key] = (keptCountByDate[key] ?? 0) + 1;
    }
    keptCountByDate.forEach((date, count) {
      if (count > 1) {
        debugPrint('⚠️ N165: $date の自動生成の付与が $count 行あります（消しません）');
      }
    });

    debugPrint('✅ N165: 合わせ直し完了 消した $deletedCount 件・足した $addedCount 件');
    return (deletedCount: deletedCount, addedCount: addedCount);
  }

  /// ログ用の 'YYYY-MM-DD'（N165）
  static String _dateText(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// 合わせ直したときの影響を計算する（N165。DB は使わない）
  /// - 合わせ直したあとの付与：existing から plan.toDelete を除き、plan.toAdd を足したもの
  /// - 合わせ直したあとの持ち越しの基準日：decideCarriedOverBaseDate（保存と同じ判定）
  /// - 合わせ直す前の持ち越し：DB の日数と基準日（getCarryOver と同じく、日数が 0 以下か基準日がなければなし）
  /// N165 3b：［⚡ 付与スケジュールを自動生成］用の引数（どちらも既定値なら 2b の保存と同じ結果）
  /// - keepStoredCarryOver：true なら、合わせ直したあとも持ち越しは DB の日数と基準日のまま（持ち越しには触らない）
  ///   carriedOverDays には DB の日数を渡す（carryOverTargetLost の判定に使う）
  /// - countUsagesBeforeFirst：false なら、初回付与日より前の使用を数えない（初回付与日が変わらないため）
  static AccrualSyncImpact evaluateAccrualSync({
    required List<VacationAccrual> existing,
    required AccrualSyncPlan plan,
    required List<VacationUsage> usages,
    required int carriedOverDays,
    required int storedDays,
    required DateTime? storedBaseDate,
    required DateTime firstAccrualDate,
    required DateTime today,
    bool keepStoredCarryOver = false,
    bool countUsagesBeforeFirst = true,
  }) {
    final after = [
      ...existing.where((a) => !plan.toDelete.contains(a)),
      for (final s in plan.toAdd)
        VacationAccrual.create(
          userId: existing.isEmpty ? '' : existing.first.userId,
          accrualDate: s.date,
          daysGranted: s.days.toDouble(),
          notes: autoAccrualNotes(s.date),
        ),
    ];

    final carryOverBefore = storedDays > 0 && storedBaseDate != null
        ? CarryOver(baseDate: storedBaseDate, days: storedDays.toDouble())
        : null;
    final CarryOver? carryOverAfter;
    if (keepStoredCarryOver) {
      carryOverAfter = carryOverBefore;
    } else {
      final baseDateAfter = decideCarriedOverBaseDate(
        carriedOverDays: carriedOverDays,
        storedDays: storedDays,
        storedBaseDate: storedBaseDate,
        accruals: after,
        firstAccrualDate: firstAccrualDate,
        today: today,
      );
      carryOverAfter = carriedOverDays > 0 && baseDateAfter != null
          ? CarryOver(baseDate: baseDateAfter, days: carriedOverDays.toDouble())
          : null;
    }

    final balanceBefore = allocateUsage(
      accruals: existing,
      usages: usages,
      today: today,
      carryOver: carryOverBefore,
    );
    final balanceAfter = allocateUsage(
      accruals: after,
      usages: usages,
      today: today,
      carryOver: carryOverAfter,
    );
    bool hasValidTarget(VacationBalance b) =>
        b.accruals.any((a) => a.isCarryOverTarget && !a.isExpired);

    final first = DateTime(firstAccrualDate.year, firstAccrualDate.month, firstAccrualDate.day);
    final usagesBeforeFirst = countUsagesBeforeFirst
        ? usages.where((u) =>
            DateTime(u.usageDate.year, u.usageDate.month, u.usageDate.day).isBefore(first))
        : const <VacationUsage>[];

    return (
      carryOverTargetLost: carriedOverDays > 0 &&
          hasValidTarget(balanceBefore) &&
          !hasValidTarget(balanceAfter),
      unallocatedBefore: balanceBefore.unallocatedDays,
      unallocatedAfter: balanceAfter.unallocatedDays,
      usagesBeforeFirstCount: usagesBeforeFirst.length,
      usagesBeforeFirstDays: usagesBeforeFirst.fold(0.0, (sum, u) => sum + u.daysUsed),
    );
  }

  /// 確認ダイアログ用：初回付与日を firstAccrualDate に変えて保存したときの計画と影響（N165）
  /// DB は読むだけ。carriedOverDays は保存しようとしている持ち越しの日数（入力欄の値）
  Future<({AccrualSyncPlan plan, AccrualSyncImpact impact})> previewFirstAccrualDateChange(
    String userId,
    DateTime firstAccrualDate,
    int carriedOverDays,
  ) async {
    final db = await _dbHelper.database;
    final existing = await _queryAccrualsByUser(db, userId);
    final plan = planAccrualSync(
      existing: existing,
      schedule: accrualsUntilToday(firstAccrualDate),
    );
    final usageRows = await db.query(
      'vacation_usage',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final settingsRows = await db.query(
      'app_settings',
      columns: ['carried_over_days', 'carried_over_base_date'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final stored = settingsRows.isEmpty ? null : settingsRows.first;
    final storedBaseDateStr = stored?['carried_over_base_date'] as String?;

    final impact = evaluateAccrualSync(
      existing: existing,
      plan: plan,
      usages: usageRows.map((map) => VacationUsage.fromMap(map)).toList(),
      carriedOverDays: carriedOverDays,
      storedDays: (stored?['carried_over_days'] as num?)?.toInt() ?? 0,
      storedBaseDate: storedBaseDateStr == null ? null : DateTime.parse(storedBaseDateStr),
      firstAccrualDate: firstAccrualDate,
      today: DateTime.now(),
    );
    debugPrint('🔍 N165: 初回付与日の変更の確認 消す ${plan.toDelete.length} 件・足す ${plan.toAdd.length} 件'
        '・持ち越しの対象がなくなる ${impact.carryOverTargetLost}'
        '・初回付与日より前の使用 ${impact.usagesBeforeFirstCount} 件（${impact.usagesBeforeFirstDays}日）'
        '・どの付与にも入らない使用 ${impact.unallocatedBefore}日 → ${impact.unallocatedAfter}日');
    return (plan: plan, impact: impact);
  }

  /// 有給設定をまとめて保存する（N165）。1 つの transaction で、中では txn だけを使う
  /// 順番：入社日・付与日数 → 初回付与日（あれば）→ 付与の合わせ直し（syncAccruals のときだけ）→ 持ち越し
  /// 持ち越しの基準日は合わせ直したあとの付与の行で決める。どこかで失敗したら何も保存しない
  /// 合わせ直したら消した件数・足した件数を、合わせ直さなかったら null を返す
  Future<({int deletedCount, int addedCount})?> saveVacationSettingsAll(
    String userId, {
    required DateTime hiredDate,
    required int annualDays,
    DateTime? firstAccrualDate,
    required int carriedOverDays,
    required bool syncAccruals,
  }) async {
    try {
      final db = await _dbHelper.database;
      final result = await db.transaction((txn) async {
        await _saveVacationSettingsIn(txn, userId, hiredDate, annualDays);
        ({int deletedCount, int addedCount})? synced;
        if (firstAccrualDate != null) {
          await _saveFirstAccrualDateIn(txn, userId, firstAccrualDate);
          if (syncAccruals) {
            synced = await syncAccrualsWithSchedule(txn, userId, firstAccrualDate);
          }
        } else if (syncAccruals) {
          debugPrint('⚠️ N165: 初回付与日がないため、付与の合わせ直しはしません');
        }
        await _saveCarriedOverDaysIn(txn, userId, carriedOverDays);
        return synced;
      });
      debugPrint('✅ N165: 有給設定をまとめて保存しました（合わせ直し: ${result == null ? 'なし' : '消した ${result.deletedCount} 件・足した ${result.addedCount} 件'}）');
      return result;
    } catch (e) {
      debugPrint('❌ N165: 有給設定のまとめた保存に失敗（何も保存していません）: $e');
      rethrow;
    }
  }

  /// 確認ダイアログ用：保存済みの初回付与日（DB）の予定に合わせ直したときの計画と影響（N165 3b）
  /// ［⚡ 付与スケジュールを自動生成］で使う。DB は読むだけ。画面の入力欄の値は使わない
  /// - 初回付与日が未登録なら null
  /// - 持ち越しには触らないので、影響は DB の日数・基準日のままで計算する（keepStoredCarryOver）
  /// - 初回付与日は変わらないので、初回付与日より前の使用は数えない（countUsagesBeforeFirst: false）
  /// - carriedOverDays は DB の持ち越しの日数（⚠️ の文言に使う）
  Future<({
    DateTime firstAccrualDate,
    int carriedOverDays,
    AccrualSyncPlan plan,
    AccrualSyncImpact impact,
  })?> previewResyncWithSavedSettings(String userId) async {
    final db = await _dbHelper.database;
    final firstAccrualDate = await _queryFirstAccrualDate(db, userId);
    if (firstAccrualDate == null) {
      debugPrint('ℹ️ N165: 初回付与日が未登録のため、合わせ直しの確認はしません');
      return null;
    }
    final existing = await _queryAccrualsByUser(db, userId);
    final plan = planAccrualSync(
      existing: existing,
      schedule: accrualsUntilToday(firstAccrualDate),
    );
    final usageRows = await db.query(
      'vacation_usage',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final settingsRows = await db.query(
      'app_settings',
      columns: ['carried_over_days', 'carried_over_base_date'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final stored = settingsRows.isEmpty ? null : settingsRows.first;
    final storedDays = (stored?['carried_over_days'] as num?)?.toInt() ?? 0;
    final storedBaseDateStr = stored?['carried_over_base_date'] as String?;

    final impact = evaluateAccrualSync(
      existing: existing,
      plan: plan,
      usages: usageRows.map((map) => VacationUsage.fromMap(map)).toList(),
      carriedOverDays: storedDays,
      storedDays: storedDays,
      storedBaseDate: storedBaseDateStr == null ? null : DateTime.parse(storedBaseDateStr),
      firstAccrualDate: firstAccrualDate,
      today: DateTime.now(),
      keepStoredCarryOver: true,
      countUsagesBeforeFirst: false,
    );
    debugPrint('🔍 N165: 保存済みの初回付与日 ${_dateText(firstAccrualDate)} への合わせ直しの確認'
        ' 消す ${plan.toDelete.length} 件・足す ${plan.toAdd.length} 件'
        '・持ち越しの対象がなくなる ${impact.carryOverTargetLost}'
        '・どの付与にも入らない使用 ${impact.unallocatedBefore}日 → ${impact.unallocatedAfter}日');
    return (
      firstAccrualDate: firstAccrualDate,
      carriedOverDays: storedDays,
      plan: plan,
      impact: impact,
    );
  }

  /// 確認したときの初回付与日（expected）が、合わせ直す直前の DB の初回付与日（current）と同じか（N165 3b。D5）
  /// 年・月・日で比べる。DB が未登録（null）なら false
  static bool isSavedFirstAccrualDateUnchanged({
    required DateTime expected,
    required DateTime? current,
  }) =>
      current != null && _isSameDate(expected, current);

  /// 保存済みの初回付与日（DB）の予定に、自動生成の付与を合わせ直す（N165 3b）
  /// 1 つの transaction の中で DB の初回付与日を読み直し、確認したときの日付（expectedFirstAccrualDate）と比べる
  /// - 違えば（未登録になったときも）何もせず、firstAccrualDateChanged: true を返す
  /// - 同じなら syncAccrualsWithSchedule で消して足し、実際に消した件数・足した件数を返す
  /// 持ち越し・入社日などの設定は書かない。失敗したら何も変えずに例外を上げる
  Future<({bool firstAccrualDateChanged, int deletedCount, int addedCount})>
      resyncAccrualsWithSavedSettings(String userId, DateTime expectedFirstAccrualDate) async {
    try {
      final db = await _dbHelper.database;
      final result = await db.transaction((txn) async {
        final current = await _queryFirstAccrualDate(txn, userId);
        if (!isSavedFirstAccrualDateUnchanged(expected: expectedFirstAccrualDate, current: current)) {
          debugPrint('⚠️ N165: 初回付与日が確認したとき（${_dateText(expectedFirstAccrualDate)}）から'
              ' ${current == null ? '未登録' : _dateText(current)} に変わったため、合わせ直しません');
          return (firstAccrualDateChanged: true, deletedCount: 0, addedCount: 0);
        }
        final synced = await syncAccrualsWithSchedule(txn, userId, expectedFirstAccrualDate);
        return (
          firstAccrualDateChanged: false,
          deletedCount: synced.deletedCount,
          addedCount: synced.addedCount,
        );
      });
      return result;
    } catch (e) {
      debugPrint('❌ N165: 保存済みの初回付与日への合わせ直しに失敗（何も変えていません）: $e');
      rethrow;
    }
  }
    /// ========== Week 16 修正版：来年度付与までに消滅する付与を取得 ==========
  /// 
  /// 返り値：来年度の付与日までに消滅する「1つの付与分」のデータ
  /// null の場合は消滅予定なし
  /// N118 3/4：読めなかったときは例外を上げる（「消滅予定なし」と分ける）
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
      rethrow;  // N118 3/4：「読めなかった」を「消滅予定なし」と分ける
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