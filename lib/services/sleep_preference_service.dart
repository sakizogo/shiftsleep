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
  /// N142：保存できなければ例外を投げる（呼び出し元が元に戻して知らせる）
  static Future<void> saveSleepStartTime(
    DateTime sleepStartTime, {
    int? shiftId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final milliseconds = sleepStartTime.millisecondsSinceEpoch;

    _ensureSaved(await prefs.setInt(_sleepStartTimeKey, milliseconds), _sleepStartTimeKey);
    if (shiftId != null) {
      _ensureSaved(await prefs.setInt(_shiftIdKey, shiftId), _shiftIdKey);
    }

    debugPrint('[SleepPrefs] 睡眠開始時刻を保存: $_sleepStartTimeKey = $milliseconds');
  }

  /// N142：書き込みの失敗は例外ではなく false で返るので、ここで例外にする
  static void _ensureSaved(bool saved, String key) {
    if (!saved) throw Exception('SharedPreferences に保存できませんでした: $key');
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

  /// N142：片付け用。開始時刻と記録 ID を読む。getSleepStartTime と違い、読めないときの例外をそのまま外に出す
  /// （読めないのに「睡眠中ではない」と判断して記録を消さないように）
  static Future<({DateTime? startTime, String? recordId})> readSleepStateOrThrow() async {
    final prefs = await SharedPreferences.getInstance();
    final milliseconds = prefs.getInt(_sleepStartTimeKey);
    return (
      startTime: milliseconds == null ? null : DateTime.fromMillisecondsSinceEpoch(milliseconds),
      recordId: prefs.getString(_currentSleepRecordIdKey),
    );
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
  /// N142：戻り値 true=消せた。例外は外に出さない（失敗しても起床や「元に戻す」処理は止めない）
  static Future<bool> clearSleepState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final startRemoved = await prefs.remove(_sleepStartTimeKey);
      final shiftRemoved = await prefs.remove(_shiftIdKey);
      debugPrint('[SleepPrefs] 睡眠状態をクリア: 開始時刻 $startRemoved、シフトID $shiftRemoved');
      return startRemoved && shiftRemoved;
    } catch (e) {
      debugPrint('[SleepPrefs] ❌ 睡眠状態のクリアエラー: $e');
      return false;
    }
  }

  // ========== Week 8 追加: 睡眠記録ID の永続化 ==========
  /// 睡眠記録IDを保存
  /// 睡眠開始時に SleepProvider から呼び出される
  /// N142：保存できなければ例外を投げる（呼び出し元が元に戻して知らせる）
  static Future<void> setCurrentSleepRecordId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    _ensureSaved(await prefs.setString(_currentSleepRecordIdKey, id), _currentSleepRecordIdKey);
    debugPrint('[SleepPrefs] 💾 睡眠記録ID を保存: $_currentSleepRecordIdKey = $id');
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
  /// N142：戻り値 true=消せた。例外は外に出さない（失敗しても起床や「元に戻す」処理は止めない）
  static Future<bool> clearCurrentSleepRecordId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final removed = await prefs.remove(_currentSleepRecordIdKey);
      debugPrint('[SleepPrefs] 🗑️ 睡眠記録ID をクリア: $removed');
      return removed;
    } catch (e) {
      debugPrint('[SleepPrefs] ❌ 睡眠記録ID クリアエラー: $e');
      return false;
    }
  }
  // ======================================================
}