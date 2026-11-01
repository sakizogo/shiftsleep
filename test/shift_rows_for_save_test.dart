import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';

// N117：ShiftRepository.shiftRowsForSave（確定で shifts に入れる行の一覧）のテスト

void main() {
  const now = '2026-11-01T10:00:00.000';
  final early = ShiftPatternModel(
    id: '1730000000000',
    patternName: '早番',
    patternType: ShiftType.work,
    startTime: const TimeOfDay(hour: 7, minute: 0),
    endTime: const TimeOfDay(hour: 16, minute: 0),
    colorIndex: 1,
  );
  final dayOff = ShiftPatternModel(
    id: 'default_dayoff',
    patternName: '休日',
    patternType: ShiftType.dayOff,
    colorIndex: 0,
  );

  test('1. 1 日 1 行。列は shift_date・pattern_id・user_id・created_at・updated_at（id は入れない）', () {
    final rows = ShiftRepository.shiftRowsForSave({DateTime(2026, 11, 6): early}, now);
    expect(rows, [
      {
        'shift_date': '2026-11-06',
        'pattern_id': '1730000000000',
        'user_id': 'test_user',
        'created_at': now,
        'updated_at': now,
      },
    ]);
  });

  test('2. pattern が null の日は飛ばす', () {
    final rows = ShiftRepository.shiftRowsForSave({
      DateTime(2026, 11, 6): early,
      DateTime(2026, 11, 7): null,
      DateTime(2026, 11, 8): dayOff,
    }, now);
    expect(rows.map((r) => r['shift_date']), ['2026-11-06', '2026-11-08']);
  });

  test('3. 日付は時刻を捨てた YYYY-MM-DD（月・日は 0 埋め、UTC の日付も年・月・日のまま）', () {
    final rows = ShiftRepository.shiftRowsForSave({
      DateTime(2027, 1, 2, 23, 59): early,
      DateTime.utc(2027, 3, 4): early,
    }, now);
    expect(rows.map((r) => r['shift_date']), ['2027-01-02', '2027-03-04']);
  });

  test('4. N104 の「削除済み」は元の pattern_id のまま入れる', () {
    final rows = ShiftRepository.shiftRowsForSave(
      {DateTime(2026, 10, 1): ShiftPatternModel.deleted('1700000000000')},
      now,
    );
    expect(rows.single['pattern_id'], '1700000000000');
  });

  test('5. 空の Map → 行なし', () {
    expect(ShiftRepository.shiftRowsForSave({}, now), isEmpty);
  });
}
