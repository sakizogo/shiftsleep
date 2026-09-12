import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'alarm_model.dart';

class AlarmManager {
  static const platform = MethodChannel('com.sakizoapps.shiftsleep/alarm');

  /// アラームをセット
  static Future<void> setAlarm(Alarm alarm) async {
    try {
      print('[AlarmManager] 🔔 アラームをセット: $alarm');

      final timestampMs = alarm.scheduledTime.millisecondsSinceEpoch;

      final result = await platform.invokeMethod('setAlarm', {
        'alarmId': alarm.id,
        'timestampMs': timestampMs,
        'label': alarm.label,
        'selectedAlarmSound': alarm.selectedAlarmSound,  // ★ 追加
      });

      print('[AlarmManager] ✅ アラームセット成功: $result');
    } catch (e) {
      print('[AlarmManager] ❌ エラー: $e');
      rethrow;
    }
  }

  /// アラームをキャンセル
  static Future<void> cancelAlarm(String alarmId) async {
    try {
      print('[AlarmManager] ❌ アラームをキャンセル: $alarmId');

      await platform.invokeMethod('cancelAlarm', {
        'alarmId': alarmId,
      });

      print('[AlarmManager] ✅ キャンセル成功');
    } catch (e) {
      print('[AlarmManager] ❌ キャンセルエラー: $e');
      rethrow;
    }
  }

  /// アラームを停止
  static Future<void> stopAlarm() async {
    try {
      print('[AlarmManager] 🛑 stopAlarm 呼び出し中...');
      
      await platform.invokeMethod('stopAlarm');
      
      print('[AlarmManager] ✅ アラーム停止完了');
    } catch (e) {
      print('[AlarmManager] ❌ エラー: $e');
      rethrow;
    }
  }
}