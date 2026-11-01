// 「シフトを確定」のあとに取り消す・登録する出勤前アラーム（pre）の日（N117）
//
// replaceAllShifts が成功してから、古い行の日の pre を取り消し、新しいシフトの出勤日の pre を登録する
// 範囲は取り消し・登録とも「今日（含む）〜 rangeEnd（含む）」。日付は時刻を捨てて比べる
// DB・アラームには依存しない
import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// 確定のあとに取り消す日（cancel）と登録する日（schedule）
/// - cancel：古い行のうち今日〜rangeEnd の日（パターンの種類は問わない。取り消しは害がないため）
/// - schedule：新しい Map のうち今日〜rangeEnd で、出勤（work）で開始時刻がある日と、その開始時刻
///   （N104 の「削除済み」・休日・有休・半休は入らない）
/// どちらも日付順・重複なし。shift_date が読めない古い行は飛ばす
({List<DateTime> cancel, List<({DateTime date, TimeOfDay startTime})> schedule}) confirmAlarmPlan(
  List<({String shiftDate, String? patternId})> oldRows,
  Map<DateTime, ShiftPatternModel?> newMap,
  DateTime today,
  DateTime rangeEnd,
) {
  final first = _dateOnly(today);
  final last = _dateOnly(rangeEnd);
  bool inRange(DateTime date) => !date.isBefore(first) && !date.isAfter(last);

  final cancel = <DateTime>{};
  for (final row in oldRows) {
    final parsed = DateTime.tryParse(row.shiftDate);
    if (parsed == null) continue;
    final date = _dateOnly(parsed);
    if (inRange(date)) cancel.add(date);
  }

  final schedule = <DateTime, TimeOfDay>{};
  for (final entry in newMap.entries) {
    final pattern = entry.value;
    final startTime = pattern?.startTime;
    if (pattern == null || pattern.isDeleted || pattern.patternType != ShiftType.work || startTime == null) {
      continue;
    }
    final date = _dateOnly(entry.key);
    if (inRange(date)) schedule[date] = startTime;
  }

  final scheduleDates = schedule.keys.toList()..sort();
  return (
    cancel: cancel.toList()..sort(),
    schedule: [for (final date in scheduleDates) (date: date, startTime: schedule[date]!)],
  );
}
