import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/confirm_alarm_plan.dart';

// N117：confirmAlarmPlan（確定のあとに取り消す・登録する pre の日）のテスト

void main() {
  final today = DateTime(2026, 11, 2);
  final rangeEnd = DateTime(2028, 12, 31);
  final early = ShiftPatternModel(
    id: '1730000000000',
    patternName: '早番',
    patternType: ShiftType.work,
    startTime: const TimeOfDay(hour: 7, minute: 0),
    endTime: const TimeOfDay(hour: 16, minute: 0),
    colorIndex: 1,
  );
  final workWithoutTime = ShiftPatternModel(
    id: '1730000000001',
    patternName: '時刻なし',
    patternType: ShiftType.work,
    colorIndex: 2,
  );
  final dayOff = ShiftPatternModel(id: 'default_dayoff', patternName: '休日', patternType: ShiftType.dayOff, colorIndex: 0);
  final vacation = ShiftPatternModel(id: 'default_vacation_1day', patternName: '有休', patternType: ShiftType.vacation, colorIndex: 3);
  final halfVacation = ShiftPatternModel(id: 'default_vacation_half', patternName: '半休', patternType: ShiftType.halfVacation, colorIndex: 4);

  ({String shiftDate, String? patternId}) row(String date) => (shiftDate: date, patternId: '1730000000000');

  test('1. 過去の日の古い行は cancel に入らない／今日は入る', () {
    final plan = confirmAlarmPlan([row('2026-11-01'), row('2026-11-02'), row('2026-11-03')], {}, today, rangeEnd);
    expect(plan.cancel, [DateTime(2026, 11, 2), DateTime(2026, 11, 3)]);
  });

  test('2. rangeEnd より後は cancel にも schedule にも入らない（rangeEnd の日は入る）', () {
    final plan = confirmAlarmPlan(
      [row('2028-12-31'), row('2029-01-01')],
      {DateTime(2028, 12, 31): early, DateTime(2029, 1, 1): early},
      today,
      rangeEnd,
    );
    expect(plan.cancel, [DateTime(2028, 12, 31)]);
    expect(plan.schedule.map((s) => s.date), [DateTime(2028, 12, 31)]);
  });

  test('3. 出勤で開始時刻がある日だけ schedule に入る（開始時刻も渡す）', () {
    final plan = confirmAlarmPlan([], {
      DateTime(2026, 11, 5): early,
      DateTime(2026, 11, 6): workWithoutTime,
      DateTime(2026, 11, 7): null,
    }, today, rangeEnd);
    expect(plan.schedule.length, 1);
    expect(plan.schedule.single.date, DateTime(2026, 11, 5));
    expect(plan.schedule.single.startTime, const TimeOfDay(hour: 7, minute: 0));
  });

  test('4. 「削除済み」・休日・有休・半休は schedule に入らない', () {
    final plan = confirmAlarmPlan([], {
      DateTime(2026, 11, 5): ShiftPatternModel.deleted('1700000000000'),
      DateTime(2026, 11, 6): dayOff,
      DateTime(2026, 11, 7): vacation,
      DateTime(2026, 11, 8): halfVacation,
    }, today, rangeEnd);
    expect(plan.schedule, isEmpty);
  });

  test('5. 古い行にあり新しい Map にない日（消した日）は cancel に入り、schedule には入らない', () {
    final plan = confirmAlarmPlan(
      [row('2026-11-05'), row('2026-11-06')],
      {DateTime(2026, 11, 5): early},
      today,
      rangeEnd,
    );
    expect(plan.cancel, [DateTime(2026, 11, 5), DateTime(2026, 11, 6)]);
    expect(plan.schedule.map((s) => s.date), [DateTime(2026, 11, 5)]);
  });

  test('N140 3/4：出勤を有休にした日は取り消して登録せず、有休を出勤にした日は登録する', () {
    final plan = confirmAlarmPlan(
      [
        (shiftDate: '2026-11-05', patternId: early.id),
        (shiftDate: '2026-11-06', patternId: vacation.id),
      ],
      {DateTime(2026, 11, 5): vacation, DateTime(2026, 11, 6): early},
      today,
      rangeEnd,
    );
    expect(plan.cancel, [DateTime(2026, 11, 5), DateTime(2026, 11, 6)]);
    expect(plan.schedule.map((s) => s.date), [DateTime(2026, 11, 6)]);
  });

  test('6. 日付は時刻を捨てて比べる（今日の時刻つき・UTC のキーも今日として扱う）', () {
    final plan = confirmAlarmPlan(
      [row('2026-11-02')],
      {DateTime(2026, 11, 2, 23, 59): early, DateTime.utc(2026, 11, 3): early},
      DateTime(2026, 11, 2, 15, 30),
      rangeEnd,
    );
    expect(plan.cancel, [DateTime(2026, 11, 2)]);
    expect(plan.schedule.map((s) => s.date), [DateTime(2026, 11, 2), DateTime(2026, 11, 3)]);
  });

  test('7. 読めない shift_date は飛ばし、同じ日の古い行が二つあっても cancel は 1 回', () {
    final plan = confirmAlarmPlan([row('不正'), row('2026-11-05'), row('2026-11-05')], {}, today, rangeEnd);
    expect(plan.cancel, [DateTime(2026, 11, 5)]);
  });

  // N180 3/3：startAt は shiftStartDateTime（0:00〜4:59 開始は登録した日の翌日）
  test('N180 3/3：startAt は実際の開始。月曜の欄の 0:00 開始は火曜 0:00、7:00 開始は当日', () {
    final zero = ShiftPatternModel(
      id: '1730000000002',
      patternName: '深夜',
      patternType: ShiftType.work,
      startTime: const TimeOfDay(hour: 0, minute: 0),
      endTime: const TimeOfDay(hour: 9, minute: 0),
    );
    final plan = confirmAlarmPlan([], {DateTime(2026, 11, 16): zero, DateTime(2026, 11, 17): early}, today, rangeEnd);
    expect(plan.schedule.map((s) => s.date), [DateTime(2026, 11, 16), DateTime(2026, 11, 17)]);
    expect(plan.schedule.map((s) => s.startAt), [DateTime(2026, 11, 17, 0, 0), DateTime(2026, 11, 17, 7, 0)]);
  });

  test('N180 3/3：呼び出し元が昨日を渡すと、昨日の欄も cancel・schedule に入る', () {
    final yesterday = DateTime(2026, 11, 1);
    final plan = confirmAlarmPlan([row('2026-10-31'), row('2026-11-01')], {yesterday: early}, yesterday, rangeEnd);
    expect(plan.cancel, [yesterday]);
    expect(plan.schedule.map((s) => s.date), [yesterday]);
  });
}
