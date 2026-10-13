import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/sleep_preference_service.dart';

/// 起床処理（UI を含まない部分）
/// 「起きる」ボタンと、通知の停止ボタン経由の起床で共通して使う
class WakeUpService {
  static final SleepRepository _sleepRepository = SleepRepository();

  // AlarmReceiver.kt が "flutter.alarm_stopped_at_ms" として保存する停止時刻（ミリ秒）
  static const String _alarmStoppedAtKey = 'alarm_stopped_at_ms';
  static bool _isProcessingPendingStop = false;

  /// wakeUpTime: 起床時刻（「起きる」ボタンなら DateTime.now()）
  /// cancelAlarms: true なら wakeUpTime の日付の main・pre アラームをキャンセル
  static Future<void> wakeUp(
    SleepProvider provider,
    DateTime wakeUpTime, {
    bool cancelAlarms = true,
  }) async {
    // ========== Week 7 Phase 3 修正: SleepProvider から現在の睡眠レコード ID を取得 ==========
    // Provider に未復元なら SharedPreferences の保存値で補う
    var currentSleepRecordId = provider.currentSleepRecordIdNow;
    currentSleepRecordId ??= await SleepPreferenceService.getCurrentSleepRecordId();
    print('[SleepButton] 🔍 currentSleepRecordId: $currentSleepRecordId');
    if (currentSleepRecordId == null) {
      throw Exception('Sleep record ID not found in SleepProvider');
    }
    // ========================================================================

    final sleepRecord =
        await _sleepRepository.getSleepRecordById(currentSleepRecordId);

    if (sleepRecord != null) {
      print('[SleepButton] 💾 睡眠レコードを更新中...');

      final updatedRecord = sleepRecord.copyWith(
        sleepEndTime: wakeUpTime,
        sleepEndAuto: false,
        durationMinutes: wakeUpTime.difference(sleepRecord.sleepStartTime).inMinutes,
        lastModifiedAt: wakeUpTime,
        updatedAt: wakeUpTime,
      );

      await _sleepRepository.updateSleepRecord(updatedRecord);
      print('[SleepButton] ✅ Sleep record updated: ${updatedRecord.id}');

      // ========== Step 7：今日のシフト始業30分前アラームをキャンセル ==========
      if (cancelAlarms) {
        print('[SleepButton] 🔔 今日のシフト始業30分前アラームをキャンセル中...');
        final today = DateTime(wakeUpTime.year, wakeUpTime.month, wakeUpTime.day);
        await AlarmService.cancelAlarm(today);
      }
      await AlarmService.stopAlarmSound();
      print('[SleepButton] 🔊 アラーム音を停止しました');
      if (cancelAlarms) {
        print('[SleepButton] ✅ アラームをキャンセルしました');
      }
      // =====================================================================

      // ========== Week 7 Phase 3 修正: SleepProvider の睡眠中フラグをクリア ==========
      await provider.endSleepingNow();
      print('[SleepButton] ✅ 睡眠中フラグをクリア');
      // ========================================================================

      await provider.loadAllSleepData();
    } else {
      print('[SleepButton] ⚠️ 睡眠レコードが見つかりません');
    }
  }

  /// 通知の「停止」ボタン（AlarmReceiver.kt）が保存した停止時刻で起床処理を行う
  /// 戻り値: 起床処理を行ったら true、それ以外は false
  static Future<bool> processPendingAlarmStop(SleepProvider provider) async {
    if (_isProcessingPendingStop) {
      print('[WakeUpService] ⏭️ 停止時刻の処理中のためスキップ');
      return false;
    }
    _isProcessingPendingStop = true;

    try {
      // Kotlin 側が書いた値を読むため、キャッシュを読み直す
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final stoppedAtMs = prefs.getInt(_alarmStoppedAtKey);
      if (stoppedAtMs == null) {
        return false;
      }
      final stoppedAt = DateTime.fromMillisecondsSinceEpoch(stoppedAtMs);
      print('[WakeUpService] 🔔 保存された停止時刻: $stoppedAt');

      // 睡眠中の保存値があるのに Provider が未復元 → 初期化中なのでキーは残して後で処理する
      if (!provider.isSleepingNow &&
          await SleepPreferenceService.getSleepStartTime() != null) {
        print('[WakeUpService] ⏳ SleepProvider が初期化中のため後で処理します');
        return false;
      }

      // 二重実行を防ぐため、起床処理より先に消す
      await prefs.remove(_alarmStoppedAtKey);

      final sleepStartTime = provider.sleepStartTime;
      if (!provider.isSleepingNow) {
        print('[WakeUpService] ℹ️ 睡眠中ではないため起床処理をしません');
        return false;
      }
      if (sleepStartTime == null) {
        print('[WakeUpService] ⚠️ 睡眠開始時刻がないため起床処理をしません');
        return false;
      }
      if (!stoppedAt.isAfter(sleepStartTime)) {
        print('[WakeUpService] ℹ️ 停止時刻が睡眠開始（$sleepStartTime）以前のため起床処理をしません');
        return false;
      }
      if (stoppedAt.isAfter(DateTime.now())) {
        print('[WakeUpService] ⚠️ 停止時刻が未来のため起床処理をしません');
        return false;
      }

      print('[WakeUpService] 🌅 停止時刻で起床処理を実行します');
      await wakeUp(provider, stoppedAt, cancelAlarms: false);
      print('[WakeUpService] ✅ 停止時刻での起床処理が完了しました');
      return true;
    } catch (e) {
      print('[WakeUpService] ❌ 停止時刻の処理エラー: $e');
      return false;
    } finally {
      _isProcessingPendingStop = false;
    }
  }
}
