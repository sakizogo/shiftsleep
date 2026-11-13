// 出勤前アラーム（pre）を DB のシフトから登録し直す（N128 で設定画面の _reschedulePreAlarms から移した）
//
// 設定画面（ON に戻す N123・音の保存 N124・分数の変更 N125）と、
// ホーム画面（「アラームとリマインダー」が許可されたとき N128）から呼ぶ
// 知らせるのは呼び出し元。アラームが OFF かどうかも呼び出し元で確かめる
// （scheduleAlarmForShift は OFF だと成功扱いの null を返し、件数を誤って数えるため）
import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/calendar_range.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/services/alarm_reschedule.dart';
import 'package:shiftsleep/services/alarm_service.dart';

/// 登録し直した結果
/// - count：登録できた件数
/// - errorCode：EXACT_ALARM_DENIED を優先したエラーコード（なければ null）
/// - readFailed：設定・シフト・パターンのどれかを読めなかった
/// - alarmDisabled：分数が 0 以下（無効）
typedef PreAlarmRescheduleResult = ({int count, String? errorCode, bool readFailed, bool alarmDisabled});

class PreAlarmRescheduleService {
  /// shiftMapFromRows に渡す休日パターン（シフト管理画面の _defaultDayOffPattern と同じ中身）
  static final ShiftPatternModel dayOffPattern = ShiftPatternModel(
    id: 'default_dayoff',
    patternName: '休日',
    patternType: ShiftType.dayOff,
    colorIndex: 0,
  );

  /// 実行中の登録し直し（二重に走らせないため）
  static Future<PreAlarmRescheduleResult>? _running;

  /// DB の昨日〜CalendarRange の終わりの出勤日の pre を登録し直し、結果を返す（N180 3/3 で昨日から）
  /// 分数・音は DB から読み直す（行がなければ 30 分・'default'）。同じ ID で登録するので、登録済みの pre は上書きされる
  /// 実行中にもう一度呼ばれたら、新しく走らせずに実行中の結果（同じ Future）を返す
  static Future<PreAlarmRescheduleResult> reschedule() {
    final running = _running;
    if (running != null) {
      debugPrint('⏳ [PreAlarmReschedule] 実行中のため、実行中の結果を待ちます');
      return running;
    }
    final future = _reschedule().whenComplete(() => _running = null);
    _running = future;
    return future;
  }

  static Future<PreAlarmRescheduleResult> _reschedule() async {
    final shiftRepository = ShiftRepository();
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    var minutesBefore = 30;
    var selectedAlarmSound = 'default';
    var targets = <({DateTime date, TimeOfDay startTime, DateTime startAt, DateTime preAt})>[];
    var readFailed = false;
    try {
      final settings = await shiftRepository.getAppSettings('test_user');
      minutesBefore = settings?.alarmTimeBeforeShift ?? 30;
      selectedAlarmSound = settings?.selectedAlarmSound ?? 'default';
      if (minutesBefore > 0) {
        final rows = await shiftRepository.getShiftsForDateRange(yesterday, CalendarRange.lastDate);
        final patterns = await shiftRepository.getAllPatterns();
        targets = preAlarmRescheduleTargets(
          rows,
          patterns,
          dayOffPattern,
          minutesBefore,
          now,
          CalendarRange.lastDate,
        );
      }
    } catch (e) {
      debugPrint('❌ [PreAlarmReschedule] 設定・シフト・パターンを読めませんでした: $e');
      readFailed = true;
    }

    final codes = <String?>[];
    if (!readFailed) {
      for (final target in targets) {
        try {
          // N180 3/3：pre だけを、実際の開始（startAt）から登録する（確定と同じ）。ID は登録した日
          codes.add(await AlarmService.schedulePreAlarm(
            shiftDate: target.date,
            startAt: target.startAt,
            minutes: minutesBefore,
            selectedAlarmSound: selectedAlarmSound,
          ));
        } catch (e) {
          debugPrint('❌ [PreAlarmReschedule] pre を登録できませんでした (${target.date}): $e');
          codes.add('SCHEDULE_FAILED');
        }
      }
    }
    final result = summarizeRescheduleResults(codes);
    debugPrint('🔔 [PreAlarmReschedule] pre を ${result.count}/${targets.length}件 登録し直しました（音: $selectedAlarmSound、エラー: ${result.errorCode}）');
    return (
      count: result.count,
      errorCode: result.errorCode,
      readFailed: readFailed,
      alarmDisabled: minutesBefore <= 0,
    );
  }
}
