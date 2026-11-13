import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/manual_wake_service.dart';
import 'package:shiftsleep/services/pattern_usage.dart';
import 'package:shiftsleep/services/sleep_preference_service.dart';
import 'package:shiftsleep/services/wake_pre_cancel.dart';

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

/// N142：通知の「停止」の起床を記録できなかったときの文言
String pendingStopFailedText(DateTime stoppedAt) {
  final time = '${stoppedAt.hour}:${stoppedAt.minute.toString().padLeft(2, '0')}';
  return '⚠️ $time に止めたアラームの起床を記録できませんでした。次にアプリを開いたときに自動でやり直します。「起きる」を押すと、押した時刻で記録されます';
}

/// N19：通知の「停止」で保存された停止時刻を処理した結果
class PendingAlarmStopResult {
  const PendingAlarmStopResult._(
    this.wakeUpResult, {
    this.failedStoppedAt,
    this.failureAlreadyNotified = false,
  });

  /// N142：起床処理の結果から作る
  factory PendingAlarmStopResult.fromWakeUp(WakeUpResult result) => PendingAlarmStopResult._(result);

  /// N142：起床処理が例外で終わった（キーは残っている）
  factory PendingAlarmStopResult.failed(DateTime stoppedAt, {required bool alreadyNotified}) =>
      PendingAlarmStopResult._(null, failedStoppedAt: stoppedAt, failureAlreadyNotified: alreadyNotified);

  /// 起床処理の結果（null は起床処理をしなかった、または失敗した）
  final WakeUpResult? wakeUpResult;

  /// N142：起床処理が失敗したときの停止時刻
  final DateTime? failedStoppedAt;

  /// N142：同じ停止時刻の失敗をもう知らせた（⚠️ を出さない）
  final bool failureAlreadyNotified;

  bool get isFailed => failedStoppedAt != null;

  static const notProcessed = PendingAlarmStopResult._(null);  // 起床処理をしなかった
  static const woke = PendingAlarmStopResult._((recorded: true, alarmsCancelled: true, stateCleared: true));  // 起床処理をした
  static const wokeButAlarmCancelFailed = PendingAlarmStopResult._((recorded: true, alarmsCancelled: false, stateCleared: true));  // 起床処理をしたが、アラームを取り消せなかった
  static const wokeWithoutRecord = PendingAlarmStopResult._((recorded: false, alarmsCancelled: true, stateCleared: true));  // 記録なしの起床をした
  static const wokeWithoutRecordButAlarmCancelFailed = PendingAlarmStopResult._((recorded: false, alarmsCancelled: false, stateCleared: true));  // 記録なしの起床をしたが、アラームを取り消せなかった

  /// N142：⏰「起床を記録しました」は記録できたときだけ出す
  bool get recordedWake => wakeUpResult?.recorded ?? false;

  /// N142：⏰ のあとに出す ⚠️ の文言（出す順）
  List<String> get warningTexts {
    final stoppedAt = failedStoppedAt;
    if (stoppedAt != null) {
      return failureAlreadyNotified ? const [] : [pendingStopFailedText(stoppedAt)];
    }
    final result = wakeUpResult;
    return result == null ? const [] : wakeUpWarningTexts(result);
  }

  @override
  bool operator ==(Object other) =>
      other is PendingAlarmStopResult &&
      other.wakeUpResult == wakeUpResult &&
      other.failedStoppedAt == failedStoppedAt &&
      other.failureAlreadyNotified == failureAlreadyNotified;

  @override
  int get hashCode => Object.hash(wakeUpResult, failedStoppedAt, failureAlreadyNotified);

  @override
  String toString() =>
      'PendingAlarmStopResult($wakeUpResult, failedStoppedAt: $failedStoppedAt, alreadyNotified: $failureAlreadyNotified)';
}

/// 起床処理（UI を含まない部分）
/// 「起きる」ボタンと、通知の停止ボタン経由の起床で共通して使う
class WakeUpService {
  static SleepRepository _sleepRepository = SleepRepository();

  /// N143：テストで偽物の DB に差し替える
  @visibleForTesting
  static set sleepRepositoryForTest(SleepRepository repository) => _sleepRepository = repository;

  /// N180 2/3：起床で pre を取り消すかを決めるために、設定・シフト・パターンを読む
  static ShiftRepository _shiftRepository = ShiftRepository();

