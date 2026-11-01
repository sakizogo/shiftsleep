import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/shift_load.dart';

// N118：loadBlockMessage・loadFailureMessage・shiftMapFromRows のテスト

void main() {
  group('loadBlockMessage', () {
    test('失敗している部分がなければ null（止めない）', () {
      expect(loadBlockMessage({}), isNull);
    });

    test('どれか 1 つでも失敗していれば止める文言', () {
      for (final part in ShiftLoadPart.values) {
        expect(
          loadBlockMessage({part}),
          '⚠️ シフトを読み込めていないため登録・保存できません。［再読み込み］を押してください',
        );
      }
    });

    test('全部失敗していても同じ文言', () {
      expect(loadBlockMessage(ShiftLoadPart.values.toSet()), isNotNull);
    });
  });

  group('loadFailureMessage', () {
    test('部分ごとに名前を入れる', () {
      final error = Exception('db');
      expect(loadFailureMessage(ShiftLoadPart.shifts, error), '❌ シフトの読み込みに失敗しました: Exception: db');
      expect(loadFailureMessage(ShiftLoadPart.patterns, error), '❌ パターンの読み込みに失敗しました: Exception: db');
      expect(loadFailureMessage(ShiftLoadPart.vacation, error), '❌ 有休の読み込みに失敗しました: Exception: db');
    });
  });

  group('shiftMapFromRows', () {
    final dayOff = ShiftPatternModel(
      id: 'default_dayoff',
      patternName: '休日',
      patternType: ShiftType.dayOff,
      colorIndex: 0,
    );
    final early = ShiftPatternModel(
      id: 'p_early',
      patternName: '早番',
      patternType: ShiftType.work,
      startTime: const TimeOfDay(hour: 7, minute: 0),
      endTime: const TimeOfDay(hour: 16, minute: 0),
      colorIndex: 1,
    );
    final patterns = [dayOff, early];

    test('行がなければ空の Map', () {
      expect(shiftMapFromRows([], patterns, dayOff), isEmpty);
    });

    test('日付は時刻を捨てたキー、パターンは pattern_id で決める', () {
      final map = shiftMapFromRows([
        {'shift_date': '2026-11-03', 'pattern_id': 'p_early'},
        {'shift_date': '2026-11-04', 'pattern_id': 'default_dayoff'},
      ], patterns, dayOff);
      expect(map.length, 2);
      expect(map[DateTime(2026, 11, 3)], same(early));
      expect(map[DateTime(2026, 11, 4)], same(dayOff));
    });

    test('pattern_id が null なら休日、見つからなければ削除済み（元の ID のまま）', () {
      final map = shiftMapFromRows([
        {'shift_date': '2026-11-05', 'pattern_id': null},
        {'shift_date': '2026-11-06', 'pattern_id': 'gone'},
      ], patterns, dayOff);
      expect(map[DateTime(2026, 11, 5)], same(dayOff));
      final deleted = map[DateTime(2026, 11, 6)]!;
      expect(deleted.isDeleted, isTrue);
      expect(deleted.id, 'gone');
    });

    test('パターンが既定だけ（パターンの読み込みに失敗）なら、出勤の日は削除済みになる', () {
      final map = shiftMapFromRows([
        {'shift_date': '2026-11-03', 'pattern_id': 'p_early'},
      ], [dayOff], dayOff);
      expect(map[DateTime(2026, 11, 3)]!.isDeleted, isTrue);
    });

    test('shift_date が読めない行があれば例外（今の表示を残すため）', () {
      expect(
        () => shiftMapFromRows([
          {'shift_date': 'broken', 'pattern_id': 'p_early'},
        ], patterns, dayOff),
        throwsFormatException,
      );
    });
  });
}
