// A-4 1/3：SleepPlanSettingsService（通勤・身支度・パターンごとのいつもの残業の保存と読み込み）のテスト
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/services/sleep_plan_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const commuteKey = SleepPlanSettingsService.commuteKey;
  const prepKey = SleepPlanSettingsService.prepKey;
  const overtimeKey = SleepPlanSettingsService.overtimeKey;

  Duration m(int minutes) => Duration(minutes: minutes);

  test('1. 何も保存していなければ、すべて未設定', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SleepPlanSettingsService.load();
    expect(settings.commute, isNull);
    expect(settings.prep, isNull);
    expect(settings.overtimeByPattern, isEmpty);
  });

  test('2. 通勤・身支度を保存すると読める。null で未設定に戻る', () async {
    SharedPreferences.setMockInitialValues({});
    await SleepPlanSettingsService.saveCommute(m(40));
    await SleepPlanSettingsService.savePrep(m(30));
    var settings = await SleepPlanSettingsService.load();
    expect(settings.commute, m(40));
    expect(settings.prep, m(30));

    await SleepPlanSettingsService.saveCommute(null);
    settings = await SleepPlanSettingsService.load();
    expect(settings.commute, isNull);
    expect(settings.prep, m(30));
    expect((await SharedPreferences.getInstance()).containsKey(commuteKey), isFalse);
  });

  test('3. 選べる値は D76 のとおり', () {
    expect(commuteMinuteChoices.first, 10);
    expect(commuteMinuteChoices.last, 120);
    expect(commuteMinuteChoices, hasLength(12));
    expect(prepMinuteChoices.first, 10);
    expect(prepMinuteChoices.last, 90);
    expect(prepMinuteChoices, hasLength(9));
    expect(overtimeMinuteChoices, [30, 60, 90, 120, 150, 180, 210, 240]);
  });

  test('4. 選べない値は保存せず例外（前の値は残る）', () async {
    SharedPreferences.setMockInitialValues({commuteKey: 40});
    await expectLater(SleepPlanSettingsService.saveCommute(m(45)), throwsArgumentError);
    await expectLater(SleepPlanSettingsService.savePrep(m(100)), throwsArgumentError);
    await expectLater(SleepPlanSettingsService.saveOvertime('p_night', m(20)), throwsArgumentError);
    expect((await SleepPlanSettingsService.load()).commute, m(40));
  });

  test('5. 読めない・壊れた値は未設定（ほかの値は読める）', () async {
    SharedPreferences.setMockInitialValues({
      commuteKey: 45,  // 選べない分
      prepKey: '30',  // 型が違う
      overtimeKey: '{壊れた JSON',
    });
    var settings = await SleepPlanSettingsService.load();
    expect(settings.commute, isNull);
    expect(settings.prep, isNull);
    expect(settings.overtimeByPattern, isEmpty);

    SharedPreferences.setMockInitialValues({
      commuteKey: 0,
      prepKey: 20,
      overtimeKey: '[60]',  // Map ではない
    });
    settings = await SleepPlanSettingsService.load();
    expect(settings.commute, isNull);
    expect(settings.prep, m(20));
    expect(settings.overtimeByPattern, isEmpty);
  });

  test('6. 残業はパターンごとに保存し、選べない値のパターンだけ外す', () async {
    SharedPreferences.setMockInitialValues({
      overtimeKey: '{"p_night": 120, "p_day": 45, "p_evening": "60", "p_late": 60}',
    });
    final settings = await SleepPlanSettingsService.load();
    expect(settings.overtimeByPattern, {'p_night': m(120), 'p_late': m(60)});
  });

  test('7. 残業の保存はほかのパターンを残し、null でそのパターンだけ外す（空になればキーを消す）', () async {
    SharedPreferences.setMockInitialValues({});
    await SleepPlanSettingsService.saveOvertime('p_night', m(120));
    await SleepPlanSettingsService.saveOvertime('p_day', m(60));
    expect((await SleepPlanSettingsService.load()).overtimeByPattern, {'p_night': m(120), 'p_day': m(60)});

    await SleepPlanSettingsService.saveOvertime('p_night', m(90));
    expect((await SleepPlanSettingsService.load()).overtimeByPattern, {'p_night': m(90), 'p_day': m(60)});

    await SleepPlanSettingsService.saveOvertime('p_night', null);
    expect((await SleepPlanSettingsService.load()).overtimeByPattern, {'p_day': m(60)});

    await SleepPlanSettingsService.saveOvertime('p_day', null);
    expect((await SleepPlanSettingsService.load()).overtimeByPattern, isEmpty);
    expect((await SharedPreferences.getInstance()).containsKey(overtimeKey), isFalse);
  });

  test('8. 寝方のタイプなど、ほかのキーには触らない', () async {
    SharedPreferences.setMockInitialValues({'shiftsleep_sleep_style_preference': 'immediate'});
    await SleepPlanSettingsService.saveCommute(m(30));
    await SleepPlanSettingsService.saveOvertime('p_night', m(60));
    await SleepPlanSettingsService.saveCommute(null);
    await SleepPlanSettingsService.saveOvertime('p_night', null);
    expect((await SharedPreferences.getInstance()).getString('shiftsleep_sleep_style_preference'), 'immediate');
  });
}
