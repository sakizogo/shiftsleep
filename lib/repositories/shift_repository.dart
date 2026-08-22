import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/database/database_helper.dart';
import 'package:shiftsleep/models/app_settings.dart';  // ← app_settings（アンダースコア）
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/models/calendar_event.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// シフトパターンのRepository
/// sqlfite を使用したパターン管理（CRUD操作）
class ShiftRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  static const String _tableName = 'shift_patterns';
  static const String _userId = 'test_user'; // 暫定：固定ユーザーID
  static const uuid = Uuid();

  /// 全パターンを取得
  Future<List<ShiftPatternModel>> getAllPatterns() async {
    try {
      final db = await _databaseHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        _tableName,
        where: 'user_id = ?',
        whereArgs: [_userId],
        orderBy: 'created_at ASC',
      );

      return List.generate(maps.length, (i) {
        return ShiftPatternModel(
          id: maps[i]['id'] as String,
          patternName: maps[i]['pattern_name'] as String,
          patternType: _stringToShiftType(maps[i]['pattern_type'] as String),
          startTime: maps[i]['start_time'] != null
              ? _parseTimeOfDay(maps[i]['start_time'] as String)
              : null,
          endTime: maps[i]['end_time'] != null
              ? _parseTimeOfDay(maps[i]['end_time'] as String)
              : null,
          colorIndex: maps[i]['color_index'] as int,
        );
      });
    } catch (e) {
      print('Error getting patterns: $e');
      return [];
    }
  }

  /// ========== Week 8 Phase 7 追加: pattern_id から ShiftPatternModel を取得 ==========
  /// パターンID で単一のシフトパターンを取得（settings_screen の起床時刻計算用）
  Future<ShiftPatternModel?> getPatternById(String patternId) async {
    try {
      final db = await _databaseHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        _tableName,
        where: 'id = ?',
        whereArgs: [patternId],
      );

      if (maps.isEmpty) {
        print('⚠️ Pattern not found: $patternId');
        return null;
      }

      final map = maps.first;
      return ShiftPatternModel(
        id: map['id'] as String,
        patternName: map['pattern_name'] as String,
        patternType: _stringToShiftType(map['pattern_type'] as String),
        startTime: map['start_time'] != null
            ? _parseTimeOfDay(map['start_time'] as String)
            : null,
        endTime: map['end_time'] != null
            ? _parseTimeOfDay(map['end_time'] as String)
            : null,
        colorIndex: map['color_index'] as int,
      );
    } catch (e) {
      print('❌ Error getting pattern by ID: $e');
      return null;
    }
  }
  // ===============================================================================

  /// パターンを作成（複数）
  Future<void> createPatterns(List<ShiftPatternModel> patterns) async {
    try {
      for (final pattern in patterns) {
        await createPattern(pattern);
      }
    } catch (e) {
      print('Error creating patterns: $e');
    }
  }

  /// パターンを作成（単数）
  Future<void> createPattern(ShiftPatternModel pattern) async {
    try {
      final db = await _databaseHelper.database;
      final now = DateTime.now().toIso8601String();

      await db.insert(
        _tableName,
        {
          'id': pattern.id,
          'user_id': _userId,
          'pattern_name': pattern.patternName,
          'pattern_type': _shiftTypeToString(pattern.patternType),
          'start_time': pattern.startTime != null
              ? '${pattern.startTime!.hour.toString().padLeft(2, '0')}:${pattern.startTime!.minute.toString().padLeft(2, '0')}'
              : null,
          'end_time': pattern.endTime != null
              ? '${pattern.endTime!.hour.toString().padLeft(2, '0')}:${pattern.endTime!.minute.toString().padLeft(2, '0')}'
              : null,
          'color_index': pattern.colorIndex,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('Pattern created: ${pattern.patternName}');
    } catch (e) {
      print('Error creating pattern: $e');
    }
  }

  /// パターンを削除
  Future<void> deletePattern(String patternId) async {
    try {
      final db = await _databaseHelper.database;
      await db.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: [patternId],
      );

      print('Pattern deleted: $patternId');
    } catch (e) {
      print('Error deleting pattern: $e');
    }
  }

  // ========== Week 3 Day 5 追加: Shifts テーブル操作メソッド ==========

  /// シフトを作成（単数）
  Future<void> createShift(DateTime date, ShiftPatternModel pattern) async {
    try {
      final db = await _databaseHelper.database;
      
      // 日付を正規化（時刻なし）
      final normalized = DateTime(date.year, date.month, date.day);
      final dateStr = normalized.toIso8601String().split('T').first;  // 2026-08-06 形式
      final now = DateTime.now().toIso8601String();  // ← 新規追加
      
      print('💾 createShift() - 保存: $dateStr / pattern_id=${pattern.id}');
      
      await db.insert(
        'shifts',
        {
          'shift_date': dateStr,
          'pattern_id': pattern.id,
          'user_id': _userId,
          'created_at': now,  // ← 新規追加
          'updated_at': now,  // ← 新規追加
        },
        conflictAlgorithm: ConflictAlgorithm.replace,  // 同じ日付なら上書き
      );
      
      print('✅ createShift() 完了: $dateStr');
    } catch (e) {
      print('❌ Error creating shift: $e');
    }
  }

  /// シフトを作成（複数）
  Future<void> createShifts(
      Map<DateTime, ShiftPatternModel?> shiftMap) async {
    try {
      for (final entry in shiftMap.entries) {
        if (entry.value != null) {
          await createShift(entry.key, entry.value!);
        }
      }
      print('Created ${shiftMap.length} shifts');
    } catch (e) {
      print('Error creating shifts: $e');
    }
  }

  /// シフトを削除
  Future<void> deleteShift(DateTime shiftDate) async {
    try {
      final db = await _databaseHelper.database;
      final normalized = DateTime(shiftDate.year, shiftDate.month, shiftDate.day);
      final dateStr = normalized.toIso8601String().split('T').first;

      await db.delete(
        'shifts',
        where: 'user_id = ? AND shift_date = ?',
        whereArgs: [_userId, dateStr],
      );

      print('Shift deleted: $dateStr');
    } catch (e) {
      print('Error deleting shift: $e');
    }
  }

  /// 全シフトを削除
  Future<void> deleteAllShifts() async {
    try {
      final db = await _databaseHelper.database;
      await db.delete('shifts');
      print('🗑️ 全シフトを削除完了');
    } catch (e) {
      print('Error deleting all shifts: $e');
    }
  }

  /// 期間内のシフトを取得
  Future<List<Map<String, dynamic>>> getShiftsForDateRange(
      DateTime startDate, DateTime endDate) async {
    try {
      print('🔍 getShiftsForDateRange() - 検索範囲: ${startDate.toIso8601String()} ～ ${endDate.toIso8601String()}');
    
      final db = await _databaseHelper.database;
    
      // 日付部分だけを取得（時刻なし）
      final startDateStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
      final endDateStr = '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';
    
      print('📅 日付範囲（フォーマット後）: $startDateStr ～ $endDateStr');
    
      // SQL クエリで日付を比較（shifts テーブルから）
      final results = await db.query(
        'shifts',
        where: 'user_id = ? AND shift_date >= ? AND shift_date <= ?',
        whereArgs: [_userId, startDateStr, endDateStr],
      );
    
      print('📊 検索結果: ${results.length}件');
      for (final result in results) {
        print('  - ${result['shift_date']}: pattern_id=${result['pattern_id']}');
      }
    
      return results;
    } catch (e) {
      print('❌ Error getting shifts for date range: $e');
      return [];
    }
  }

  // ========== Week 3 Day 8 追加: CalendarEvents テーブル操作メソッド ==========

  /// イベントを作成（単数）
  Future<void> createCalendarEvent(
    DateTime date,
    String eventType,
    String eventEmoji, {
    String? eventName,
    String? notes,
  }) async {
    try {
      final db = await _databaseHelper.database;

      // 日付を正規化（時刻なし）
      final normalized = DateTime(date.year, date.month, date.day);
      final dateStr = normalized.toIso8601String().split('T').first; // 2026-08-06 形式
      final now = DateTime.now().toIso8601String();
      final eventId = uuid.v4();

      print('💾 createCalendarEvent() - 保存: $dateStr / type=$eventType / emoji=$eventEmoji');

      await db.insert(
        'calendar_events',
        {
          'id': eventId,
          'user_id': _userId,
          'event_date': dateStr,
          'event_type': eventType,
          'event_emoji': eventEmoji,
          'event_name': eventName,
          'notes': notes,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('✅ createCalendarEvent() 完了: $dateStr');
    } catch (e) {
      print('❌ Error creating calendar event: $e');
    }
  }

  /// イベントを削除
  Future<void> deleteCalendarEvent(String eventId) async {
    try {
      final db = await _databaseHelper.database;

      await db.delete(
        'calendar_events',
        where: 'id = ?',
        whereArgs: [eventId],
      );

      print('✅ Calendar event deleted: $eventId');
    } catch (e) {
      print('❌ Error deleting calendar event: $e');
    }
  }

  /// 特定の日付のイベントを削除
  Future<void> deleteCalendarEventByDate(DateTime date) async {
    try {
      final db = await _databaseHelper.database;
      final normalized = DateTime(date.year, date.month, date.day);
      final dateStr = normalized.toIso8601String().split('T').first;

      await db.delete(
        'calendar_events',
        where: 'user_id = ? AND event_date = ?',
        whereArgs: [_userId, dateStr],
      );

      print('✅ Calendar events deleted for date: $dateStr');
    } catch (e) {
      print('❌ Error deleting calendar events for date: $e');
    }
  }

  /// 期間内のイベントを取得
  Future<List<CalendarEvent>> getCalendarEventsForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      print('🔍 getCalendarEventsForDateRange() - 検索範囲: ${startDate.toIso8601String()} ～ ${endDate.toIso8601String()}');

      final db = await _databaseHelper.database;

      // 日付部分だけを取得（時刻なし）
      final startDateStr =
          '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
      final endDateStr =
          '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';

      print('📅 日付範囲（フォーマット後）: $startDateStr ～ $endDateStr');

      // SQL クエリで日付を比較（calendar_events テーブルから）
      final results = await db.query(
        'calendar_events',
        where: 'user_id = ? AND event_date >= ? AND event_date <= ?',
        whereArgs: [_userId, startDateStr, endDateStr],
        orderBy: 'event_date ASC',
      );

      print('📊 検索結果: ${results.length}件');
      for (final result in results) {
        print('  - ${result['event_date']}: ${result['event_emoji']} ${result['event_type']}');
      }

      return results.map((map) => CalendarEvent.fromMap(map)).toList();
    } catch (e) {
      print('❌ Error getting calendar events for date range: $e');
      return [];
    }
  }

  /// 全イベントを取得
  Future<List<CalendarEvent>> getAllCalendarEvents() async {
    try {
      final db = await _databaseHelper.database;
      final results = await db.query(
        'calendar_events',
        where: 'user_id = ?',
        whereArgs: [_userId],
        orderBy: 'event_date ASC',
      );

      print('📊 All calendar events: ${results.length}件');
      return results.map((map) => CalendarEvent.fromMap(map)).toList();
    } catch (e) {
      print('❌ Error getting all calendar events: $e');
      return [];
    }
  }

  // ========================================================================

  /// ============ Helper Methods ============

  /// 文字列を ShiftType に変換
  ShiftType _stringToShiftType(String type) {
    switch (type.toLowerCase()) {
      case 'dayoff':
        return ShiftType.dayOff;
      case 'work':
      default:
        return ShiftType.work;
    }
  }

  /// ShiftType を文字列に変換
  String _shiftTypeToString(ShiftType type) {
    switch (type) {
      case ShiftType.dayOff:
        return 'dayOff';
      case ShiftType.work:
      default:
        return 'work';
    }
  }

  /// 文字列を TimeOfDay に変換
  /// 形式: "HH:mm"
  TimeOfDay _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }
  /// ========== Week 4 Day 1 追加: app_settings テーブル操作メソッド ==========

  /// 設定を取得
  Future<AppSettings?> gety(String userId) async {
    try {
      final db = await _databaseHelper.database;
      final results = await db.query(
        'app_settings',
        where: 'user_id = ?',
        whereArgs: [userId],
      );

      if (results.isEmpty) {
        print('⚠️ No app settings found for user: $userId');
        return null;
      }

      return AppSettings.fromMap(results.first);
    } catch (e) {
      print('❌ Error getting app settings: $e');
      return null;
    }
  }

  /// 設定を作成または更新
  Future<void> createOrUpdateAppSettings(AppSettings settings) async {
    try {
      final db = await _databaseHelper.database;
      final now = DateTime.now().toIso8601String();

      // AppSettings の toMap() を使用
      final map = settings.toMap();
      map.remove('id');
      map['updated_at'] = now;
      map['name'] = null;
      map['age'] = null;
      map['gender'] = null;
      map['shift_pattern'] = null;
      map['language'] = 'ja';

      await db.insert(
        'app_settings',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('✅ App settings saved: ${settings.userId}');
    } catch (e) {
      print('❌ Error saving app settings: $e');
    }
  }

  /// アラーム時間だけを更新
  Future<void> updateAlarmTimeBeforeShift(String userId, int minutes) async {
    try {
      final db = await _databaseHelper.database;
      final now = DateTime.now().toIso8601String();

      await db.update(
        'app_settings',
        {
          'alarm_time_before_shift': minutes,
          'updated_at': now,
        },
        where: 'user_id = ?',
        whereArgs: [userId],
      );

      print('✅ Alarm time updated: $userId → ${minutes}分前');
    } catch (e) {
      print('❌ Error updating alarm time: $e');
    }
  }

  /// ================================================================
  /// AppSettings を取得
  Future<AppSettings?> getAppSettings(String userId) async {
    try {
      final db = await _databaseHelper.database;
      final results = await db.query(
        'app_settings',
        where: 'user_id = ?',
        whereArgs: [userId],
      );

      if (results.isEmpty) {
        print('⚠️ No app settings found for user: $userId');
        return null;
      }

      return AppSettings.fromMap(results.first);
    } catch (e) {
      print('✗ Error getting app settings: $e');
      return null;
    }
  }
}