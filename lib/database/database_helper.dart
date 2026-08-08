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
      version: 3,  // ========== Week 3 Day 6-2 修正: version を 3 に上げる ==========
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

    // app_settings テーブル
    await db.execute('''
      CREATE TABLE app_settings (
        user_id TEXT PRIMARY KEY,
        name TEXT,
        age INTEGER,
        gender TEXT,
        shift_pattern TEXT,
        language TEXT DEFAULT 'ja',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

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
  }

  // Close database
  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}