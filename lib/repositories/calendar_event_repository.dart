import 'package:shiftsleep/models/calendar_event.dart';
import 'package:shiftsleep/database/database_helper.dart';

class CalendarEventRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<void> deleteCalendarEvent(String eventId) async {
    try {
      final db = await _dbHelper.database;
      await db.delete(
        'calendar_events',
        where: 'id = ?',
        whereArgs: [eventId],
      );
      print('[CalendarEventRepository] ✅ イベント削除完了: ID=$eventId');
    } catch (e) {
      print('[CalendarEventRepository] ❌ イベント削除エラー: $e');
      rethrow;
    }
  }

  // ========== Week 21：日付別イベント取得 ==========
  Future<List<CalendarEvent>> getEventsByDate(String userId, DateTime date) async {
    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'calendar_events',
        where: 'user_id = ? AND DATE(event_date) = DATE(?)',
        whereArgs: [userId, date.toString()],
      );
      return results.map((row) => CalendarEvent.fromMap(row)).toList();
    } catch (e) {
      print('[CalendarEventRepository] ❌ イベント取得エラー: $e');
      return [];
    }
  }
  // ================================================================
}