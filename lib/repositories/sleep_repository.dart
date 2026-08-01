import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/sleep_record.dart';

class SleepRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Insert a new sleep record
  Future<void> insertSleepRecord(SleepRecord record) async {
    final Database db = await _dbHelper.database;
    await db.insert(
      'sleep_records',
      record.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Get a sleep record by ID
  Future<SleepRecord?> getSleepRecordById(String id) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> result = await db.query(
      'sleep_records',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isEmpty) {
      return null;
    }

    return SleepRecord.fromJson(result.first);
  }

  // Get all sleep records for a user
  Future<List<SleepRecord>> getSleepRecordsByUserId(String userId) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> result = await db.query(
      'sleep_records',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'sleep_date DESC',
    );

    return result.map((json) => SleepRecord.fromJson(json)).toList();
  }

  // Get sleep records for a date range
  Future<List<SleepRecord>> getSleepRecordsByDateRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> result = await db.query(
      'sleep_records',
      where: 'user_id = ? AND sleep_date >= ? AND sleep_date <= ?',
      whereArgs: [
        userId,
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'sleep_date DESC',
    );

    return result.map((json) => SleepRecord.fromJson(json)).toList();
  }

  // Update a sleep record
  Future<void> updateSleepRecord(SleepRecord record) async {
    final Database db = await _dbHelper.database;
    await db.update(
      'sleep_records',
      record.toJson(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  // Delete a sleep record
  Future<void> deleteSleepRecord(String id) async {
    final Database db = await _dbHelper.database;
    await db.delete(
      'sleep_records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Get latest sleep record for a user
  Future<SleepRecord?> getLatestSleepRecord(String userId) async {
    final Database db = await _dbHelper.database;
    final List<Map<String, dynamic>> result = await db.query(
      'sleep_records',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'sleep_date DESC',
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return SleepRecord.fromJson(result.first);
  }

  // Get sleep records for today
  Future<List<SleepRecord>> getSleepRecordsForToday(String userId) async {
    final DateTime now = DateTime.now();
    final DateTime startOfDay = DateTime(now.year, now.month, now.day);
    final DateTime endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return getSleepRecordsByDateRange(userId, startOfDay, endOfDay);
  }

  // Calculate total sleep duration for a date
  Future<int> getTotalSleepDurationForDate(String userId, DateTime date) async {
    final List<SleepRecord> records = await getSleepRecordsByDateRange(
      userId,
      DateTime(date.year, date.month, date.day),
      DateTime(date.year, date.month, date.day, 23, 59, 59),
    );

    int totalMinutes = 0;
    for (final record in records) {
      totalMinutes += record.durationMinutes;
    }
    return totalMinutes;
  }

  // Check if record is still editable
  bool isRecordEditable(SleepRecord record) {
    return DateTime.now().isBefore(record.canEditUntil);
  }

  // Get edit remaining time (in hours)
  int getEditRemainingHours(SleepRecord record) {
    final Duration difference = record.canEditUntil.difference(DateTime.now());
    return difference.inHours;
  }
}