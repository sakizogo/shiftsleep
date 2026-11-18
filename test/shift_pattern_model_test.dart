import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';

// N116：calendarCellLabel（カレンダーのマスに出す短い名前）のテスト

void main() {
  group('calendarCellLabel', () {
    test('削除済みのパターンはマスでは「削除」', () {
      final deleted = ShiftPatternModel.deleted('1760000000000');
      expect(deleted.calendarCellLabel, '削除');
    });

    test('削除済みのパターンの名前（マス以外の表示）は「削除済み」のまま', () {
      final deleted = ShiftPatternModel.deleted('1760000000000');
      expect(deleted.patternName, '削除済み');
    });

    test('ふつうのパターンは長い名前でもそのまま（省略はマスの Text に任せる）', () {
      final longName = ShiftPatternModel(
        id: '1760000000001',
        patternName: '長い名前の夜勤パターン',
        patternType: ShiftType.work,
        startTime: const TimeOfDay(hour: 22, minute: 0),
        endTime: const TimeOfDay(hour: 7, minute: 0),
        colorIndex: 2,
      );
      expect(longName.calendarCellLabel, '長い名前の夜勤パターン');
      expect(longName.calendarCellLabel, longName.patternName);
    });
  });
}
