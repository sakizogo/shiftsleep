import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/manual_wake_service.dart';
import 'package:shiftsleep/services/sleep_preference_service.dart';

/// N19：起床はできたがアラームを取り消せなかったときの文言
const alarmCancelFailedText = '⚠️ 起床は記録しましたが、アラームを取り消せませんでした。鳴ったら止めてください';

/// N19：通知の「停止」で保存された停止時刻を処理した結果
enum PendingAlarmStopResult {
  notProcessed,  // 起床処理をしなかった
  woke,  // 起床処理をした
  wokeButAlarmCancelFailed,  // 起床処理をしたが、アラームを取り消せなかった
}

/// 起床処理（UI を含まない部分）
/// 「起きる」ボタンと、通知の停止ボタン経由の起床で共通して使う
class WakeUpService {
  static SleepRepository _sleepRepository = SleepRepository();

  /// N143：テストで偽物の DB に差し替える
  @visibleForTesting
  static set sleepRepositoryForTest(SleepRepository repository) => _sleepRepository = repository;

  // AlarmReceiver.kt が "flutter.alarm_stopped_at_ms" として保存する停止時刻（ミリ秒）
  static const String _alarmStoppedAtKey = 'alarm_stopped_at_ms';
  static bool _isProcessingPendingStop = false;

  /// wakeUpTime: 起床時刻（「起きる」ボタンなら DateTime.now()、通知の「停止」なら押した時刻）
  /// N19：どちらの起床でも、wakeUpTime の日付の main・pre と、今日・明日の main を取り消す
  /// 戻り値: アラームを取り消せたら true（取り消せなくても起床は最後まで進める。知らせるのは呼び出し元）
  static Future<bool> wakeUp(
    SleepProvider provider,
    DateTime wakeUpTime,
  ) async {
    // N33: 睡眠記録がない・id がない・途中で例外が出ても、音は必ず止める（stopAlarmSound は例外を外に出さない）
    await AlarmService.stopAlarmSound();
    print('[SleepButton] 🔊 アラーム音を停止しました');

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
      print('[SleepButton] 🔔 今日のシフト始業30分前アラームをキャンセル中...');
      final alarmsCancelled = await _cancelAlarmsForWakeUp(wakeUpTime);

      // ✅ N4: 手動起床時刻は「今夜だけ有効」なので起床したら消す
      await ManualWakeService.clear();
      print('[SleepButton] ✅ アラームをキャンセルしました');
      // =====================================================================

      // ========== Week 7 Phase 3 修正: SleepProvider の睡眠中フラグをクリア ==========
      await provider.endSleepingNow();
      print('[SleepButton] ✅ 睡眠中フラグをクリア');
      // ========================================================================

      await provider.loadAllSleepData();
      return alarmsCancelled;
    } else {
      print('[SleepButton] ⚠️ 睡眠レコードが見つかりません');
      return true;
    }
  }

  /// N19：起床で main・pre を取り消す。失敗しても例外を外に出さず、false を返す
  /// 片方が失敗しても、もう片方は取り消す
  static Future<bool> _cancelAlarmsForWakeUp(DateTime wakeUpTime) async {
    var cancelled = true;
    try {
      final wakeUpDate = DateTime(wakeUpTime.year, wakeUpTime.month, wakeUpTime.day);
      cancelled = await AlarmService.cancelAlarm(wakeUpDate);
    } catch (e) {
      debugPrint('[WakeUpService] ❌ 起床の日の main・pre を取り消せませんでした: $e');
      cancelled = false;
    }
    try {
      // ✅ N17: 明日の日付で登録された手動起床アラームも残さない
      if (!await ManualWakeService.cancelTodayAndTomorrow()) cancelled = false;
    } catch (e) {
      debugPrint('[WakeUpService] ❌ 今日・明日の main を取り消せませんでした: $e');
      cancelled = false;
    }
    return cancelled;
  }

  /// 通知の「停止」ボタン（AlarmReceiver.kt）が保存した停止時刻で起床処理を行う
  static Future<PendingAlarmStopResult> processPendingAlarmStop(SleepProvider provider) async {
    if (_isProcessingPendingStop) {
      print('[WakeUpService] ⏭️ 停止時刻の処理中のためスキップ');
      return PendingAlarmStopResult.notProcessed;
    }
    _isProcessingPendingStop = true;

    try {
      // Kotlin 側が書いた値を読むため、キャッシュを読み直す
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final stoppedAtMs = prefs.getInt(_alarmStoppedAtKey);
      if (stoppedAtMs == null) {
        return PendingAlarmStopResult.notProcessed;
      }
      final stoppedAt = DateTime.fromMillisecondsSinceEpoch(stoppedAtMs);
      print('[WakeUpService] 🔔 保存された停止時刻: $stoppedAt');

      // 睡眠中の保存値があるのに Provider が未復元 → 初期化中なのでキーは残して後で処理する
      if (!provider.isSleepingNow &&
          await SleepPreferenceService.getSleepStartTime() != null) {
        print('[WakeUpService] ⏳ SleepProvider が初期化中のため後で処理します');
        return PendingAlarmStopResult.notProcessed;
      }

      // 二重実行を防ぐため、起床処理より先に消す
      await prefs.remove(_alarmStoppedAtKey);

      final sleepStartTime = provider.sleepStartTime;
      if (!provider.isSleepingNow) {
        print('[WakeUpService] ℹ️ 睡眠中ではないため起床処理をしません');
        return PendingAlarmStopResult.notProcessed;
      }
      if (sleepStartTime == null) {
        print('[WakeUpService] ⚠️ 睡眠開始時刻がないため起床処理をしません');
        return PendingAlarmStopResult.notProcessed;
      }
      if (!stoppedAt.isAfter(sleepStartTime)) {
        print('[WakeUpService] ℹ️ 停止時刻が睡眠開始（$sleepStartTime）以前のため起床処理をしません');
        return PendingAlarmStopResult.notProcessed;
      }
      if (stoppedAt.isAfter(DateTime.now())) {
        print('[WakeUpService] ⚠️ 停止時刻が未来のため起床処理をしません');
        return PendingAlarmStopResult.notProcessed;
      }

      print('[WakeUpService] 🌅 停止時刻で起床処理を実行します');
      final alarmsCancelled = await wakeUp(provider, stoppedAt);
      print('[WakeUpService] ✅ 停止時刻での起床処理が完了しました');
      return alarmsCancelled
          ? PendingAlarmStopResult.woke
          : PendingAlarmStopResult.wokeButAlarmCancelFailed;
    } catch (e) {
      print('[WakeUpService] ❌ 停止時刻の処理エラー: $e');
      return PendingAlarmStopResult.notProcessed;
    } finally {
      _isProcessingPendingStop = false;
    }
  }
}
