// A-3 1/3：buildSleepPlanCardModel（カードの表示の形）のテスト
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/next_shift.dart';
import 'package:shiftsleep/services/sleep_plan.dart';
import 'package:shiftsleep/services/sleep_plan_card_model.dart';
import 'package:shiftsleep/services/sleep_plan_loader.dart';

DateTime t(int day, int hour, [int minute = 0]) => DateTime(2026, 11, day, hour, minute);

TimeOfDay hm(int hour, int minute) => TimeOfDay(hour: hour, minute: minute);

ShiftPatternModel work(String name, TimeOfDay start, TimeOfDay end) => ShiftPatternModel(
      id: 'p_$name',
      patternName: name,
      patternType: ShiftType.work,
      startTime: start,
      endTime: end,
      colorIndex: 1,
    );

final dayD = work('日勤', hm(8, 0), hm(17, 0));
final nightNt = work('夜勤', hm(20, 0), hm(5, 0));

List<WorkShift> shiftsOf(Map<int, ShiftPatternModel> byDay) =>
    workShiftsFromMap({for (final entry in byDay.entries) t(entry.key, 0): entry.value});

SleepPlanInputs inputsOf(
  List<WorkShift>? shifts, {
  int alarmMinutesBefore = 60,
  bool settingsFailed = false,
  SleepStylePreference preference = SleepStylePreference.immediate,
}) =>
    SleepPlanInputs(
      shifts: shifts,
      alarmMinutesBefore: alarmMinutesBefore,
      settingsFailed: settingsFailed,
      preference: preference,
    );

SleepRecord rec(String id, DateTime start, DateTime end) => SleepRecord(
      id: id,
      userId: 'test_user',
      sleepDate: DateTime(start.year, start.month, start.day),
      sleepStartTime: start,
      sleepStartAuto: true,
      sleepEndTime: end,
      sleepEndAuto: false,
      wakeUpType: '',
      durationMinutes: end.difference(start).inMinutes,
      lastModifiedAt: start,
      canEditUntil: end.add(const Duration(days: 2)),
      createdAt: start,
      updatedAt: start,
    );

/// 11/5〜11/9 の 5 晩、23:00〜翌 7:00（8 時間）
final fiveNights = [
  for (var i = 0; i < 5; i++) rec('n$i', t(5 + i, 23), t(6 + i, 7)),
];

SleepPlanCardModel model(
  DateTime now,
  SleepPlanInputs inputs, {
  List<SleepRecord> records = const [],
  bool recordsFailed = false,
  bool isPremium = false,
  bool advicePromoVisible = true,
  DateTime? sleepingSince,
}) =>
    buildSleepPlanCardModel(
      inputs: inputs,
      records: records,
      recordsFailed: recordsFailed,
      now: now,
      isPremium: isPremium,
      advicePromoVisible: advicePromoVisible,
      sleepingSince: sleepingSince,
    );

