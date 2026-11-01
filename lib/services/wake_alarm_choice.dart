// 「今から寝る」で手動起床と出勤前アラームのどちらを登録するか（N4・N118）
//
// 出勤前アラームのほうが早い（同時刻を含む）ときだけ出勤前、それ以外は手動起床
// シフトを読めなかったときは「出勤前アラームなし」として渡す（手動起床で鳴らす）
// DB・アラームには依存しない
enum WakeAlarmChoice { shiftPre, manual }

WakeAlarmChoice chooseWakeAlarm({
  required DateTime manualWakeAt,
  DateTime? shiftPreAlarmAt,
}) {
  if (shiftPreAlarmAt != null && !manualWakeAt.isBefore(shiftPreAlarmAt)) {
    return WakeAlarmChoice.shiftPre;
  }
  return WakeAlarmChoice.manual;
}
