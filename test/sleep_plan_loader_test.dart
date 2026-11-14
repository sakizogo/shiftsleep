// A-3 1/3：SleepPlanLoader（勤務・パターン・設定・寝方のタイプの読み込み）のテスト
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/sleep_plan.dart';
import 'package:shiftsleep/services/sleep_plan_loader.dart';
import 'package:shiftsleep/services/sleep_plan_settings_service.dart';

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

  // ===== A-4 1/3 =====
  group('A-4 1/3：ベースライン用の勤務（D83）と任意の設定', () {
    SleepPlanLoader loaderWith(Future<SleepPlanSettings> Function() loadPlanSettings) => SleepPlanLoader(
          shiftRepository: repository,
          loadPreference: () async => SleepStylePreference.auto,
          loadPlanSettings: loadPlanSettings,
        );

    test('5. ベースライン用に今日−29〜今日+6 を先に読み、目安用は今日−2〜今日+6 のまま', () async {
      final inputs = await loaderWith(() async => SleepPlanSettings.none).load(now);
      expect(SleepPlanLoader.baselineRangeStart(now), DateTime(2026, 10, 18));
      expect(repository.rangeStarts, [DateTime(2026, 10, 18), DateTime(2026, 11, 14)]);
      expect(repository.lastRangeEnd, DateTime(2026, 11, 22));
      expect(inputs.baselineShifts!.single.startAt, DateTime(2026, 11, 17, 8, 0));
      expect(inputs.shifts!.single.startAt, DateTime(2026, 11, 17, 8, 0));
    });

    test('6. ベースライン用が読めなければ null（目安用の一覧を使う。勤務の失敗にはしない）', () async {
      repository.failRangeStart = DateTime(2026, 10, 18);
      final inputs = await loaderWith(() async => SleepPlanSettings.none).load(now);
      expect(inputs.baselineShifts, isNull);
      expect(inputs.shiftsFailed, isFalse);
      expect(inputs.shifts, hasLength(1));
    });

    test('7. 目安用の勤務が読めなければ、ベースライン用も使わない', () async {
      repository.failRangeStart = DateTime(2026, 11, 14);
      final inputs = await loaderWith(() async => SleepPlanSettings.none).load(now);
      expect(inputs.shiftsFailed, isTrue);
      expect(inputs.baselineShifts, isNull);
    });

    test('8. 通勤・身支度・残業を読み、消えたパターンの残業は外す。目安の設定にも入る', () async {
      repository.settings = settingsWith(30);
      final inputs = await loaderWith(() async => const SleepPlanSettings(
            commute: Duration(minutes: 40),
            prep: Duration(minutes: 30),
            overtimeByPattern: {'p_day': Duration(hours: 1), 'p_gone': Duration(minutes: 90)},
          )).load(now);
      expect(inputs.commute, const Duration(minutes: 40));
      expect(inputs.prep, const Duration(minutes: 30));
      expect(inputs.overtimeByPattern, {'p_day': const Duration(hours: 1)});

      final options = inputs.planOptions;
      expect(options.alarmMinutesBefore, 30);
      expect(options.leadTime, const Duration(minutes: 70));
      expect(options.homeTime, const Duration(minutes: 40));
      expect(options.overtimeByPattern, {'p_day': const Duration(hours: 1)});
    });

    test('9. 任意の設定が読めなければ未設定（今までと同じ前置き）', () async {
      repository.settings = settingsWith(45);
      final inputs = await loaderWith(() async => throw Exception('prefs failed')).load(now);
      expect(inputs.commute, isNull);
      expect(inputs.prep, isNull);
      expect(inputs.overtimeByPattern, isEmpty);
      expect(inputs.planOptions.leadTime, const Duration(minutes: 45));
      expect(inputs.shiftsFailed, isFalse);
    });

    test('10. 既定では SleepPlanSettingsService から読む', () async {
      SharedPreferences.setMockInitialValues({
        SleepPlanSettingsService.commuteKey: 20,
        SleepPlanSettingsService.overtimeKey: '{"p_day": 60}',
      });
      final inputs = await loader().load(now);
      expect(inputs.commute, const Duration(minutes: 20));
      expect(inputs.prep, isNull);
      expect(inputs.overtimeByPattern, {'p_day': const Duration(hours: 1)});
    });

    test('11. 寝方のタイプだけを変えても、ほかの読み込んだものはそのまま', () async {
      final inputs = await loaderWith(() async => const SleepPlanSettings(
            commute: Duration(minutes: 40),
            overtimeByPattern: {'p_day': Duration(hours: 1)},
          )).load(now);
      final changed = inputs.withPreference(SleepStylePreference.lastMinute);
      expect(changed.preference, SleepStylePreference.lastMinute);
      expect(changed.shifts, same(inputs.shifts));
      expect(changed.baselineShifts, same(inputs.baselineShifts));
      expect(changed.commute, inputs.commute);
      expect(changed.prep, inputs.prep);
      expect(changed.overtimeByPattern, inputs.overtimeByPattern);
      expect(changed.alarmMinutesBefore, inputs.alarmMinutesBefore);
      expect(changed.settingsFailed, inputs.settingsFailed);
    });
  });
}
