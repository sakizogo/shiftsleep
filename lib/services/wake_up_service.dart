import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/manual_wake_service.dart';
import 'package:shiftsleep/services/sleep_preference_service.dart';

/// N19：起床はできたがアラームを取り消せなかったときの文言
const alarmCancelFailedText = '⚠️ 起床は記録しましたが、アラームを取り消せませんでした。鳴ったら止めてください';

/// N142：起こす記録が見つからず、起床時刻を記録できなかったときの文言
const noRecordWakeText = '⚠️ 記録中の睡眠が見つからなかったため、起床時刻は記録できませんでした。あとから睡眠記録の「追加」で入れられます';

/// N142：記録なしの起床でアラームも取り消せなかったときの文言（「起床は記録しました」とは言えない）
const noRecordAlarmCancelFailedText = '⚠️ アラームを取り消せませんでした。鳴ったら止めてください';

/// N142：SharedPreferences の睡眠状態を消せなかったときの文言
/// 再起動で睡眠中に戻っても、完了済みの記録は上書きしない（_findSleepingRecord）
const stateClearFailedText = '⚠️ 睡眠中の状態を消せませんでした。端末の空き容量が少ないかもしれません。次に開いたときに「睡眠中」に戻っていたら「起きる」を押してください（記録済みの起床時刻は変わりません）';

/// N142：起床処理の結果
/// recorded：起床時刻を記録できた（false は記録なしの起床）
/// alarmsCancelled：アラームを取り消せた
/// stateCleared：SharedPreferences の睡眠状態を消せた
typedef WakeUpResult = ({bool recorded, bool alarmsCancelled, bool stateCleared});

/// N142：起床処理のあとに出す ⚠️ の文言（出す順）
List<String> wakeUpWarningTexts(WakeUpResult result) => [
      if (!result.recorded) noRecordWakeText,
      if (!result.alarmsCancelled)
        result.recorded ? alarmCancelFailedText : noRecordAlarmCancelFailedText,
      if (!result.stateCleared) stateClearFailedText,
    ];

/// N19：通知の「停止」で保存された停止時刻を処理した結果
class PendingAlarmStopResult {
  const PendingAlarmStopResult._(this.wakeUpResult);

  /// N142：起床処理の結果から作る
  factory PendingAlarmStopResult.fromWakeUp(WakeUpResult result) => PendingAlarmStopResult._(result);

  /// 起床処理の結果（null は起床処理をしなかった）
  final WakeUpResult? wakeUpResult;

  static const notProcessed = PendingAlarmStopResult._(null);  // 起床処理をしなかった
  static const woke = PendingAlarmStopResult._((recorded: true, alarmsCancelled: true, stateCleared: true));  // 起床処理をした
  static const wokeButAlarmCancelFailed = PendingAlarmStopResult._((recorded: true, alarmsCancelled: false, stateCleared: true));  // 起床処理をしたが、アラームを取り消せなかった
  static const wokeWithoutRecord = PendingAlarmStopResult._((recorded: false, alarmsCancelled: true, stateCleared: true));  // 記録なしの起床をした
  static const wokeWithoutRecordButAlarmCancelFailed = PendingAlarmStopResult._((recorded: false, alarmsCancelled: false, stateCleared: true));  // 記録なしの起床をしたが、アラームを取り消せなかった

  /// N142：⏰「起床を記録しました」は記録できたときだけ出す
  bool get recordedWake => wakeUpResult?.recorded ?? false;

  /// N142：⏰ のあとに出す ⚠️ の文言（出す順）
  List<String> get warningTexts {
    final result = wakeUpResult;
    return result == null ? const [] : wakeUpWarningTexts(result);
  }

  @override
  bool operator ==(Object other) =>
      other is PendingAlarmStopResult && other.wakeUpResult == wakeUpResult;

  @override
  int get hashCode => wakeUpResult.hashCode;

