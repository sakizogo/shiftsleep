import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import 'alarm_service.dart';

/// N4: 「今夜だけ」有効な手動起床時刻を管理する
/// - 設定画面で起床時刻を選んだとき save()
/// - 「今から寝る」で getActive() → シフト基準と比べて早い方を登録
/// - 「起きる」で clear()
class ManualWakeService {
  static const String _key = 'shiftsleep_manual_wake_at';

  /// 指定時刻が次に来る日時（今日のその時刻が過ぎていれば明日）
  static DateTime nextOccurrence(TimeOfDay time, {DateTime? from}) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return today.isAfter(now) ? today : today.add(const Duration(days: 1));
  }

  /// 手動起床時刻を保存（今夜だけ有効）
  static Future<void> save(TimeOfDay time) async {
    final target = nextOccurrence(time);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, target.toIso8601String());
    print('[ManualWake] 💾 手動起床時刻を保存: $target');
  }

  /// 有効な手動起床時刻を返す（未保存・過去なら null。過去の値は削除）
  static Future<DateTime?> getActive() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == null) return null;

    final target = DateTime.tryParse(saved);
    if (target == null || !target.isAfter(DateTime.now())) {
      await prefs.remove(_key);
      print('[ManualWake] 🗑️ 期限切れの手動起床時刻を削除: $saved');
      return null;
    }
    print('[ManualWake] ✅ 有効な手動起床時刻: $target');
    return target;
  }

  /// 手動起床時刻を削除（「起きる」押下時）
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    print('[ManualWake] 🗑️ 手動起床時刻をクリア');
  }

  /// 手動起床時刻でアラームを登録し、成功したら1秒バイブ
  /// 戻り値：エラーメッセージ（成功時は null）
  static Future<String?> scheduleAlarm({
    required DateTime target,
    required int preAlarmMinutes,
    required String selectedAlarmSound,
  }) async {
    final shiftDate = DateTime(target.year, target.month, target.day);

    // 起床アラーム（main）だけを取り消してから登録（pre は残す）
    await AlarmService.cancelMainAlarm(shiftDate);

    final errorCode = await AlarmService.scheduleAlarmForShift(
      shiftDate: shiftDate,
      alarmTime: TimeOfDay(hour: target.hour, minute: target.minute),
      preAlarmEnabled: false,
      preAlarmMinutes: preAlarmMinutes,
      selectedAlarmSound: selectedAlarmSound,
    );
    print('[ManualWake] 📨 手動起床アラームを登録: $target ※結果は [AlarmService] ログを参照');

    final error = AlarmService.alarmErrorMessage(errorCode);
    if (error == null) {
      await _vibrate();
    }
    return error;
  }

  static Future<void> _vibrate() async {
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(duration: 1000);
        print('[ManualWake] 📳 バイブ（1秒）');
      }
    } catch (e) {
      print('[ManualWake] ⚠️ バイブ失敗: $e');
    }
  }
}