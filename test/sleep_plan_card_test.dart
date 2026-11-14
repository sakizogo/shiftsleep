// A-3 2/3：SleepPlanCard（ホームの睡眠の目安のカード）の widget テスト
import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/next_shift.dart';
import 'package:shiftsleep/services/sleep_plan.dart';
import 'package:shiftsleep/services/sleep_plan_card_model.dart';
import 'package:shiftsleep/services/sleep_plan_loader.dart';
import 'package:shiftsleep/services/sleep_plan_text.dart';
import 'package:shiftsleep/widgets/premium_lock_dialog.dart';
import 'package:shiftsleep/widgets/sleep_plan_card.dart';

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
  SleepStylePreference preference = SleepStylePreference.immediate,
}) =>
    SleepPlanInputs(shifts: shifts, alarmMinutesBefore: 60, settingsFailed: false, preference: preference);

/// 読み込みの偽物。results を順に返す（足りなければ最後のもの）。gate があれば、それが終わるまで待つ
class _ScriptedLoader extends SleepPlanLoader {
  _ScriptedLoader(this.results);

  final List<SleepPlanInputs> results;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<SleepPlanInputs> load(DateTime now) async {
    final index = calls < results.length ? calls : results.length - 1;
    calls++;
    final waiting = gate;
    if (waiting != null) await waiting.future;
    return results[index];
  }
}

class _NoRepository extends SleepRepository {}

/// SleepProvider の偽物（カードが読む値だけを持つ）
class _TestProvider extends SleepProvider {
  _TestProvider() : super(_NoRepository());

  List<SleepRecord> records = [];
  bool premium = false;
  bool promo = true;
  bool sleeping = false;
  DateTime? sleepingSince;
  bool loadFailed = false;

  @override
  List<SleepRecord> get last30DaysRecords => records;
  @override
  bool get isPremiumUser => premium;
  @override
  bool get advicePromoVisible => promo;
  @override
  bool get isSleepingNow => sleeping;
  @override
  DateTime? get sleepStartTime => sleepingSince;
  @override
  bool get sleepDataLoadFailed => loadFailed;

  void changed() => notifyListeners();
}

