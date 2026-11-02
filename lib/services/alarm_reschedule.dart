// 設定でアラームを ON に戻したときの、出勤前アラーム（pre）の登録し直し（N123）
//
// H4 の OFF は登録済みの main / pre をすべて取り消すため、ON に戻したら DB のシフトから pre を登録し直す
// 登録する日は確定（N117）と同じ confirmAlarmPlan で決め、すでに過ぎた pre は除く（件数に入れないため）
// DB・アラームには依存しない
import 'package:flutter/material.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/confirm_alarm_plan.dart';
import 'package:shiftsleep/services/shift_load.dart';

/// 登録し直す pre の日・開始時刻・鳴る時刻
/// - rows は shifts の行（shift_date・pattern_id）。パターンは shiftMapFromRows で決める
/// - 出勤（work）で開始時刻がある、今日〜rangeEnd の日（confirmAlarmPlan の schedule と同じ）
/// - preAt（日付＋開始時刻−minutesBefore）が now より後の日だけ（開始 0:30 なら前日に鳴ることもある）
/// - minutesBefore が 0 以下（無効）なら空
/// - shift_date が読めない行があれば例外（shiftMapFromRows。読み込みの失敗として扱う）
List<({DateTime date, TimeOfDay startTime, DateTime preAt})> preAlarmRescheduleTargets(
  List<Map<String, dynamic>> rows,
  List<ShiftPatternModel> patterns,
  ShiftPatternModel dayOffPattern,
  int minutesBefore,
  DateTime now,
  DateTime rangeEnd,
) {
  final map = shiftMapFromRows(rows, patterns, dayOffPattern);
  if (minutesBefore <= 0) return [];
  final plan = confirmAlarmPlan(const [], map, now, rangeEnd);
  final targets = <({DateTime date, TimeOfDay startTime, DateTime preAt})>[];
  for (final shift in plan.schedule) {
    final preAt = DateTime(
      shift.date.year,
      shift.date.month,
      shift.date.day,
      shift.startTime.hour,
      shift.startTime.minute,
    ).subtract(Duration(minutes: minutesBefore));
    if (preAt.isAfter(now)) {
      targets.add((date: shift.date, startTime: shift.startTime, preAt: preAt));
    }
  }
  return targets;
}

/// 各件の scheduleAlarmForShift の戻り値（null=成功）から、成功件数と知らせるエラーコードを決める
/// エラーコードは EXACT_ALARM_DENIED を優先し、なければ最後のエラー（確定と同じ）
({int count, String? errorCode}) summarizeRescheduleResults(List<String?> codes) {
  var count = 0;
  String? errorCode;
  for (final code in codes) {
    if (code == null) {
      count++;
    } else if (errorCode != 'EXACT_ALARM_DENIED') {
      errorCode = code;
    }
  }
  return (count: count, errorCode: errorCode);
}

/// 登録し直したあとの SnackBar の文言と色（color が null なら既定の色）
/// 優先順：読めなかった → 分が 0 → エラー（AlarmService.alarmErrorMessage の文言） → 0 件 → 成功
/// - readFailed：設定・シフト・パターン・行の変換のどれかが読めなかった（スイッチは ON のまま）
/// - errorMessage：エラーのときの文言（件数は出さない）
({String text, Color? color}) rescheduleMessage({
  required int count,
  required String? errorMessage,
  required bool readFailed,
  required bool alarmDisabled,
}) {
  if (readFailed) {
    return (
      text: '⚠️ 出勤前アラームを登録し直せませんでした。もう一度 OFF → ON にするか、シフトを確定し直してください',
      color: Colors.orange,
    );
  }
  if (alarmDisabled) {
    return (text: 'ℹ️ 出勤前アラームは無効（0分）のため登録しません', color: null);
  }
  if (errorMessage != null) {
    return (text: errorMessage, color: Colors.orange);
  }
  if (count == 0) {
    return (text: 'ℹ️ 登録し直す出勤日はありません', color: null);
  }
  return (text: '✅ 出勤前アラームを $count件 登録し直しました', color: Colors.green);
}
