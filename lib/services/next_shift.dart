// シフトの実際の開始・終了の日時（N180）
//
// 0:00〜4:59 に始まる勤務は「前の日」の欄に登録する決まり（例：月曜の欄の 0:00 開始は、火曜の 0:00 から働く）
// そのため、開始が境目（nextDayStartBoundary）より前なら、登録した日の翌日に始まるとして扱う
// 終了が開始以下（同じ時刻を含む）なら、開始の翌日に終わるとして扱う
// DB・アラームには依存しない
import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';

/// これより前に始まる勤務は、登録した日の翌日に始まる（5:00。5:00 ちょうどは当日）
const TimeOfDay nextDayStartBoundary = TimeOfDay(hour: 5, minute: 0);

int _minutesOf(TimeOfDay time) => time.hour * 60 + time.minute;

/// N180 3/3：パターン画面で、開始が 0:00〜4:59 のときに出勤時刻の下に出す説明
const String nextDayRegistrationHint = 'ℹ️ 0:00〜4:59 に始まる勤務は、前日の欄に登録してください（例：火曜の 0:00 から働くなら月曜の欄）';

/// N180 3/3：パターン一覧で、開始が 0:00〜4:59 のパターンの時刻に添える文言
const String nextDayRegistrationLabel = '（前日の欄に登録）';

/// 登録した日の翌日に始まる勤務か（開始が boundary より前。N180 3/3）
bool startsOnNextDay(TimeOfDay startTime, {TimeOfDay boundary = nextDayStartBoundary}) =>
    _minutesOf(startTime) < _minutesOf(boundary);

/// 勤務が実際に始まる日時
/// - shiftDate は登録した日（時刻は捨てる）
/// - 開始が boundary より前なら翌日、boundary 以後なら当日
DateTime shiftStartDateTime(
  DateTime shiftDate,
  TimeOfDay startTime, {
  TimeOfDay boundary = nextDayStartBoundary,
}) {
  final dayOffset = startsOnNextDay(startTime, boundary: boundary) ? 1 : 0;
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

// ===== A-1（1/2）：次の勤務・前の勤務（睡眠プラン用） =====

/// 準夜勤が始まる時刻（12:00。5:00〜11:59 開始は日勤）
const TimeOfDay eveningShiftStart = TimeOfDay(hour: 12, minute: 0);

/// 夜勤が始まる時刻（20:00。20:00〜4:59 開始は夜勤）
const TimeOfDay nightShiftStart = TimeOfDay(hour: 20, minute: 0);

/// 勤務の種類（開始時刻で分ける）
enum ShiftKind {
  /// 日勤（5:00〜11:59 開始）
  day,

  /// 準夜勤（12:00〜19:59 開始）
  evening,

  /// 夜勤（20:00〜4:59 開始。0:00〜4:59 開始は前日の欄に登録した勤務）
  night,
}

/// 開始時刻（実際の開始の時:分＝パターンの startTime）から勤務の種類を決める
/// - 境目：4:59 は夜勤・5:00 は日勤（nextDayStartBoundary）、11:59 は日勤・12:00 は準夜勤、19:59 は準夜勤・20:00 は夜勤
ShiftKind shiftKindOf(TimeOfDay startTime) {
  final minutes = _minutesOf(startTime);
  if (minutes < _minutesOf(nextDayStartBoundary) || minutes >= _minutesOf(nightShiftStart)) {
    return ShiftKind.night;
  }
  if (minutes < _minutesOf(eveningShiftStart)) return ShiftKind.day;
  return ShiftKind.evening;
}

/// 1 回分の勤務（実際に始まる・終わる日時つき）
class WorkShift {
  /// 登録した欄の日（時刻なし。0:00〜4:59 開始なら startAt の前日）
  final DateTime registeredDate;

  /// 元のパターン
  final ShiftPatternModel pattern;

  /// 実際に始まる日時（shiftStartDateTime）
  final DateTime startAt;

  /// 実際に終わる日時（shiftEndDateTime。終了時刻のないパターンは WorkShift にしないので null にならない）
  final DateTime endAt;

  /// 勤務の種類（shiftKindOf）
  final ShiftKind kind;

  const WorkShift({
    required this.registeredDate,
    required this.pattern,
    required this.startAt,
    required this.endAt,
    required this.kind,
  });

  @override
  String toString() => 'WorkShift(registeredDate: $registeredDate, pattern: ${pattern.id}, '
      'startAt: $startAt, endAt: $endAt, kind: $kind)';
}

/// 日付→パターンの Map（shiftMapFromRows で作ったもの）から、出勤の日だけを WorkShift にして開始の早い順に並べる
/// - 出勤（work）で、削除済みでなく、開始・終了の両方がある日だけ（休日・有休・半休パターン・null は入らない）
/// - 半休の日も、shifts に出勤が残っていれば勤務として数える（半休は有休の使用に入り、シフトと共存するため。N77）
/// - Map のキーの時刻は捨てる
List<WorkShift> workShiftsFromMap(Map<DateTime, ShiftPatternModel?> map) {
  final shifts = <WorkShift>[];
  for (final entry in map.entries) {
    final pattern = entry.value;
    if (pattern == null || pattern.isDeleted || pattern.patternType != ShiftType.work) continue;
    final startTime = pattern.startTime;
    final endTime = pattern.endTime;
    if (startTime == null || endTime == null) continue;
    final date = DateTime(entry.key.year, entry.key.month, entry.key.day);
    final startAt = shiftStartDateTime(date, startTime);
    shifts.add(WorkShift(
      registeredDate: date,
      pattern: pattern,
      startAt: startAt,
      endAt: shiftEndDateTime(startAt, endTime)!,
      kind: shiftKindOf(startTime),
    ));
  }
  shifts.sort((a, b) => a.startAt.compareTo(b.startAt));
  return shifts;
}

/// now から within（既定 48 時間）以内に始まる、いちばん早い勤務。なければ null
/// - 範囲は now < startAt <= now + within（ちょうど within 後に始まる勤務は含める）
/// - 勤務中（startAt <= now < endAt）・ちょうど now に始まる勤務は含めない
/// - 半休の日の出勤も勤務として数える（workShiftsFromMap）
WorkShift? nextWorkShift(
  DateTime now,
  Iterable<WorkShift> shifts, {
  Duration within = const Duration(hours: 48),
}) {
  final limit = now.add(within);
  WorkShift? best;
  for (final shift in shifts) {
    if (!shift.startAt.isAfter(now) || shift.startAt.isAfter(limit)) continue;
    if (best == null || shift.startAt.isBefore(best.startAt)) best = shift;
  }
  return best;
}

/// now までに終わった勤務のうち、いちばん遅く終わったもの（lookback 既定 48 時間までさかのぼる）。なければ null
/// - 範囲は now − lookback <= endAt <= now（ちょうど now に終わった勤務・ちょうど lookback 前に終わった勤務も含める）
/// - 勤務中（endAt > now）は含めない
/// - 勤務が重なるときは、始まりではなく終わりの遅いほう
/// - 半休の日の出勤も勤務として数える（workShiftsFromMap）
WorkShift? previousWorkShift(
  DateTime now,
  Iterable<WorkShift> shifts, {
  Duration lookback = const Duration(hours: 48),
}) {
  final from = now.subtract(lookback);
  WorkShift? best;
  for (final shift in shifts) {
    if (shift.endAt.isAfter(now) || shift.endAt.isBefore(from)) continue;
    if (best == null || shift.endAt.isAfter(best.endAt)) best = shift;
  }
  return best;
}
