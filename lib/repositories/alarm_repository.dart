// lib/repositories/alarm_repository.dart
import 'package:sqflite/sqflite.dart';
import 'package:shiftsleep/models/alarm_config.dart';
import 'package:shiftsleep/database/database_helper.dart';

/// アラーム設定を DB で管理する Repository クラス
/// CRUD 操作と各種ユーティリティメソッドを提供
class AlarmRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// アラーム設定を DB に保存（新規作成）
  Future<void> insertAlarmConfig(AlarmConfig config) async {
    try {
      final db = await _dbHelper.database;
      await db.insert(
        'alarm_configs',
        config.toMap(),
        conflictAlgorithm: ConflictAlgorithm.fail,
      );
      print('[AlarmRepository] ✅ insertAlarmConfig: ${config.id}');
    } catch (e) {
      print('[AlarmRepository] ❌ insertAlarmConfig error: $e');
      rethrow;
    }
  }

  Future<AlarmConfig?> getAlarmConfigByUserId(String userId) async {
    try {
      final db = await _dbHelper.database;
      final result = await db.query(
        'alarm_configs',
        where: 'userId = ?',
        whereArgs: [userId],
        limit: 1,
      );

      if (result.isEmpty) {
        print('[AlarmRepository] ℹ️ getAlarmConfigByUserId: No record found for $userId');
        return null;
      }

      final config = AlarmConfig.fromMap(result.first);
      print('[AlarmRepository] ✅ getAlarmConfigByUserId: ${config.id}');
      return config;
    } catch (e) {
      print('[AlarmRepository] ❌ getAlarmConfigByUserId error: $e');
      rethrow;
    }
  }

  Future<List<AlarmConfig>> getAllAlarmConfigs() async {
    try {
      final db = await _dbHelper.database;
      final result = await db.query('alarm_configs');

      final configs = result.map((map) => AlarmConfig.fromMap(map)).toList();
      print('[AlarmRepository] ✅ getAllAlarmConfigs: ${configs.length} records');
      return configs;
    } catch (e) {
      print('[AlarmRepository] ❌ getAllAlarmConfigs error: $e');
      rethrow;
    }
  }

  Future<void> updateAlarmConfig(AlarmConfig config) async {
    try {
      final db = await _dbHelper.database;
      final result = await db.update(
        'alarm_configs',
        config.toMap(),
        where: 'id = ?',
        whereArgs: [config.id],
      );

      if (result == 0) {
        print('[AlarmRepository] ⚠️ updateAlarmConfig: No record found with id ${config.id}');
        return;
      }

      print('[AlarmRepository] ✅ updateAlarmConfig: ${config.id}');
    } catch (e) {
      print('[AlarmRepository] ❌ updateAlarmConfig error: $e');
      rethrow;
    }
  }

  Future<void> deleteAlarmConfig(String id) async {
    try {
      final db = await _dbHelper.database;
      final result = await db.delete(
        'alarm_configs',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (result == 0) {
        print('[AlarmRepository] ⚠️ deleteAlarmConfig: No record found with id $id');
        return;
      }

      print('[AlarmRepository] ✅ deleteAlarmConfig: $id');
    } catch (e) {
      print('[AlarmRepository] ❌ deleteAlarmConfig error: $e');
      rethrow;
    }
  }

  Future<bool> hasAlarmConfigForUser(String userId) async {
    try {
      final config = await getAlarmConfigByUserId(userId);
      return config != null;
    } catch (e) {
      print('[AlarmRepository] ❌ hasAlarmConfigForUser error: $e');
      return false;
    }
  }

  Future<void> resetAlarmConfigForUser(String userId) async {
    try {
      final db = await _dbHelper.database;
      await db.delete(
        'alarm_configs',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      print('[AlarmRepository] ✅ resetAlarmConfigForUser: $userId');
    } catch (e) {
      print('[AlarmRepository] ❌ resetAlarmConfigForUser error: $e');
      rethrow;
    }
  }
}