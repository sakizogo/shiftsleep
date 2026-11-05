import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// 睡眠状態をSharedPreferencesで永続化するサービス
class SleepPreferenceService {
  static const String _sleepStartTimeKey = 'sleep_start_time_ms';
  static const String _shiftIdKey = 'current_shift_id';
  static const String _currentSleepRecordIdKey = 'current_sleep_record_id';  // ✅ 【追加】

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

  // ========== Week 8 追加: 睡眠記録ID の永続化 ==========
  /// 睡眠記録IDを保存
  /// 睡眠開始時に SleepProvider から呼び出される
  static Future<void> setCurrentSleepRecordId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentSleepRecordIdKey, id);
      print('[SleepPrefs] 💾 睡眠記録ID を保存: $_currentSleepRecordIdKey = $id');
    } catch (e) {
      print('[SleepPrefs] ❌ 睡眠記録ID 保存エラー: $e');
    }
  }

  /// 睡眠記録IDを取得
  /// アプリ起動時に SleepProvider から呼び出される
  static Future<String?> getCurrentSleepRecordId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_currentSleepRecordIdKey);
      if (id != null) {
        print('[SleepPrefs] 📖 睡眠記録ID を取得: $id');
      }
      return id;
    } catch (e) {
      print('[SleepPrefs] ❌ 睡眠記録ID 取得エラー: $e');
      return null;
    }
  }

  /// N143：起動時の復元用。睡眠中（開始時刻が保存されている）なら ID を返す
  /// 睡眠中でなければ、残っている ID を消して null を返す
  /// 開始時刻の確認と削除の間に await を挟まない（同時に「今から寝る」が走っても新しい ID を消さないように）
  /// 読めないときは何も消さない
  static Future<String?> restoreCurrentSleepRecordId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt(_sleepStartTimeKey) != null) {
        return prefs.getString(_currentSleepRecordIdKey);
      }
      if (prefs.containsKey(_currentSleepRecordIdKey)) {
        await prefs.remove(_currentSleepRecordIdKey);
        debugPrint('[SleepPrefs] 🗑️ 睡眠中ではないため、残っていた睡眠記録ID をクリア');
      }
      return null;
    } catch (e) {
      debugPrint('[SleepPrefs] ❌ 睡眠記録ID 復元エラー: $e');
      return null;
    }
  }

  /// 睡眠記録IDをクリア
  /// 睡眠終了時に SleepProvider から呼び出される
  static Future<void> clearCurrentSleepRecordId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_currentSleepRecordIdKey);
      print('[SleepPrefs] 🗑️ 睡眠記録ID をクリア');
    } catch (e) {
      print('[SleepPrefs] ❌ 睡眠記録ID クリアエラー: $e');
    }
  }
  // ======================================================
}