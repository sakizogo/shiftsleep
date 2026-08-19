import 'package:shared_preferences/shared_preferences.dart';

/// 睡眠状態をSharedPreferencesで永続化するサービス
class SleepPreferenceService {
  static const String _sleepStartTimeKey = 'sleep_start_time_ms';
  static const String _shiftIdKey = 'current_shift_id';

  /// 睡眠開始時刻をミリ秒で保存
  /// sleepStartTime: 睡眠開始時刻 (DateTime)
  /// shiftId: 関連するシフトID（オプション）
  static Future<void> saveSleepStartTime(
    DateTime sleepStartTime, {
    int? shiftId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final milliseconds = sleepStartTime.millisecondsSinceEpoch;
      
      await prefs.setInt(_sleepStartTimeKey, milliseconds);
      if (shiftId != null) {
        await prefs.setInt(_shiftIdKey, shiftId);
      }
      
      print('[SleepPrefs] 睡眠開始時刻を保存: $_sleepStartTimeKey = $milliseconds');
    } catch (e) {
      print('[SleepPrefs] エラー (保存): $e');
    }
  }

  /// 保存された睡眠開始時刻を取得
  /// 戻り値: DateTime? (保存されていなければ null)
  static Future<DateTime?> getSleepStartTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final milliseconds = prefs.getInt(_sleepStartTimeKey);
      
      if (milliseconds == null) {
        print('[SleepPrefs] 保存された睡眠開始時刻なし');
        return null;
      }
      
      final startTime = DateTime.fromMillisecondsSinceEpoch(milliseconds);
      print('[SleepPrefs] 睡眠開始時刻を復元: $startTime');
      return startTime;
    } catch (e) {
      print('[SleepPrefs] エラー (取得): $e');
      return null;
    }
  }

  /// 関連するシフトIDを取得
  static Future<int?> getShiftId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_shiftIdKey);
    } catch (e) {
      print('[SleepPrefs] エラー (シフトID取得): $e');
      return null;
    }
  }

  /// 睡眠状態をクリア（睡眠終了時に呼び出す）
  static Future<void> clearSleepState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sleepStartTimeKey);
      await prefs.remove(_shiftIdKey);
      print('[SleepPrefs] 睡眠状態をクリア');
    } catch (e) {
      print('[SleepPrefs] エラー (クリア): $e');
    }
  }
}