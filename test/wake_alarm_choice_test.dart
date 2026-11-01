import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/wake_alarm_choice.dart';

// N118：chooseWakeAlarm（手動起床と出勤前アラームのどちらを登録するか）のテスト

void main() {
  final manual = DateTime(2026, 11, 3, 6, 30);

  test('出勤前アラームがない（シフトなし・読めなかった）なら手動起床', () {
    expect(chooseWakeAlarm(manualWakeAt: manual), WakeAlarmChoice.manual);
  });

  test('手動起床のほうが早ければ手動起床', () {
    expect(
      chooseWakeAlarm(manualWakeAt: manual, shiftPreAlarmAt: DateTime(2026, 11, 3, 7, 0)),
      WakeAlarmChoice.manual,
    );
  });

  test('同じ時刻なら出勤前アラーム', () {
    expect(
      chooseWakeAlarm(manualWakeAt: manual, shiftPreAlarmAt: manual),
      WakeAlarmChoice.shiftPre,
    );
  });

  test('出勤前アラームのほうが早ければ出勤前アラーム', () {
    expect(
      chooseWakeAlarm(manualWakeAt: manual, shiftPreAlarmAt: DateTime(2026, 11, 3, 6, 0)),
      WakeAlarmChoice.shiftPre,
    );
  });
}
