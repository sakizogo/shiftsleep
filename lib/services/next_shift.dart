// シフトの実際の開始・終了の日時（N180）
//
// 0:00〜4:59 に始まる勤務は「前の日」の欄に登録する決まり（例：月曜の欄の 0:00 開始は、火曜の 0:00 から働く）
// そのため、開始が境目（nextDayStartBoundary）より前なら、登録した日の翌日に始まるとして扱う
// 終了が開始以下（同じ時刻を含む）なら、開始の翌日に終わるとして扱う
// DB・アラームには依存しない
import 'package:flutter/material.dart';

/// これより前に始まる勤務は、登録した日の翌日に始まる（5:00。5:00 ちょうどは当日）
const TimeOfDay nextDayStartBoundary = TimeOfDay(hour: 5, minute: 0);

int _minutesOf(TimeOfDay time) => time.hour * 60 + time.minute;

/// 勤務が実際に始まる日時
/// - shiftDate は登録した日（時刻は捨てる）
/// - 開始が boundary より前なら翌日、boundary 以後なら当日
DateTime shiftStartDateTime(
  DateTime shiftDate,
  TimeOfDay startTime, {
  TimeOfDay boundary = nextDayStartBoundary,
}) {
  final dayOffset = _minutesOf(startTime) < _minutesOf(boundary) ? 1 : 0;
  return DateTime(
    shiftDate.year,
    shiftDate.month,
    shiftDate.day + dayOffset,
    startTime.hour,
    startTime.minute,
  );
}

/// 勤務が実際に終わる日時
/// - startAt は shiftStartDateTime で求めた開始の日時
/// - 終了が開始より後なら開始と同じ日、開始以下なら開始の翌日（開始＝終了は 24 時間の勤務）
/// - endTime が null なら null
DateTime? shiftEndDateTime(DateTime startAt, TimeOfDay? endTime) {
  if (endTime == null) return null;
  final startMinutes = startAt.hour * 60 + startAt.minute;
  final dayOffset = _minutesOf(endTime) <= startMinutes ? 1 : 0;
  return DateTime(
    startAt.year,
    startAt.month,
    startAt.day + dayOffset,
    endTime.hour,
    endTime.minute,
  );
}
