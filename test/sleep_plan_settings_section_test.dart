// A-4 2/3：設定画面の「😴 睡眠の目安」セクション（SleepPlanSettingsSection）のテスト
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/sleep_plan.dart';
import 'package:shiftsleep/services/sleep_plan_settings_service.dart';
import 'package:shiftsleep/widgets/sleep_plan_card.dart';
import 'package:shiftsleep/widgets/sleep_plan_settings_section.dart';

ShiftPatternModel pattern(String id, String name, ShiftType type) => ShiftPatternModel(
      id: id,
      patternName: name,
      patternType: type,
      startTime: type == ShiftType.work ? const TimeOfDay(hour: 8, minute: 0) : null,
      endTime: type == ShiftType.work ? const TimeOfDay(hour: 17, minute: 0) : null,
    );

final dayShift = pattern('p_day', '日勤', ShiftType.work);
final nightShift = pattern('p_night', '夜勤', ShiftType.work);
final dayOff = pattern('p_off', '休日', ShiftType.dayOff);
final vacation = pattern('p_vac', '有休', ShiftType.vacation);
final halfVacation = pattern('p_half', '半休', ShiftType.halfVacation);
final deleted = ShiftPatternModel.deleted('p_gone');

final allPatterns = [dayShift, dayOff, nightShift, vacation, halfVacation, deleted];

