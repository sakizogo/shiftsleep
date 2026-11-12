// 起床アラームを決めて登録する（N19）
//
// 「今から寝る」と、睡眠中の起床時刻の変更・「設定を保存」から呼ぶ
// 判定は wake_alarm_choice.dart の純粋な関数。知らせるのは呼び出し元（wakeAlarmMessages）
import 'package:flutter/foundation.dart';
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/manual_wake_service.dart';
import 'package:shiftsleep/services/wake_alarm_choice.dart';

class WakeAlarmRegistrationService {
  static ShiftRepository _shiftRepository = ShiftRepository();

  /// テストで偽物の DB に差し替える
  @visibleForTesting
  static set shiftRepositoryForTest(ShiftRepository repository) => _shiftRepository = repository;

  /// 手動起床と今日のシフトから登録するアラームを決めて登録する
  /// - アラームが OFF なら何もしない
  /// - 手動起床がなければ main には触らない
  /// - pre だけのときは、pre を登録できてから古い main を取り消す（失敗しても 0 本にしないため）
  /// - 登録の失敗は結果で返す。手動起床の読み込みの例外だけは呼び出し元に投げる
  /// vibrateOnMain：main を登録できたら 1 秒バイブ（「今から寝る」だけ）
  /// settingsReadFailed：settings は読めなかったときの既定値（N118 2b：手動起床があれば必ず main も登録する）
  static Future<WakeAlarmRegistrationResult> register({
    required DateTime now,
    required AppSettings settings,
    required bool vibrateOnMain,
    bool settingsReadFailed = false,
  }) async {
    final manualWakeAt = await ManualWakeService.getActive();

    if (!await AlarmService.isAlarmEnabled()) {
      debugPrint('🔕 [WakeAlarmRegistration] アラームOFFのため登録しません');
      return WakeAlarmRegistrationResult(
        now: now,
        plan: WakeAlarmPlan.none,
        manualWakeAt: manualWakeAt,
        alarmDisabled: true,
        settingsReadFailed: settingsReadFailed,
      );
    }

    final minutesBefore = settings.alarmTimeBeforeShift;
    final read = await _readTodayPattern(now, minutesBefore);
    final preAlarmAt = todayPreAlarmAt(now: now, minutesBefore: minutesBefore, pattern: read.pattern);
    final plan = planWakeAlarms(
      manualWakeAt: manualWakeAt,
      shiftPreAlarmAt: preAlarmAt,
      keepMain: settingsReadFailed,
    );
    debugPrint('⏰ [WakeAlarmRegistration] $plan（手動: $manualWakeAt、出勤前: $preAlarmAt）');

    String? mainError;
    if (plan.includesMain) {
      try {
        mainError = await ManualWakeService.scheduleAlarm(
          target: manualWakeAt!,
          preAlarmMinutes: minutesBefore,
          selectedAlarmSound: settings.selectedAlarmSound,
          vibrate: vibrateOnMain,
        );
      } catch (e) {
        debugPrint('❌ [WakeAlarmRegistration] main を登録できませんでした: $e');
        mainError = _unexpectedErrorText;
      }
    }

    String? preError;
    if (plan.includesPre) {
      try {
        final errorCode = await AlarmService.scheduleAlarmForShift(
          shiftDate: DateTime(now.year, now.month, now.day),
          alarmTime: read.pattern!.startTime!,
          mainAlarmEnabled: false,  // ✅ ShiftPre: 出勤時刻ちょうどのアラームは登録しない
          preAlarmEnabled: true,
          preAlarmMinutes: minutesBefore,
          selectedAlarmSound: settings.selectedAlarmSound,
        );
        preError = AlarmService.alarmErrorMessage(errorCode);
      } catch (e) {
        debugPrint('❌ [WakeAlarmRegistration] pre を登録できませんでした: $e');
        preError = _unexpectedErrorText;
      }
    }

    if (plan == WakeAlarmPlan.preOnly && manualWakeAt != null && preError == null) {
      try {
        await ManualWakeService.cancelTodayAndTomorrow();
      } catch (e) {
        // 古い main が残っても早く鳴るだけで、pre は登録できているので知らせない
        debugPrint('❌ [WakeAlarmRegistration] 古い main を取り消せませんでした: $e');
      }
    }

    return WakeAlarmRegistrationResult(
      now: now,
      plan: plan,
      manualWakeAt: manualWakeAt,
      preAlarmAt: preAlarmAt,
      minutesBefore: minutesBefore,
      mainError: mainError,
      preError: preError,
      shiftsReadFailed: read.failed,
      settingsReadFailed: settingsReadFailed,
      patternMissing: read.missing,
      todayWorkStartAt: todayWorkStartAt(now: now, pattern: read.pattern),
    );
  }

  /// 今日のシフトのパターンを読む。シフトなし・休日 → pattern が null
  /// 読めなかったら failed（呼び出し元で「シフトなし」として進め、知らせる）
  /// N118 2b：行はあるのにパターンが見つからない（削除済み）→ missing（pre なしで進め、知らせる）
  /// 出勤前アラームが無効（0）なら、シフトは読まない
  static Future<({ShiftPatternModel? pattern, bool failed, bool missing})> _readTodayPattern(
      DateTime now, int minutesBefore) async {
    if (minutesBefore <= 0) return (pattern: null, failed: false, missing: false);
    try {
      final today = DateTime(now.year, now.month, now.day);
      final rows = await _shiftRepository.getShiftsForDateRange(today, today);
      if (rows.isEmpty) return (pattern: null, failed: false, missing: false);

      final patternId = rows.first['pattern_id'] as String;
      if (patternId == 'default_dayoff') return (pattern: null, failed: false, missing: false);

      final pattern = await _shiftRepository.getPatternById(patternId);
      if (pattern == null) {
        debugPrint('⚠️ [WakeAlarmRegistration] 今日のシフトのパターンが見つかりません（削除済み）: $patternId');
      }
      return (pattern: pattern, failed: false, missing: pattern == null);
    } catch (e) {
      debugPrint('❌ [WakeAlarmRegistration] 今日のシフトを読めませんでした: $e');
      return (pattern: null, failed: true, missing: false);
    }
  }

  static const String _unexpectedErrorText =
      '⚠️ 起床アラームを登録できませんでした。『起きる』→『今から寝る』をやり直してください';
}