  /// N180 2/3：テストで偽物の DB に差し替える
  @visibleForTesting
  static set shiftRepositoryForTest(ShiftRepository repository) => _shiftRepository = repository;

  // AlarmReceiver.kt が "flutter.alarm_stopped_at_ms" として保存する停止時刻（ミリ秒）
  static const String _alarmStoppedAtKey = 'alarm_stopped_at_ms';
  static bool _isProcessingPendingStop = false;

  /// N142：起床処理に失敗した停止時刻（⚠️ を 1 回だけ出す、タイマーではやり直さないために覚える）
  /// メモリだけに持つので、プロセスが終わると忘れる（同じ時刻でまた失敗したら、もう 1 回だけ知らせる）
  static int? _failedStoppedAtMs;

  /// N142：テストの間で失敗の記憶を残さない
  @visibleForTesting
  static void resetFailedStoppedAtForTest() => _failedStoppedAtMs = null;

  /// wakeUpTime: 起床時刻（「起きる」ボタンなら DateTime.now()、通知の「停止」なら押した時刻）
  /// stopSound: 今鳴っている音を止めるか（N142：通知の「停止」では AlarmReceiver が止めているので false。
  /// このとき鳴っている音は別のアラームなので、黙って止めない）
  /// N19：どちらの起床でも、wakeUpTime の日付の main・pre と、今日・明日の main を取り消す
  /// N180 2/3：pre は wakeUpTime から 3 時間以内に鳴るときだけ（_cancelAlarmsForWakeUp）
  /// N142：記録が見つからなくても、記録なしの起床として最後まで進める（睡眠中から必ず抜けられる）
  /// DB を読めない・更新できないときは例外を投げ、睡眠中のままにする（もう一度「起きる」を押せる）
  /// 戻り値の知らせは呼び出し元が出す（wakeUpWarningTexts）
  static Future<WakeUpResult> wakeUp(
    SleepProvider provider,
    DateTime wakeUpTime, {
    bool stopSound = true,
  }) async {
    // N33: 睡眠記録がない・id がない・途中で例外が出ても、音は必ず止める（stopAlarmSound は例外を外に出さない）
    if (stopSound) {
      await AlarmService.stopAlarmSound();
      print('[SleepButton] 🔊 アラーム音を停止しました');
    }

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
  /// N180 2/3：pre は、起きた日の欄の pre が起きた時刻から 3 時間以内に鳴るときだけ取り消す
  /// （設定・シフト・パターンを読めなかったら取り消さず、false を返す）
  static Future<bool> _cancelAlarmsForWakeUp(DateTime wakeUpTime) async {
    var cancelled = true;
    final wakeUpDate = DateTime(wakeUpTime.year, wakeUpTime.month, wakeUpTime.day);
    try {
      cancelled = await AlarmService.cancelMainAlarm(wakeUpDate);
    } catch (e) {
      debugPrint('[WakeUpService] ❌ 起床の日の main を取り消せませんでした: $e');
      cancelled = false;
    }
    DateTime? preAlarmAt;
    var preReadFailed = false;
    try {
      preAlarmAt = await _readPreAlarmAt(wakeUpDate);
    } catch (e) {
      debugPrint('[WakeUpService] ❌ 起床の日のシフトを読めなかったため、pre は取り消しません: $e');
      preReadFailed = true;
      cancelled = false;
    }
    if (!preReadFailed) {
      final cancelPre = shouldCancelPreOnWake(wakeUpTime: wakeUpTime, preAlarmAt: preAlarmAt);
      debugPrint('[WakeUpService] 🔔 起床の日の pre（$preAlarmAt）を${cancelPre ? '取り消します' : '残します'}');
      if (cancelPre) {
        try {
          if (!await AlarmService.cancelPreAlarm(wakeUpDate)) cancelled = false;
        } catch (e) {
          debugPrint('[WakeUpService] ❌ 起床の日の pre を取り消せませんでした: $e');
          cancelled = false;
        }
      }
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

  /// N180 2/3：起きた日の欄の pre が鳴る時刻（registeredPreAlarmAt）を DB から読む
  /// シフトなし・休日・分数 0 以下・パターンが見つからない（削除済み）→ null
  /// 設定・シフト・パターンを読めなかったら例外をそのまま外に出す
  static Future<DateTime?> _readPreAlarmAt(DateTime wakeUpDate) async {
    final settings = await _shiftRepository.getAppSettings('test_user');
    final minutesBefore = settings?.alarmTimeBeforeShift ?? 30;
    if (minutesBefore <= 0) return null;
    final rows = await _shiftRepository.getShiftsForDateRange(wakeUpDate, wakeUpDate);
    if (rows.isEmpty) return null;
    final patternId = rows.first['pattern_id'] as String?;
    if (patternId == null || patternId == 'default_dayoff' || patternId == legacyDayOffPatternId) return null;
    final pattern = await _shiftRepository.getPatternById(patternId);
    return registeredPreAlarmAt(shiftDate: wakeUpDate, pattern: pattern, minutesBefore: minutesBefore);
  }

  /// 通知の「停止」ボタン（AlarmReceiver.kt）が保存した停止時刻で起床処理を行う
  /// N142：キーは起床処理が例外なく終わってから消す。失敗したら残し、起動時・復帰時に同じ時刻でやり直す
  /// retryFailed: 失敗した同じ停止時刻をやり直すか（5 秒ごとのタイマーは false）
  static Future<PendingAlarmStopResult> processPendingAlarmStop(
    SleepProvider provider, {
    bool retryFailed = true,
  }) async {
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

      // 起床処理をしない停止時刻はキーを消す
      final discardReason = _stoppedAtDiscardReason(provider, stoppedAt);
      if (discardReason != null) {
        debugPrint('[WakeUpService] ℹ️ 起床処理をしません: $discardReason');
        await _removeStoppedAt(prefs);
        return PendingAlarmStopResult.notProcessed;
      }

      if (!retryFailed && stoppedAtMs == _failedStoppedAtMs) {
        debugPrint('[WakeUpService] ⏭️ 失敗した停止時刻は起動時・復帰時にやり直します');
        return PendingAlarmStopResult.notProcessed;
      }

      print('[WakeUpService] 🌅 停止時刻で起床処理を実行します');
      final WakeUpResult result;
      try {
        result = await wakeUp(provider, stoppedAt, stopSound: false);
      } catch (e) {
        debugPrint('[WakeUpService] ❌ 停止時刻での起床処理に失敗（キーを残してやり直します）: $e');
        final alreadyNotified = stoppedAtMs == _failedStoppedAtMs;
        _failedStoppedAtMs = stoppedAtMs;
        return PendingAlarmStopResult.failed(stoppedAt, alreadyNotified: alreadyNotified);
      }
      print('[WakeUpService] ✅ 停止時刻での起床処理が完了しました');
      await _removeStoppedAt(prefs);
      return PendingAlarmStopResult.fromWakeUp(result);
    } catch (e) {
      print('[WakeUpService] ❌ 停止時刻の処理エラー: $e');
      return PendingAlarmStopResult.notProcessed;
    } finally {
      _isProcessingPendingStop = false;
    }
  }

  /// N142：この停止時刻で起床処理をしない理由（するなら null）
  static String? _stoppedAtDiscardReason(SleepProvider provider, DateTime stoppedAt) {
    final sleepStartTime = provider.sleepStartTime;
    if (!provider.isSleepingNow) return '睡眠中ではない';
    if (sleepStartTime == null) return '睡眠開始時刻がない';
    if (!stoppedAt.isAfter(sleepStartTime)) return '停止時刻が睡眠開始（$sleepStartTime）以前';
    if (stoppedAt.isAfter(DateTime.now())) return '停止時刻が未来';
    return null;
  }

  /// N142：停止時刻のキーを消す。消せなくても処理の結果は変えない
  /// （残っても次の確認で、睡眠中でなければ消える。睡眠中に戻っていても完了済みの記録は上書きしない）
  static Future<void> _removeStoppedAt(SharedPreferences prefs) async {
    _failedStoppedAtMs = null;
    try {
      if (!await prefs.remove(_alarmStoppedAtKey)) {
        debugPrint('[WakeUpService] ⚠️ 停止時刻のキーを消せませんでした');
      }
    } catch (e) {
      debugPrint('[WakeUpService] ⚠️ 停止時刻のキーを消せませんでした: $e');
    }
  }
}
