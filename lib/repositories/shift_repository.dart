import 'package:sqflite/sqflite.dart';
import 'package:flutter/material.dart';
import 'package:shiftsleep/database/database_helper.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/constants/shift_enums.dart';

/// シフトパターンのRepository
/// sqlfite を使用したパターン管理（CRUD操作）
class ShiftRepository {
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  static const String _tableName = 'shift_patterns';
  static const String _userId = 'test_user'; // 暫定：固定ユーザーID

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

  /// パターンをIDで取得
  Future<ShiftPatternModel?> getPatternById(String id) async {
    try {
      final db = await _databaseHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        _tableName,
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, _userId],
      );

      if (maps.isEmpty) return null;

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
      print('Error getting pattern: $e');
      return null;
    }
  }

  /// パターンを作成
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
          'pattern_type': pattern.patternType.toString().split('.').last,
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

  /// パターンを更新
  Future<void> updatePattern(ShiftPatternModel pattern) async {
    try {
      final db = await _databaseHelper.database;
      final now = DateTime.now().toIso8601String();

      await db.update(
        _tableName,
        {
          'pattern_name': pattern.patternName,
          'pattern_type': pattern.patternType.toString().split('.').last,
          'start_time': pattern.startTime != null
              ? '${pattern.startTime!.hour.toString().padLeft(2, '0')}:${pattern.startTime!.minute.toString().padLeft(2, '0')}'
              : null,
          'end_time': pattern.endTime != null
              ? '${pattern.endTime!.hour.toString().padLeft(2, '0')}:${pattern.endTime!.minute.toString().padLeft(2, '0')}'
              : null,
          'color_index': pattern.colorIndex,
          'updated_at': now,
        },
        where: 'id = ? AND user_id = ?',
        whereArgs: [pattern.id, _userId],
      );

      print('Pattern updated: ${pattern.patternName}');
    } catch (e) {
      print('Error updating pattern: $e');
    }
  }

  /// パターンを削除
  Future<void> deletePattern(String id) async {
    try {
      final db = await _databaseHelper.database;

      await db.delete(
        _tableName,
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, _userId],
      );

      print('Pattern deleted: $id');
    } catch (e) {
      print('Error deleting pattern: $e');
    }
  }

  /// 複数パターンを一括作成
  Future<void> createPatterns(List<ShiftPatternModel> patterns) async {
    try {
      for (final pattern in patterns) {
        await createPattern(pattern);
      }
    } catch (e) {
      print('Error creating patterns: $e');
    }
  }

  /// ========== Week 3 Day 5 追加: Shifts テーブル操作メソッド ==========

  /// シフトを作成
  Future<void> createShift(DateTime shiftDate, ShiftPatternModel pattern) async {
    try {
      final db = await _databaseHelper.database;
      final now = DateTime.now().toIso8601String();
      final normalized = DateTime(shiftDate.year, shiftDate.month, shiftDate.day);
      final dateStr = normalized.toIso8601String().split('T').first;

      await db.insert(
        'shifts',
        {
          'id': '${_userId}_${dateStr}_${DateTime.now().millisecondsSinceEpoch}',
          'user_id': _userId,
          'shift_date': dateStr,
          'pattern_id': pattern.id,
          'notes': '',
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('Shift created: $dateStr');
    } catch (e) {
      print('Error creating shift: $e');
    }
  }

  /// 複数のシフトを一括作成
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

  /// 期間内のシフトを取得
  Future<List<Map<String, dynamic>>> getShiftsForDateRange(
      DateTime startDate, DateTime endDate) async {
    try {
      final db = await _databaseHelper.database;
      final startStr = startDate.toIso8601String().split('T').first;
      final endStr = endDate.toIso8601String().split('T').first;

      final List<Map<String, dynamic>> shifts = await db.query(
        'shifts',
        where: 'user_id = ? AND shift_date >= ? AND shift_date <= ?',
        whereArgs: [_userId, startStr, endStr],
        orderBy: 'shift_date ASC',
      );

      return shifts;
    } catch (e) {
      print('Error getting shifts: $e');
      return [];
    }
  }

  /// ===================================================================

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

  /// 文字列を TimeOfDay に変換
  /// 形式: "HH:mm"
  TimeOfDay _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }
}