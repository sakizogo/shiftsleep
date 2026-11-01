import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/pattern_usage.dart';

// N104：classifyPatternUsage（パターンを使っている日を今日以降と過去に分ける）
// と resolvePatternForShift（pattern_id からパターンを決める）のテスト

void main() {
  group('resolvePatternForShift', () {
    // シフト管理画面と同じ既定パターン＋ユーザーのパターン
    final dayOff = ShiftPatternModel(
      id: 'default_dayoff',
      patternName: '休日',
      patternType: ShiftType.dayOff,
      colorIndex: 0,
    );
    final vacation1Day = ShiftPatternModel(
      id: 'default_vacation_1day',
      patternName: '有休',
      patternType: ShiftType.vacation,
      colorIndex: 3,
    );
    final vacationHalf = ShiftPatternModel(
      id: 'default_vacation_half',
      patternName: '半休',
      patternType: ShiftType.halfVacation,
      colorIndex: 4,
    );
    final dayShift = ShiftPatternModel(
      id: '1760000000000',
      patternName: '日勤',
      patternType: ShiftType.work,
      startTime: const TimeOfDay(hour: 8, minute: 30),
      endTime: const TimeOfDay(hour: 17, minute: 0),
      colorIndex: 1,
    );
    final patterns = [dayOff, vacation1Day, vacationHalf, dayShift];

    test('1. 見つかる → そのパターン', () {
      final pattern = resolvePatternForShift('1760000000000', patterns, dayOff);
      expect(identical(pattern, dayShift), isTrue);
      expect(pattern.isDeleted, isFalse);
    });

    test('2. 見つからない → 削除済み（id は元のまま・出勤ではない・時刻なし）', () {
      final pattern = resolvePatternForShift('1750000000000', patterns, dayOff);
      expect(pattern.isDeleted, isTrue);
      expect(pattern.id, '1750000000000');
      expect(pattern.patternName, '削除済み');
      expect(pattern.patternType, isNot(ShiftType.work));
      expect(pattern.patternType, isNot(ShiftType.vacation));
      expect(pattern.patternType, isNot(ShiftType.halfVacation));
      expect(pattern.startTime, isNull);
      expect(pattern.color, ShiftPatternModel.deletedColor);
    });

    test('3. 既定パターンの ID → 削除済みにならない', () {
      expect(identical(resolvePatternForShift('default_dayoff', patterns, dayOff), dayOff), isTrue);
      expect(identical(resolvePatternForShift('default_vacation_1day', patterns, dayOff), vacation1Day), isTrue);
      expect(identical(resolvePatternForShift('default_vacation_half', patterns, dayOff), vacationHalf), isTrue);
    });

    test('4. 古い休日 ID（default_off_day）→ 今までどおり休日', () {
      final pattern = resolvePatternForShift('default_off_day', patterns, dayOff);
      expect(identical(pattern, dayOff), isTrue);
      expect(pattern.isDeleted, isFalse);
    });

    test('5. pattern_id が null → 今までどおり休日', () {
      expect(identical(resolvePatternForShift(null, patterns, dayOff), dayOff), isTrue);
    });

    test('6. パターンの一覧が空でも、既定の休日 ID 以外は削除済み', () {
      expect(resolvePatternForShift('1760000000000', [], dayOff).isDeleted, isTrue);
      expect(identical(resolvePatternForShift('default_off_day', [], dayOff), dayOff), isTrue);
    });
  });

  // 時刻つきでも日付だけで比べることを確かめるため、昼の時刻にしておく
  final today = DateTime(2026, 11, 1, 14, 30);

  test('1. 空のリスト：今日以降 0・過去 0・最初の日 null', () {
    final usage = classifyPatternUsage([], today);
    expect(usage.futureCount, 0);
    expect(usage.pastCount, 0);
    expect(usage.firstFutureDate, isNull);
  });

  test('2. 過去だけ：今日以降 0・過去の件数', () {
    final usage = classifyPatternUsage(['2026-10-01', '2026-10-15', '2026-10-31'], today);
    expect(usage.futureCount, 0);
    expect(usage.pastCount, 3);
    expect(usage.firstFutureDate, isNull);
  });

  test('3. 今日だけ：今日は今日以降に含める', () {
    final usage = classifyPatternUsage(['2026-11-01'], today);
    expect(usage.futureCount, 1);
    expect(usage.pastCount, 0);
    expect(usage.firstFutureDate, '2026-11-01');
  });

  test('4. 未来と過去が混ざる：それぞれの件数と、未来のいちばん早い日', () {
    final usage = classifyPatternUsage(
      ['2026-09-30', '2026-10-31', '2026-11-02', '2026-12-10', '2027-01-05'],
      today,
    );
    expect(usage.futureCount, 3);
    expect(usage.pastCount, 2);
    expect(usage.firstFutureDate, '2026-11-02');
  });

  test('5. 並びがばらばらでも、未来のいちばん早い日を返す', () {
    final usage = classifyPatternUsage(
      ['2027-01-05', '2026-10-31', '2026-11-20', '2026-11-03', '2026-09-30', '2026-12-10'],
      today,
    );
    expect(usage.futureCount, 4);
    expect(usage.pastCount, 2);
    expect(usage.firstFutureDate, '2026-11-03');
  });
}
