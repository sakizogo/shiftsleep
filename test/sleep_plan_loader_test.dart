// A-3 1/3：SleepPlanLoader（勤務・パターン・設定・寝方のタイプの読み込み）のテスト
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/sleep_plan.dart';
import 'package:shiftsleep/services/sleep_plan_loader.dart';

import 'fakes/fake_shift_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 11, 16, 15, 0);  // 月曜
  final dayD = ShiftPatternModel(
    id: 'p_day',
    patternName: '日勤',
    patternType: ShiftType.work,
    startTime: const TimeOfDay(hour: 8, minute: 0),
    endTime: const TimeOfDay(hour: 17, minute: 0),
    colorIndex: 1,
  );

  late FakeShiftRepository repository;

  SleepPlanLoader loader({SleepStylePreference preference = SleepStylePreference.auto}) =>
      SleepPlanLoader(shiftRepository: repository, loadPreference: () async => preference);

  AppSettings settingsWith(int minutes) => AppSettings(
        id: 1,
        userId: 'test_user',
        alarmTimeBeforeShift: minutes,
        createdAt: now,
        updatedAt: now,
      );

  setUp(() {
    repository = FakeShiftRepository()
      ..rows = [
        {'shift_date': '2026-11-17', 'pattern_id': 'p_day'},
      ]
      ..patterns = [dayD];
  });

  test('1. 勤務は今日−2〜今日+6 を読み、勤務の一覧にする', () async {
    final inputs = await loader().load(now);
    expect(repository.lastRangeStart, DateTime(2026, 11, 14));
    expect(repository.lastRangeEnd, DateTime(2026, 11, 22));
    expect(SleepPlanLoader.rangeStart(now), DateTime(2026, 11, 14));
    expect(SleepPlanLoader.rangeEnd(now), DateTime(2026, 11, 22));
    expect(inputs.shiftsFailed, isFalse);
    expect(inputs.shifts!.single.startAt, DateTime(2026, 11, 17, 8, 0));
  });

  test('2. 勤務・パターンが読めなければ shifts は null（勤務の失敗）', () async {
    repository.failShifts = true;
    final noShifts = await loader().load(now);
    expect(noShifts.shifts, isNull);
    expect(noShifts.shiftsFailed, isTrue);

    repository
      ..failShifts = false
      ..failPatterns = true;
    expect((await loader().load(now)).shiftsFailed, isTrue);

    // shift_date が読めない行も読み込みの失敗
    repository
      ..failPatterns = false
      ..rows = [
        {'shift_date': 'broken', 'pattern_id': 'p_day'},
      ];
    expect((await loader().load(now)).shiftsFailed, isTrue);
  });

  test('3. 設定の行がなければ 30 分、あればその分数、読めなければ 30 分と設定の失敗', () async {
    final noRow = await loader().load(now);
    expect(noRow.alarmMinutesBefore, defaultAlarmMinutesBefore);
    expect(noRow.alarmMinutesBefore, 30);
    expect(noRow.settingsFailed, isFalse);

    repository.settings = settingsWith(45);
    final withRow = await loader().load(now);
    expect(withRow.alarmMinutesBefore, 45);
    expect(withRow.settingsFailed, isFalse);

    repository.failSettings = true;
    final failed = await loader().load(now);
    expect(failed.alarmMinutesBefore, 30);
    expect(failed.settingsFailed, isTrue);
    expect(failed.shiftsFailed, isFalse);  // 勤務は読めている
  });

  test('4. 寝方のタイプは設定のサービスから読む', () async {
    expect((await loader(preference: SleepStylePreference.lastMinute).load(now)).preference,
        SleepStylePreference.lastMinute);
    expect((await loader().load(now)).preference, SleepStylePreference.auto);
  });
}
