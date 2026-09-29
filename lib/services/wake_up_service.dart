import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/sleep_preference_service.dart';

/// 起床処理（UI を含まない部分）
/// 「起きる」ボタンと、通知の停止ボタン経由の起床で共通して使う
class WakeUpService {
  static final SleepRepository _sleepRepository = SleepRepository();

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
}