void main() {
  final dayToDay = shiftsOf({16: dayD, 17: dayD});

  test('5. 無料：理由・追加の睡眠・3 日分は入れず、🔒 にする', () {
    final result = model(t(16, 18), inputsOf(dayToDay));
    expect(result.state, SleepPlanCardState.ready);
    expect(result.premiumLocked, isTrue);
    expect(result.showPremiumTeaser, isTrue);
    expect(result.premiumReasonLines, isEmpty);
    expect(result.premiumExtraLines, isEmpty);
    expect(result.premiumDays, isEmpty);
    expect(result.text!.mainLine, '今夜　寝る目安 0:00 ごろ → 起きる目安 翌 7:00 ごろ（7 時間）');
    expect(result.text!.reassurance, isNotEmpty);
  });

  test('6. プレミアム：🔒 にせず、理由と 3 日分を入れる', () {
    final result = model(t(16, 18), inputsOf(dayToDay), isPremium: true);
    expect(result.premiumLocked, isFalse);
    expect(result.showPremiumTeaser, isFalse);
    expect(result.premiumReasonLines, isNotEmpty);
    expect(result.premiumReasonLines, result.text!.reasonLines);
    expect(result.premiumDays, hasLength(3));
  });

  test('7. advicePromoVisible が false なら 🔒 の案内を出さない（中身も入れない）', () {
    final result = model(t(16, 18), inputsOf(dayToDay), advicePromoVisible: false);
    expect(result.showPremiumTeaser, isFalse);
    expect(result.premiumLocked, isTrue);
    expect(result.premiumReasonLines, isEmpty);
  });

  test('8. 設定の失敗・記録の失敗のときの ⚠️ の行', () {
    // 設定を読めず 30 分で計算：起きる目安は 7:30
    final settingsFailed = model(t(16, 18), inputsOf(dayToDay, alarmMinutesBefore: 30, settingsFailed: true));
    expect(settingsFailed.warnings, [sleepPlanSettingsFailedText]);
    expect(settingsFailed.plan!.main!.wakeAt, t(17, 7, 30));

    // 記録を読めなかったら、記録があっても使わず 7 時間（記録が少ない行は出さない）
    final recordsFailed = model(t(16, 18), inputsOf(dayToDay), records: fiveNights, recordsFailed: true);
    expect(recordsFailed.warnings, [sleepPlanRecordsFailedText]);
    expect(recordsFailed.plan!.main!.length, const Duration(hours: 7));
    expect(recordsFailed.fewRecordsLine, isNull);

    expect(model(t(16, 18), inputsOf(dayToDay)).warnings, isEmpty);
  });

  test('9. 記録が少ないときだけ、記録が少ない行を出す', () {
    expect(model(t(16, 18), inputsOf(dayToDay)).fewRecordsLine, sleepPlanFewRecordsText);
    final enough = model(t(16, 18), inputsOf(dayToDay), records: fiveNights);
    expect(enough.fewRecordsLine, isNull);
    expect(enough.plan!.main!.length, const Duration(hours: 8));
  });

  test('10. 勤務なし・勤務中・勤務の失敗', () {
    final noShift = model(t(16, 18), inputsOf(const []));
    expect(noShift.state, SleepPlanCardState.noShift);
    expect(noShift.text!.headline, 'この 2 日は勤務がありません');
    expect(noShift.showPremiumTeaser, isFalse);
    expect(noShift.fewRecordsLine, isNull);

    final inShift = model(t(17, 22), inputsOf(shiftsOf({16: nightNt, 17: nightNt})));
    expect(inShift.state, SleepPlanCardState.ready);
    expect(inShift.inShift, isTrue);
    expect(inShift.text!.statusLines.first, '勤務中です。終わったあとの目安です');

    final failed = model(t(16, 18), inputsOf(null));
    expect(failed.state, SleepPlanCardState.failed);
    expect(failed.warnings, [sleepPlanShiftsFailedText]);
    expect(failed.text, isNull);
    expect(failed.showPremiumTeaser, isFalse);
  });

  test('記録中の入眠時刻（sleepingSince）を使う', () {
    // 日勤前の main（0:00〜7:00）の中で、23:30 から寝ている
    final result = model(t(17, 1), inputsOf(dayToDay), sleepingSince: t(16, 23, 30));
    expect(result.plan!.main!.sleepAt, t(16, 23, 30));
    expect(result.text!.statusLines, ['おやすみ中です。起きる目安は 7:00 ごろです']);
  });

  // ===== A-4 1/3 =====
  group('A-4 1/3：通勤・身支度・いつもの残業・ベースライン用の勤務', () {
    test('通勤 40 分・身支度 30 分は目安の計算に入る（日勤前の起きる目安は 6:50）', () {
      const inputs = SleepPlanInputs(
        shifts: null,
        alarmMinutesBefore: 60,
        settingsFailed: false,
        preference: SleepStylePreference.immediate,
      );
      expect(inputs.planOptions.leadTime, const Duration(hours: 1));
      final withCommute = SleepPlanInputs(
        shifts: shiftsOf({16: dayD, 17: dayD}),
        alarmMinutesBefore: 60,
        settingsFailed: false,
        preference: SleepStylePreference.immediate,
        commute: const Duration(minutes: 40),
        prep: const Duration(minutes: 30),
      );
      final result = model(t(16, 18), withCommute);
      expect(result.plan!.main!.sleepAt, t(16, 23, 50));
      expect(result.plan!.main!.wakeAt, t(17, 6, 50));
    });

    // 夜勤（20:00〜5:00）明けに、登録どおりの終わりから 4 時間 30 分（残業 2 時間のあと 2 時間 30 分）で寝る記録が 3 件
    final pastNights = shiftsOf({1: nightNt, 3: nightNt, 5: nightNt, 11: nightNt});
    final afterNightRecords = [
      for (final day in [2, 4, 6]) rec('a$day', t(day, 9, 30), t(day, 16, 30)),
    ];
    final overtime = {nightNt.id: const Duration(hours: 2)};

    SleepPlanInputs autoInputs({List<WorkShift>? baselineShifts, Map<String, Duration> overtimeByPattern = const {}}) =>
        SleepPlanInputs(
          shifts: shiftsOf({11: nightNt}),  // 目安用（今日−2〜今日+6）には昔の夜勤が入らない
          alarmMinutesBefore: 60,
          settingsFailed: false,
          preference: SleepStylePreference.auto,
          baselineShifts: baselineShifts,
          overtimeByPattern: overtimeByPattern,
        );

    test('残業 2 時間・帰ってすぐ寝る人（勤務明けの記録 3 件）は、記録から「帰ってすぐ寝る」と判定される', () {
      final result =
          model(t(10, 12), autoInputs(baselineShifts: pastNights, overtimeByPattern: overtime), records: afterNightRecords);
      expect(result.plan!.style, SleepStyle.immediate);
      expect(result.plan!.styleSource, SleepStyleSource.records);
    });

    test('残業がなければ 4 時間 30 分は 3 時間を超えるので、記録からは決まらない', () {
      final result = model(t(10, 12), autoInputs(baselineShifts: pastNights), records: afterNightRecords);
      expect(result.plan!.styleSource, SleepStyleSource.fallback);
    });

    test('D83：ベースライン用の勤務がなければ、目安用の範囲には昔の夜勤がなく、記録からは決まらない', () {
      final result = model(t(10, 12), autoInputs(overtimeByPattern: overtime), records: afterNightRecords);
      expect(result.plan!.styleSource, SleepStyleSource.fallback);
    });
  });
}