  @override
  String toString() => 'PendingAlarmStopResult($wakeUpResult)';
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
  /// N142：記録が見つからなくても、記録なしの起床として最後まで進める（睡眠中から必ず抜けられる）
  /// DB を読めない・更新できないときは例外を投げ、睡眠中のままにする（もう一度「起きる」を押せる）
  /// 戻り値の知らせは呼び出し元が出す（wakeUpWarningTexts）
  static Future<WakeUpResult> wakeUp(
    SleepProvider provider,
    DateTime wakeUpTime,
  ) async {
    // N33: 睡眠記録がない・id がない・途中で例外が出ても、音は必ず止める（stopAlarmSound は例外を外に出さない）
    await AlarmService.stopAlarmSound();
    print('[SleepButton] 🔊 アラーム音を停止しました');

    final sleepRecord = await _findSleepingRecord(provider);

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
    } else {
      debugPrint('[WakeUpService] ⚠️ 起こす記録が見つからないため、記録なしの起床にします');
    }

    // ========== Step 7：今日のシフト始業30分前アラームをキャンセル ==========
    print('[SleepButton] 🔔 今日のシフト始業30分前アラームをキャンセル中...');
    final alarmsCancelled = await _cancelAlarmsForWakeUp(wakeUpTime);

    // ✅ N4: 手動起床時刻は「今夜だけ有効」なので起床したら消す
    await ManualWakeService.clear();
    print('[SleepButton] ✅ アラームをキャンセルしました');
    // =====================================================================

    // ========== Week 7 Phase 3 修正: SleepProvider の睡眠中フラグをクリア ==========
    // N142：消せなくても起床は止めない（知らせるのは呼び出し元）
    final stateCleared = await provider.endSleepingNow();
    print('[SleepButton] ✅ 睡眠中フラグをクリア');
    // ========================================================================

    await provider.loadAllSleepData();
    return (
      recorded: sleepRecord != null,
      alarmsCancelled: alarmsCancelled,
      stateCleared: stateCleared,
    );
  }

  /// N142：起こす記録を探す。① 保存された ID → ② 保存された開始時刻 の順。なければ null
  /// どちらも「開始時刻がミリ秒まで一致し、進行中（durationMinutes == 0）」の記録だけを採用する
  /// （ID が古くても別の記録を、再起動で睡眠中に戻っても完了済みの記録を上書きしない）
  /// DB を読めないときの例外はそのまま外に出す
  static Future<SleepRecord?> _findSleepingRecord(SleepProvider provider) async {
    final startTime =
        provider.sleepStartTime ?? await SleepPreferenceService.getSleepStartTime();
    if (startTime == null) {
      debugPrint('[WakeUpService] ⚠️ 睡眠の開始時刻がありません');
      return null;
    }
    bool isSleepingRecord(SleepRecord record) =>
        record.durationMinutes == 0 &&
        record.sleepStartTime.millisecondsSinceEpoch == startTime.millisecondsSinceEpoch;

    // Provider に未復元なら SharedPreferences の保存値で補う
    final id = provider.currentSleepRecordIdNow ??
        await SleepPreferenceService.getCurrentSleepRecordId();
    debugPrint('[WakeUpService] 🔍 保存された記録 ID: $id');
    if (id != null) {
      final record = await _sleepRepository.getSleepRecordById(id);
      if (record != null && isSleepingRecord(record)) return record;
      debugPrint('[WakeUpService] ℹ️ ID の記録は採用できないため、開始時刻で探します');
    }

    // SQL の文字列比較にせず、入眠日で絞ってからミリ秒で比べる
    final records = await _sleepRepository.getSleepRecordsByDateRange(
      'test_user',
      DateTime(startTime.year, startTime.month, startTime.day),
      DateTime(startTime.year, startTime.month, startTime.day, 23, 59, 59),
    );
    for (final record in records) {
      if (isSleepingRecord(record)) return record;
    }
    return null;
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
      final result = await wakeUp(provider, stoppedAt);
      print('[WakeUpService] ✅ 停止時刻での起床処理が完了しました');
      return PendingAlarmStopResult.fromWakeUp(result);
    } catch (e) {
      print('[WakeUpService] ❌ 停止時刻の処理エラー: $e');
      return PendingAlarmStopResult.notProcessed;
    } finally {
      _isProcessingPendingStop = false;
    }
  }
}