void main() {
  late _TestProvider provider;
  late DateTime now;
  late List<SleepStylePreference> saved;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = _TestProvider();
    now = t(16, 18);
    saved = [];
  });

  Future<void> pumpCard(
    WidgetTester tester,
    SleepPlanLoader loader, {
    Duration? tick,
    Future<void> Function(SleepStylePreference)? savePreference,
    ValueListenable<int>? pendingDraftCount,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SleepProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SleepPlanCard(
                loader: loader,
                clock: () => now,
                tick: tick,
                pendingDraftCount: pendingDraftCount,
                savePreference: savePreference ??
                    (preference) async {
                      saved.add(preference);
                    },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 終わりにカードを外す（タイマーを止める）
  Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  void toBackground(WidgetTester tester) {
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void toForeground(WidgetTester tester) {
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  final dayToDay = shiftsOf({16: dayD, 17: dayD});
  const mainDayToDay = '今夜　寝る目安 0:00 ごろ → 起きる目安 翌 7:00 ごろ（7 時間）';

  testWidgets('11. 読み込み中は「準備しています」', (tester) async {
    final loader = _ScriptedLoader([inputsOf(dayToDay)])..gate = Completer<void>();
    await pumpCard(tester, loader);
    expect(find.text(sleepPlanLoadingText), findsOneWidget);
    expect(find.text(mainDayToDay), findsNothing);

    loader.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text(sleepPlanLoadingText), findsNothing);
    expect(find.text(mainDayToDay), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('12. 無料：見出し・目安・一言・🔒 が見え、理由は見えない', (tester) async {
    await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]));
    expect(find.text('次の日勤に向けた目安'), findsOneWidget);
    expect(find.text('明日 8:00 からの「日勤」'), findsOneWidget);
    expect(find.text(mainDayToDay), findsOneWidget);
    expect(find.text(sleepReassuranceEnough), findsOneWidget);
    expect(find.text(sleepPlanFewRecordsText), findsOneWidget);
    expect(find.text(sleepPlanPremiumLabel), findsOneWidget);
    expect(find.text(sleepPlanPremiumTeaserText), findsOneWidget);
    expect(find.text(sleepPlanReasonsTitle), findsNothing);
    expect(find.textContaining(sleepPlanReasonText(SleepPlanReason.wakeForShift)), findsNothing);
    await unmount(tester);
  });

  testWidgets('13. プレミアム：理由と 3 日分が見え、🔒 がない（理由だけ最初から開く）', (tester) async {
    provider.premium = true;
    await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]));
    expect(find.text(sleepPlanPremiumLabel), findsNothing);
    expect(find.text(sleepPlanReasonsTitle), findsOneWidget);
    expect(find.text('・${sleepPlanReasonText(SleepPlanReason.wakeForShift)}'), findsOneWidget);
    expect(find.text(sleepPlanDaysTitle), findsOneWidget);
    expect(find.text('今日 11/16（月）'), findsNothing);

    await tester.tap(find.text(sleepPlanDaysTitle));
    await tester.pump();
    expect(find.text('今日 11/16（月）'), findsOneWidget);

    await tester.tap(find.text(sleepPlanReasonsTitle));
    await tester.pump();
    expect(find.text('・${sleepPlanReasonText(SleepPlanReason.wakeForShift)}'), findsNothing);
    await unmount(tester);
  });

  testWidgets('14. 勤務の失敗で ⚠️ と［再読み込み］が出て、押すと読み直す', (tester) async {
    final loader = _ScriptedLoader([inputsOf(null), inputsOf(dayToDay)]);
    await pumpCard(tester, loader);
    expect(find.text(sleepPlanShiftsFailedText), findsOneWidget);
    expect(find.text('再読み込み'), findsOneWidget);
    expect(loader.calls, 1);

    await tester.tap(find.text('再読み込み'));
    await tester.pump();
    await tester.pump();
    expect(loader.calls, 2);
    expect(find.text(sleepPlanShiftsFailedText), findsNothing);
    expect(find.text(mainDayToDay), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('15. 勤務なしは 1 行', (tester) async {
    await pumpCard(tester, _ScriptedLoader([inputsOf(const [])]));
    expect(find.text('この 2 日は勤務がありません。ふだんどおりに過ごせる日です'), findsOneWidget);
    expect(find.text(sleepPlanPremiumLabel), findsNothing);
    await unmount(tester);
  });

  testWidgets('16. 勤務中の文', (tester) async {
    now = t(17, 22);
    await pumpCard(tester, _ScriptedLoader([inputsOf(shiftsOf({16: nightNt, 17: nightNt}))]));
    expect(find.text('夜勤明けの目安'), findsOneWidget);
    expect(find.text('勤務中です。終わったあとの目安です'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('17. 寝方のタイプの［変える ›］→ シートで選ぶ → 保存され、目安が変わる', (tester) async {
    now = t(17, 5);
    await pumpCard(tester, _ScriptedLoader([inputsOf(shiftsOf({16: nightNt, 17: nightNt}))]));
    expect(find.text('今日　寝る目安 6:00 ごろ → 起きる目安 13:00 ごろ（7 時間）'), findsOneWidget);
    expect(find.text('寝方のタイプ：帰ってすぐ寝る（設定から）'), findsOneWidget);

    await tester.tap(find.text('変える ›'));
    await tester.pumpAndSettle();
    expect(find.text(sleepStyleSheetTitle), findsOneWidget);
    await tester.tap(find.text('出勤ぎりぎりまで寝る'));
    await tester.pumpAndSettle();

    expect(saved, [SleepStylePreference.lastMinute]);
    expect(find.text('今日　寝る目安 12:00 ごろ → 起きる目安 19:00 ごろ（7 時間）'), findsOneWidget);
    expect(find.text('寝方のタイプ：出勤ぎりぎりまで寝る（設定から）'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('18. 保存に失敗したら ⚠️（例外の中身は出さない）、目安は変わらない', (tester) async {
    now = t(17, 5);
    await pumpCard(
      tester,
      _ScriptedLoader([inputsOf(shiftsOf({16: nightNt, 17: nightNt}))]),
      savePreference: (_) async => throw StateError('disk full'),
    );
    await tester.tap(find.text('変える ›'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('出勤ぎりぎりまで寝る'));
    await tester.pumpAndSettle();

    expect(find.text(sleepStyleSaveFailedText), findsOneWidget);
    expect(find.textContaining('disk full'), findsNothing);
    expect(find.text('今日　寝る目安 6:00 ごろ → 起きる目安 13:00 ごろ（7 時間）'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('19. 時計が進んで分が変わると、状態の文が変わる（これから → 中にいる）', (tester) async {
    await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]), tick: const Duration(seconds: 20));
    expect(find.text('今から眠ると、起きる目安は 7:00 ごろです'), findsNothing);

    now = t(17, 1);
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('今から眠ると、起きる目安は 7:00 ごろです'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('20. SleepProvider の入眠（sleepStartTime）で「おやすみ中です」になる', (tester) async {
    now = t(17, 1);
    await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]));
    expect(find.text('今から眠ると、起きる目安は 7:00 ごろです'), findsOneWidget);

    provider
      ..sleeping = true
      ..sleepingSince = t(16, 23, 30)
      ..changed();
    await tester.pump();
    expect(find.text('おやすみ中です。起きる目安は 7:00 ごろです'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('21. アプリに戻ったら読み直す', (tester) async {
    final loader = _ScriptedLoader([inputsOf(dayToDay)]);
    await pumpCard(tester, loader);
    expect(loader.calls, 1);

    toBackground(tester);
    toForeground(tester);
    await tester.pump();
    await tester.pump();
    expect(loader.calls, 2);
    expect(find.text(mainDayToDay), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('22. 色だけでなく文字とアイコンで意味がわかる（🔒・⚠️）', (tester) async {
    await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]));
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.text(sleepPlanPremiumLabel), findsOneWidget);
    await unmount(tester);

    await pumpCard(tester, _ScriptedLoader([inputsOf(null)]));
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.textContaining('⚠️'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('23. 無料で 🔒 を押すとダイアログ。［プレミアム版に登録］で「準備中です」、［閉じる］で閉じる', (tester) async {
    await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]));

    await tester.tap(find.text(sleepPlanPremiumLabel));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.byIcon(Icons.lock)), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text(sleepPlanPremiumTeaserText)),
        findsOneWidget);

    await tester.tap(find.text('プレミアム版に登録'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(premiumComingSoonText), findsOneWidget);

    await tester.tap(find.text(sleepPlanPremiumLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await unmount(tester);
  });

  testWidgets('24. advicePromoVisible が false なら 🔒 の案内が出ない', (tester) async {
    provider.promo = false;
    await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]));
    expect(find.text(sleepPlanPremiumLabel), findsNothing);
    expect(find.byIcon(Icons.lock), findsNothing);
    expect(find.text(mainDayToDay), findsOneWidget);
    await unmount(tester);
  });

  group('A-3 3/3：F1・F2（鍵・メモは絵文字を付けず、アイコンと文字だけ）', () {
    testWidgets('F1：🔒 の案内は鍵のアイコン 1 つと「プレミアム」の文字だけ', (tester) async {
      await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]));
      expect(find.text('プレミアム'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.textContaining('🔒'), findsNothing);
      await unmount(tester);
    });

    testWidgets('F2：未確定の一言はアイコンと文字だけ（📝 を付けない）', (tester) async {
      await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]), pendingDraftCount: ValueNotifier<int>(1));
      expect(find.text('未確定のシフトがあります。確定すると目安に反映されます'), findsOneWidget);
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
      expect(find.textContaining('📝'), findsNothing);
      await unmount(tester);
    });
  });

  group('D72：未確定のシフトの一言', () {
    testWidgets('勤務ありの形：未確定があれば一言が出て、なければ出ない', (tester) async {
      final pending = ValueNotifier<int>(2);
      await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]), pendingDraftCount: pending);
      expect(find.text(mainDayToDay), findsOneWidget);
      expect(find.text(sleepPlanDraftPendingText), findsOneWidget);
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
      await unmount(tester);

      await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]), pendingDraftCount: ValueNotifier<int>(0));
      expect(find.text(sleepPlanDraftPendingText), findsNothing);
      await unmount(tester);

      // 渡されなければ出さない
      await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]));
      expect(find.text(sleepPlanDraftPendingText), findsNothing);
      await unmount(tester);
    });

    testWidgets('勤務なしの形：未確定があれば一言が出て、なければ出ない', (tester) async {
      await pumpCard(tester, _ScriptedLoader([inputsOf(const [])]), pendingDraftCount: ValueNotifier<int>(1));
      expect(find.text('この 2 日は勤務がありません。ふだんどおりに過ごせる日です'), findsOneWidget);
      expect(find.text(sleepPlanDraftPendingText), findsOneWidget);
      await unmount(tester);

      await pumpCard(tester, _ScriptedLoader([inputsOf(const [])]), pendingDraftCount: ValueNotifier<int>(0));
      expect(find.text(sleepPlanDraftPendingText), findsNothing);
      await unmount(tester);
    });

    testWidgets('未確定が確定・破棄されて 0 になると一言が消え、また入れると出る', (tester) async {
      final pending = ValueNotifier<int>(1);
      await pumpCard(tester, _ScriptedLoader([inputsOf(dayToDay)]), pendingDraftCount: pending);
      expect(find.text(sleepPlanDraftPendingText), findsOneWidget);

      pending.value = 0;  // ShiftDraftStore.clear（確定・破棄）で 0 になる
      await tester.pump();
      expect(find.text(sleepPlanDraftPendingText), findsNothing);
      expect(find.text(mainDayToDay), findsOneWidget);

      pending.value = 3;
      await tester.pump();
      expect(find.text(sleepPlanDraftPendingText), findsOneWidget);
      await unmount(tester);

      // 外したあとに値が変わっても落ちない（removeListener）
      pending.value = 0;
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('25. 外したあとにアプリに戻っても落ちない（removeObserver）', (tester) async {
    final loader = _ScriptedLoader([inputsOf(dayToDay)]);
    await pumpCard(tester, loader);
    await unmount(tester);

    toBackground(tester);
    toForeground(tester);
    await tester.pump();
    expect(loader.calls, 1);
    expect(tester.takeException(), isNull);
  });
}
