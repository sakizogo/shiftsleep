// 「起きる」で出勤前アラーム（pre）を取り消すかどうか（N180 2/3）
//
// 起きた時刻から 3 時間以内に鳴る pre だけを取り消す（すでに過ぎた pre も取り消す。害がないため）
// 夜勤前・準夜勤前の仮眠から起きたときに、その日のあとで鳴る pre を消さないため
// 対象は起きた日の欄の pre だけ（取り消す ID は今までと同じ。取り消すものが今より増えることはない）
// DB・アラームには依存しない
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/next_shift.dart';

/// 「起きる」で取り消す pre の範囲（起きた時刻からこの時間以内に鳴るもの。ちょうどを含む）
const Duration wakePreCancelWindow = Duration(hours: 3);

/// 登録されている pre が鳴る時刻（登録と同じ式：shiftStartDateTime の開始−minutesBefore 分。N180 3/3）
/// 0:00〜4:59 開始は登録した日の翌日に始まるので、月曜の欄の 0:00 開始・60 分前は月曜 23:00
/// 分数 0 以下・シフトなし（pattern が null）・削除済み・出勤以外・開始時刻なし → null（pre は登録されていない）
DateTime? registeredPreAlarmAt({
  required DateTime shiftDate,
  required ShiftPatternModel? pattern,
  required int minutesBefore,
}) {
  final startTime = pattern?.startTime;
  if (minutesBefore <= 0 || pattern == null || pattern.isDeleted) return null;
  if (pattern.patternType != ShiftType.work || startTime == null) return null;
  return shiftStartDateTime(shiftDate, startTime).subtract(Duration(minutes: minutesBefore));
}

/// 起きた時刻と pre が鳴る時刻から、pre を取り消すか決める
/// preAlarmAt が null（pre なし）なら取り消さない
bool shouldCancelPreOnWake({
  required DateTime wakeUpTime,
  required DateTime? preAlarmAt,
}) {
  if (preAlarmAt == null) return false;
  return !preAlarmAt.isAfter(wakeUpTime.add(wakePreCancelWindow));
}
