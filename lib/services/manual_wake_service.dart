import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import 'alarm_service.dart';

/// N4/N10/N11: 手動起床時刻を管理する
/// - 設定画面で起床時刻を選んだとき save()（今夜だけの予約 + 最後に選んだ時刻を保存）
/// - 「この設定を毎日使用する」は setDaily() / isDaily()
/// - 「今から寝る」で getActive() → 今夜だけの予約、なければ毎日設定の時刻を返す
///   （シフト基準と比べて早い方を登録するのは呼び出し側）
/// - 「起きる」で clear() → 今夜だけの予約のみ削除（最後に選んだ時刻と毎日設定は残す）
class ManualWakeService {
  /// 今夜だけの予約（ISO8601 日時）
  static const String _key = 'shiftsleep_manual_wake_at';

  /// 最後に選んだ時刻（"HH:mm"、clear() では消さない）
  static const String _timeKey = 'shiftsleep_manual_wake_time';

  /// 毎日使用フラグ（bool、clear() では消さない）
  static const String _dailyKey = 'shiftsleep_manual_wake_daily';

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
    await prefs.setString(_timeKey, _format(time));
    print('[ManualWake] 💾 手動起床時刻を保存: $target');
  }

  /// 毎日使用フラグを返す（未保存なら false）
  static Future<bool> isDaily() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dailyKey) ?? false;
  }

  /// 毎日使用フラグを保存（time があれば最後に選んだ時刻も保存）
  static Future<void> setDaily(bool enabled, {TimeOfDay? time}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dailyKey, enabled);
    if (time != null) {
      await prefs.setString(_timeKey, _format(time));
    }
    print('[ManualWake] 🔁 毎日使用: ${enabled ? 'ON' : 'OFF'}');
  }

  /// 有効な手動起床時刻を返す
  /// ① 今夜だけの予約が未来ならそれ（過去なら削除）
  /// ② なければ毎日使用 ON かつ最後に選んだ時刻があれば、その次の発生日時
  /// ③ どちらもなければ null
  static Future<DateTime?> getActive() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      final target = DateTime.tryParse(saved);
      if (target != null && target.isAfter(DateTime.now())) {
        print('[ManualWake] ✅ 有効な手動起床時刻: $target');
        return target;
      }
      await prefs.remove(_key);
      print('[ManualWake] 🗑️ 期限切れの手動起床時刻を削除: $saved');
    }

    final daily = prefs.getBool(_dailyKey) ?? false;
    final time = _parse(prefs.getString(_timeKey));
    if (daily && time != null) {
      final target = nextOccurrence(time);
      print('[ManualWake] 🔁 毎日設定から手動起床時刻: $target');
      return target;
    }
    return null;
  }

  /// 今夜だけの予約を削除（「起きる」押下時）。最後に選んだ時刻と毎日設定は残す
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    print('[ManualWake] 🗑️ 手動起床時刻をクリア（毎日設定は残す）');
  }

  static String _format(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  /// "HH:mm" を TimeOfDay に変換（不正値は null）
  static TimeOfDay? _parse(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
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