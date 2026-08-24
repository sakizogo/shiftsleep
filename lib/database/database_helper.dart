import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initializeDatabase();
    return _database!;
  }

  Future<Database> _initializeDatabase() async {
    final String path = join(
      await getDatabasesPath(),
      'shiftsleep.db',
    );

    return await openDatabase(
      path,
      version: 15,  // v15 に更新
      onCreate: _createTables,
      onUpgrade: (db, oldVersion, newVersion) async {
        // ========== Week 3 Day 6-2 修正: shift_patterns テーブル + shifts テーブルの pattern_id カラム追加 ==========

        // バージョン 2 → 3 への更新：shifts テーブルに pattern_id カラムを追加
        if (oldVersion < 3) {
          print('🔧 Database upgrade: v$oldVersion → v$newVersion');

          // shift_patterns テーブルの作成（v2で追加されていなかった場合）
          await db.execute('''
            CREATE TABLE IF NOT EXISTS shift_patterns (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              pattern_name TEXT NOT NULL,
              pattern_type TEXT NOT NULL,
              start_time TEXT,
              end_time TEXT,
              color_index INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');

          // shifts テーブルを新しいスキーマに移行
          // 古いテーブルをリネーム
          await db.execute('ALTER TABLE shifts RENAME TO shifts_old');

          // 新しいスキーマで shifts テーブルを再作成
          await db.execute('''
            CREATE TABLE shifts (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              shift_date TEXT NOT NULL,
              pattern_id TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');

          print('✅ Database upgrade complete: shifts table migrated to new schema');
        }
        // ========================================================================

        // ========== Week 3 Day 8 追加: calendar_events テーブル ==========
        // バージョン 3 → 4 への更新：calendar_events テーブルを追加
        if (oldVersion < 4) {
          print('🔧 Database upgrade: v$oldVersion → v$newVersion');

          await db.execute('''
            CREATE TABLE calendar_events (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              event_date TEXT NOT NULL,
              event_type TEXT NOT NULL,
              event_emoji TEXT NOT NULL,
              event_name TEXT,
              notes TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');

          print('✅ Database upgrade complete: calendar_events table created');
        }
        
        // ================================================================

        // ========== Week 5 Day 2 追加: app_settings テーブルに wake_up_time カラムを追加 ==========
        // バージョン 5 → 6 への更新：app_settings テーブルに起床時刻カラムを追加
        if (oldVersion < 6) {
          print('🔧 Database upgrade: v$oldVersion → v$newVersion');

          try {
            await db.execute('''
              ALTER TABLE app_settings 
              ADD COLUMN wake_up_time TEXT
            ''');
    
            // 既存行に default 値を設定
            await db.execute('''
              UPDATE app_settings 
              SET wake_up_time = '07:00' 
              WHERE wake_up_time IS NULL
            ''');
    
            print('✅ Database upgrade complete: app_settings table updated with wake_up_time column');
          } catch (e) {
            print('⚠️ Column might already exist: $e');
          }
        }
        // ========== Week 5 Day 3 追加: app_settings テーブルに selected_alarm_sound カラムを追加 ==========
        // バージョン 6 → 7 への更新：app_settings テーブルにアラーム音選択カラムを追加
        if (oldVersion < 7) {
          print('🔧 Database upgrade: v$oldVersion → v$newVersion');

          try {
            await db.execute('''
              ALTER TABLE app_settings 
              ADD COLUMN selected_alarm_sound TEXT DEFAULT 'default'
            ''');
    
            print('✅ Database upgrade complete: app_settings table updated with selected_alarm_sound column');
          } catch (e) {
            print('⚠️ Column might already exist: $e');
          }
        }
        
        // ========== Week 7 A 追加: sleep_records テーブルに sleep_role カラムを追加 ==========
        // バージョン 7 → 8 への更新：sleep_records テーブルに睡眠の質的役割カラムを追加
        if (oldVersion < 8) {
          print('🔧 Database upgrade: v$oldVersion → v$newVersion');

          try {
            await db.execute('''
              ALTER TABLE sleep_records 
              ADD COLUMN sleep_role TEXT DEFAULT 'primary'
            ''');
    
            // 既存の sleep_records を duration_minutes から自動判定して sleep_role を設定
            // 5時間以上 → primary, 30分～5時間 → supplementary, 30分未満 → split_segment
            await db.execute('''
              UPDATE sleep_records 
              SET sleep_role = CASE
                WHEN duration_minutes >= 300 THEN 'primary'
                WHEN duration_minutes >= 30 THEN 'supplementary'
                ELSE 'split_segment'
              END
              WHERE sleep_role IS NULL OR sleep_role = 'primary'
            ''');
    
            print('✅ Database upgrade complete: sleep_records table updated with sleep_role column');
          } catch (e) {
            print('⚠️ Column might already exist or other error: $e');
          }
        }
        // ========== Week 7 Phase 2 追加: app_settings テーブルに advice_promo_visible カラムを追加 ==========
        // バージョン 8 → 9 への更新：app_settings テーブルにプロモーション表示フラグを追加
        if (oldVersion < 9) {
          print('🔧 Database upgrade: v$oldVersion → v$newVersion');

          try {
            await db.execute('''
              ALTER TABLE app_settings 
              ADD COLUMN advice_promo_visible INTEGER DEFAULT 1
            ''');
    
            print('✅ Database upgrade complete: app_settings table updated with advice_promo_visible column');
          } catch (e) {
            print('⚠️ Column might already exist: $e');
          }
        }
        
        // ========== Week 7 Phase 3 追加: app_settings テーブルに is_premium_user カラムを追加 ==========
        // バージョン 9 → 10 への更新：app_settings テーブルに有料ユーザーフラグを追加
        if (oldVersion < 10) {
          print('🔧 Database upgrade: v$oldVersion → v$newVersion');

          try {
            await db.execute('''
              ALTER TABLE app_settings 
              ADD COLUMN is_premium_user INTEGER DEFAULT 0
            ''');
    
            print('✅ Database upgrade complete: app_settings table updated with is_premium_user column');
          } catch (e) {
            print('⚠️ Column might already exist: $e');
          }
        }
        // ====================================================================
                
        // ========== Week 11: vacation_settings & vacation_usage テーブル追加 ==========
        if (oldVersion < 11) {
          print('🔧 Database upgrade: v$oldVersion → v$newVersion');
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS vacation_settings (
                user_id TEXT PRIMARY KEY,
                hired_date TEXT NOT NULL,
                annual_days INTEGER NOT NULL,
                manual_override INTEGER DEFAULT 0,
                last_calculation_date TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS vacation_usage (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                usage_date TEXT NOT NULL,
                days_used REAL NOT NULL,
                reason TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_vacation_usage_user_date
              ON vacation_usage(user_id, usage_date)
            ''');
            print('✅ Database upgrade complete: vacation_settings & vacation_usage tables created');
          } catch (e) {
            print('⚠️ Failed to create vacation tables: $e');
          }
        }
        // ========================================================================

        // ========== Week 12: vacation_accruals テーブル追加 ==========
        // バージョン 11 → 12 への更新：有給付与履歴管理テーブルを追加
        if (oldVersion < 12) {
          print('🔧 Database upgrade: v$oldVersion → v$newVersion');
          try {
            // 有給付与履歴テーブル（6ヶ月ごとの付与を記録）
            await db.execute('''
              CREATE TABLE IF NOT EXISTS vacation_accruals (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                accrual_date TEXT NOT NULL,
                days_granted INTEGER NOT NULL,
                expiry_date TEXT NOT NULL,
                notes TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
            
            // クエリ高速化用インデックス
            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_vacation_accruals_user_expiry
              ON vacation_accruals(user_id, expiry_date)
            ''');
            
            print('✅ Database upgrade complete: vacation_accruals table created');
          } catch (e) {
            print('⚠️ Failed to create vacation_accruals table: $e');
          }
        }

        // ========== Week 13追加: v14 へのマイグレーション（持ち越し有休数を DB保存） ==========
        if (oldVersion < 14) {
          try {
            print('🔧 Database upgrade: v13 → v14');

            // app_settings テーブルに carried_over_days カラムを追加
            await db.execute('''
              ALTER TABLE app_settings ADD COLUMN carried_over_days INTEGER DEFAULT 0
            ''');
            print('✅ Added carried_over_days to app_settings');

            print('✅ Database upgrade complete: v14 migration done');
          } catch (e) {
            print('⚠️ Failed to upgrade to v14: $e');
          }
        }
        // ===============================================================================
        // ========== Week 14: vacation_accruals に is_carried_over カラムを追加 ==========
        if (oldVersion < 15) {
          // vacation_accruals テーブルに is_carried_over カラムを追加
          try {
            await db.execute('''
              ALTER TABLE vacation_accruals
              ADD COLUMN is_carried_over INTEGER DEFAULT 0
            ''');
            print('✅ DB v15 Migration: Added is_carried_over column to vacation_accruals');
          } catch (e) {
            // カラムが既に存在する場合はエラーを無視
            print('⚠️ is_carried_over column may already exist: $e');
          }
        }
        // ========================================================================
      },
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // ========== Week 7 A 修正: sleep_records テーブルに sleep_role カラムを追加 ==========
    // sleep_records テーブル
    await db.execute('''
      CREATE TABLE sleep_records (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        sleep_date TEXT NOT NULL,
        sleep_start_time TEXT NOT NULL,
        sleep_start_auto INTEGER NOT NULL,
        sleep_end_time TEXT NOT NULL,
        sleep_end_auto INTEGER NOT NULL,
        wake_up_type TEXT NOT NULL,
        duration_minutes INTEGER NOT NULL,
        modified_count INTEGER NOT NULL DEFAULT 0,
        last_modified_at TEXT NOT NULL,
        can_edit_until TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sleep_role TEXT DEFAULT 'primary'
      )
    ''');
    // ========== Week 7 A 修正 完了 ==========
    
    // ========== shift_patterns テーブル（追加） ==========
    await db.execute('''
      CREATE TABLE shift_patterns (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        pattern_name TEXT NOT NULL,
        pattern_type TEXT NOT NULL,
        start_time TEXT,
        end_time TEXT,
        color_index INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // ========== Week 14 追加：デフォルトシフトパターンを挿入 ==========
    // 初回生成時に「休日」「有休」「半休」をデフォルトパターンとして追加
    try {
      final now = DateTime.now().toIso8601String();
      
      await db.execute('''
        INSERT INTO shift_patterns 
          (id, user_id, pattern_name, pattern_type, start_time, end_time, color_index, created_at, updated_at)
        VALUES
          ('default_off_day', 'default_user', '休日', 'off_day', NULL, NULL, 2, '$now', '$now'),
          ('default_vacation_1day', 'default_user', '有休', 'vacation', NULL, NULL, 3, '$now', '$now'),
          ('default_vacation_half', 'default_user', '半休', 'half_vacation', NULL, NULL, 4, '$now', '$now')
      ''');
      print('✅ Default shift patterns inserted (off_day, vacation, half_vacation)');
    } catch (e) {
      print('⚠️ Default patterns might already exist: $e');
    }
    // ========================================================================

    // ================================================
    // shifts テーブル - Week 3 Day 6-2 版（pattern_id を使用）
    await db.execute('''
      CREATE TABLE shifts (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        shift_date TEXT NOT NULL,
        pattern_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // ========== Week 7 Phase 3 修正: app_settings テーブルに is_premium_user カラム追加 ==========
    // アラーム時間カスタマイズに対応（alarm_time_before_shift カラム追加）
    await db.execute('''
      CREATE TABLE app_settings (
        user_id TEXT PRIMARY KEY,
        name TEXT,
        age INTEGER,
        gender TEXT,
        shift_pattern TEXT,
        language TEXT DEFAULT 'ja',
        alarm_time_before_shift INTEGER NOT NULL DEFAULT 30,
        wake_up_time TEXT DEFAULT '07:00',
        selected_alarm_sound TEXT DEFAULT 'default',
        advice_promo_visible INTEGER DEFAULT 1,
        is_premium_user INTEGER DEFAULT 0,
        carried_over_days INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    // ===================================================================

    // alarm_configs テーブル
    await db.execute('''
      CREATE TABLE alarm_configs (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL,
        alarmMode TEXT NOT NULL,
        alarmSound TEXT NOT NULL,
        volume INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    // ========== Week 3 Day 8 追加: calendar_events テーブル ==========
    // カレンダーイベント（給料日、ボーナス、慰安旅行など）
    await db.execute('''
      CREATE TABLE calendar_events (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        event_date TEXT NOT NULL,
        event_type TEXT NOT NULL,
        event_emoji TEXT NOT NULL,
        event_name TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    // ================================================================

    
    // ========== Week 11: vacation_settings & vacation_usage テーブル追加 ==========
    await db.execute('''
      CREATE TABLE vacation_settings (
        user_id TEXT PRIMARY KEY,
        hired_date TEXT NOT NULL,
        annual_days INTEGER NOT NULL,
        manual_override INTEGER DEFAULT 0,
        last_calculation_date TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE vacation_usage (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        usage_date TEXT NOT NULL,
        days_used REAL NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_vacation_usage_user_date
      ON vacation_usage(user_id, usage_date)
    ''');
    // ========================================================================

    // ========== Week 12: vacation_accruals テーブル追加 ==========
    // 有給付与履歴（6ヶ月ごとの付与を記録）
    await db.execute('''
      CREATE TABLE vacation_accruals (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        accrual_date TEXT NOT NULL,
        days_granted INTEGER NOT NULL,
        expiry_date TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    
    // クエリ高速化用インデックス
    await db.execute('''
      CREATE INDEX idx_vacation_accruals_user_expiry
      ON vacation_accruals(user_id, expiry_date)
    ''');
    // ========================================================================


  }

  // Close database
  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}