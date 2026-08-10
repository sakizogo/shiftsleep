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
      version: 5,  // ========== Week 4 Day 1 追加: version を 5 に上げる（アラーム時間カスタマイズ）==========
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

        // ========== Week 4 Day 1 追加: app_settings テーブルに alarm_time_before_shift カラムを追加 ==========
        // バージョン 4 → 5 への更新：app_settings テーブルにアラーム時間設定カラムを追加
        if (oldVersion < 5) {
          print('🔧 Database upgrade: v$oldVersion → v$newVersion');

          // 既存の app_settings テーブルに alarm_time_before_shift カラムを追加
          // デフォルト値：30分（出勤30分前にアラーム）
          await db.execute('''
            ALTER TABLE app_settings 
            ADD COLUMN alarm_time_before_shift INTEGER NOT NULL DEFAULT 30
          ''');

          print('✅ Database upgrade complete: app_settings table updated with alarm_time_before_shift column');
        }
        // ====================================================================
      },
    );
  }

  Future<void> _createTables(Database db, int version) async {
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
        updated_at TEXT NOT NULL
      )
    ''');

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

    // ========== Week 4 Day 1 更新: app_settings テーブル ==========
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

    // ========== Week 3 Day 5 追加: shift_patterns テーブル ==========
    // シフトパターン定義を管理するテーブル
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
    // ========================================================================

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
  }

  // Close database
  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