void main() {
  group('shouldShowSleepPlanAlarmInfo（ⓘ アラーム）', () {
    test('通勤・身支度がどちらも未設定なら出さない', () {
      expect(shouldShowSleepPlanAlarmInfo(alarmMinutesBefore: 30, commute: null, prep: null), isFalse);
    });

    test('アラームの分数が通勤＋身支度より小さい（アラームのほうが遅い）なら出す', () {
      expect(
        shouldShowSleepPlanAlarmInfo(
          alarmMinutesBefore: 50,
          commute: const Duration(minutes: 30),
          prep: const Duration(minutes: 30),
        ),
        isTrue,
      );
    });

    test('片方だけでも、その分より小さければ出す', () {
      expect(shouldShowSleepPlanAlarmInfo(alarmMinutesBefore: 30, commute: null, prep: const Duration(minutes: 40)), isTrue);
      expect(shouldShowSleepPlanAlarmInfo(alarmMinutesBefore: 30, commute: const Duration(minutes: 40), prep: null), isTrue);
    });

    test('同じ時刻・アラームのほうが早いなら出さない', () {
      expect(
        shouldShowSleepPlanAlarmInfo(
          alarmMinutesBefore: 60,
          commute: const Duration(minutes: 30),
          prep: const Duration(minutes: 30),
        ),
        isFalse,
      );
      expect(shouldShowSleepPlanAlarmInfo(alarmMinutesBefore: 90, commute: const Duration(minutes: 60), prep: null), isFalse);
    });

    test('アラームが無効（0）なら出さない', () {
      expect(shouldShowSleepPlanAlarmInfo(alarmMinutesBefore: 0, commute: const Duration(minutes: 60), prep: null), isFalse);
    });

    test('文は通勤＋身支度の分を「ごろ」で出す', () {
      expect(
        sleepPlanAlarmInfoText(commute: const Duration(minutes: 60), prep: const Duration(minutes: 30)),
        '出勤前アラームが、通勤と身支度から出した起きる目安（出勤の 1 時間 30 分前ごろ）より遅く鳴ります',
      );
    });
  });

  group('表示の小さな関数', () {
    test('残業は出勤のパターンだけ（休日・有休・半休・削除済みは外す）', () {
      expect(overtimeTargetPatterns(allPatterns), [dayShift, nightShift]);
    });

    test('分の表示', () {
      expect(sleepPlanMinutesLabel(const Duration(minutes: 30)), '30 分');
      expect(sleepPlanMinutesLabel(const Duration(minutes: 60)), '1 時間');
      expect(sleepPlanMinutesLabel(const Duration(minutes: 150)), '2 時間 30 分');
    });

    test('寝方のタイプ：自動は「自動」とだけ、ほかはシートと同じ名前', () {
      expect(sleepStyleSettingLabel(SleepStylePreference.auto), '自動');
      expect(sleepStyleSettingLabel(SleepStylePreference.immediate), '帰ってすぐ寝る');
      expect(sleepStyleSettingLabel(SleepStylePreference.lastMinute), '出勤ぎりぎりまで寝る');
    });
  });

  group('SleepPlanSettingsSection', () {
    late List<Duration?> commuteSaved;
    late List<Duration?> prepSaved;
    late List<(String, Duration?)> overtimeSaved;
    late List<SleepStylePreference> styleSaved;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      commuteSaved = [];
      prepSaved = [];
      overtimeSaved = [];
      styleSaved = [];
    });

    Future<void> pumpSection(
      WidgetTester tester, {
      int alarmMinutesBefore = 30,
      SleepPlanSettings settings = SleepPlanSettings.none,
      List<ShiftPatternModel>? patterns,
      bool patternsFail = false,
      SleepStylePreference preference = SleepStylePreference.auto,
      bool useRealSave = false,
      bool saveFails = false,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<void> fail() async => throw StateError('保存できない');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SleepPlanSettingsSection(
                alarmMinutesBefore: alarmMinutesBefore,
                loadSettings: useRealSave ? null : () async => settings,
                loadPatterns: () async {
                  if (patternsFail) throw StateError('読めない');
                  return patterns ?? allPatterns;
                },
                loadPreference: useRealSave ? null : () async => preference,
                saveCommute: useRealSave
                    ? null
                    : (value) async {
                        if (saveFails) return fail();
                        commuteSaved.add(value);
                      },
                savePrep: useRealSave ? null : (value) async => prepSaved.add(value),
                saveOvertime: useRealSave ? null : (id, value) async => overtimeSaved.add((id, value)),
                savePreference: useRealSave ? null : (value) async => styleSaved.add(value),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, Key key, String label) async {
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    String shownValue(WidgetTester tester, Key key) =>
        tester.widget<DropdownButton<int>>(find.byKey(key)).value == 0
            ? '未設定'
            : sleepPlanMinutesLabel(Duration(minutes: tester.widget<DropdownButton<int>>(find.byKey(key)).value!));

    const commuteKey = ValueKey('sleepPlanCommute');
    const prepKey = ValueKey('sleepPlanPrep');
    const alarmInfoKey = ValueKey('sleepPlanAlarmInfo');

    testWidgets('見出し・但し書き・ⓘ 残業を出す。未設定のときは「未設定」「なし」', (tester) async {
      await pumpSection(tester);
      expect(find.text(sleepPlanSettingsTitle), findsOneWidget);
      expect(find.text(sleepPlanSettingsNote), findsOneWidget);
      expect(find.text(sleepPlanOvertimeInfo), findsOneWidget);
      expect(shownValue(tester, commuteKey), '未設定');
      expect(shownValue(tester, prepKey), '未設定');
      expect(find.text('なし'), findsNWidgets(2));
      expect(find.byKey(alarmInfoKey), findsNothing);
    });

    testWidgets('読み込んだ値を出す', (tester) async {
      await pumpSection(
        tester,
        settings: const SleepPlanSettings(
          commute: Duration(minutes: 40),
          prep: Duration(minutes: 20),
          overtimeByPattern: {'p_night': Duration(minutes: 90)},
        ),
      );
      expect(shownValue(tester, commuteKey), '40 分');
      expect(shownValue(tester, prepKey), '20 分');
      expect(tester.widget<DropdownButton<int>>(find.byKey(const ValueKey('sleepPlanOvertime_p_night'))).value, 90);
      expect(tester.widget<DropdownButton<int>>(find.byKey(const ValueKey('sleepPlanOvertime_p_day'))).value, 0);
    });

    testWidgets('残業は出勤のパターンだけ並ぶ', (tester) async {
      await pumpSection(tester);
      expect(find.text('日勤'), findsOneWidget);
      expect(find.text('夜勤'), findsOneWidget);
      expect(find.text('休日'), findsNothing);
      expect(find.text('有休'), findsNothing);
      expect(find.text('半休'), findsNothing);
      expect(find.text('削除済み'), findsNothing);
      expect(find.byKey(const ValueKey('sleepPlanOvertime_p_off')), findsNothing);
    });

    testWidgets('出勤のパターンがないときはその旨を出す', (tester) async {
      await pumpSection(tester, patterns: [dayOff, vacation]);
      expect(find.text(sleepPlanNoWorkPatternText), findsOneWidget);
    });

    testWidgets('パターンを読めなかったときは ⚠️（アイコンと文）を出す', (tester) async {
      await pumpSection(tester, patternsFail: true);
      expect(find.text(sleepPlanPatternsLoadFailedText), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('通勤を選ぶとすぐ保存して SnackBar。未設定に戻せる', (tester) async {
      await pumpSection(tester);
      await choose(tester, commuteKey, '40 分');
      expect(commuteSaved, [const Duration(minutes: 40)]);
      expect(find.text('✅ 通勤を保存しました'), findsOneWidget);
      expect(shownValue(tester, commuteKey), '40 分');

      await choose(tester, commuteKey, '未設定');
      expect(commuteSaved, [const Duration(minutes: 40), null]);
      expect(shownValue(tester, commuteKey), '未設定');
    });

    testWidgets('身支度・残業・寝方のタイプも選ぶと保存する', (tester) async {
      await pumpSection(tester);
      await choose(tester, prepKey, '30 分');
      expect(prepSaved, [const Duration(minutes: 30)]);

      await choose(tester, const ValueKey('sleepPlanOvertime_p_night'), '1 時間 30 分');
      expect(overtimeSaved, [('p_night', const Duration(minutes: 90))]);
      expect(find.text('✅ 残業（夜勤）を保存しました'), findsOneWidget);

      await choose(tester, const ValueKey('sleepPlanOvertime_p_night'), 'なし');
      expect(overtimeSaved.last, ('p_night', null));
    });

    testWidgets('保存できなかったら ⚠️ の SnackBar（例外の中身は出さない）で、表示は変えない', (tester) async {
      await pumpSection(tester, saveFails: true);
      await choose(tester, commuteKey, '40 分');
      expect(find.text('⚠️ 通勤を保存できませんでした'), findsOneWidget);
      expect(find.textContaining('StateError'), findsNothing);
      expect(shownValue(tester, commuteKey), '未設定');
    });

    testWidgets('ⓘ アラーム：アラームのほうが遅いときだけ出る', (tester) async {
      await pumpSection(tester, alarmMinutesBefore: 30);
      expect(find.byKey(alarmInfoKey), findsNothing);

      await choose(tester, commuteKey, '20 分');
      // 20 分前 < アラーム 30 分前：アラームのほうが早いので出さない
      expect(find.byKey(alarmInfoKey), findsNothing);

      await choose(tester, prepKey, '20 分');
      // 40 分前 > アラーム 30 分前：アラームのほうが遅い
      expect(find.byKey(alarmInfoKey), findsOneWidget);
      expect(find.text(sleepPlanAlarmInfoText(commute: const Duration(minutes: 20), prep: const Duration(minutes: 20))),
          findsOneWidget);
    });

    testWidgets('ⓘ アラーム：アラームの分数（画面で今選んでいる値）が変わると出る・消える', (tester) async {
      const settings = SleepPlanSettings(commute: Duration(minutes: 60));
      await pumpSection(tester, alarmMinutesBefore: 30, settings: settings);
      expect(find.byKey(alarmInfoKey), findsOneWidget);

      await pumpSection(tester, alarmMinutesBefore: 60, settings: settings);
      expect(find.byKey(alarmInfoKey), findsNothing);

      await pumpSection(tester, alarmMinutesBefore: 0, settings: settings);
      expect(find.byKey(alarmInfoKey), findsNothing);
    });

    testWidgets('寝方のタイプ：自動は「自動」とだけ出し、カードと同じシートで選べる', (tester) async {
      await pumpSection(tester);
      final label = find.byKey(const ValueKey('sleepPlanStyleLabel'));
      expect(tester.widget<Text>(label).data, '自動');
      expect(find.text('自動（これまでの記録から）'), findsNothing);

      await tester.tap(find.text('変える ›'));
      await tester.pumpAndSettle();
      expect(find.text(sleepStyleSheetTitle), findsWidgets);
      expect(find.text('自動（これまでの記録から）'), findsOneWidget);
      await tester.tap(find.text('帰ってすぐ寝る'));
      await tester.pumpAndSettle();

      expect(styleSaved, [SleepStylePreference.immediate]);
      expect(tester.widget<Text>(label).data, '帰ってすぐ寝る');
      expect(find.text('✅ 寝方のタイプを保存しました'), findsOneWidget);
    });

    testWidgets('本物のサービスで保存し、開き直すと同じ値を読む', (tester) async {
      await pumpSection(tester, useRealSave: true);
      await choose(tester, commuteKey, '1 時間');
      await choose(tester, prepKey, '30 分');
      await choose(tester, const ValueKey('sleepPlanOvertime_p_day'), '2 時間');

      final loaded = await SleepPlanSettingsService.load();
      expect(loaded.commute, const Duration(minutes: 60));
      expect(loaded.prep, const Duration(minutes: 30));
      expect(loaded.overtimeByPattern, {'p_day': const Duration(minutes: 120)});

      await tester.pumpWidget(const SizedBox());
      await pumpSection(tester, useRealSave: true);
      expect(shownValue(tester, commuteKey), '1 時間');
      expect(shownValue(tester, prepKey), '30 分');
      expect(tester.widget<DropdownButton<int>>(find.byKey(const ValueKey('sleepPlanOvertime_p_day'))).value, 120);

      await choose(tester, commuteKey, '未設定');
      expect((await SleepPlanSettingsService.load()).commute, isNull);
    });
  });
}
