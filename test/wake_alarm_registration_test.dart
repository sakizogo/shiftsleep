// N19：WakeAlarmRegistrationService（起床アラームを決めて登録する）
//
// 実際の時計で「過去」と判定されないよう、now はすべて明日の日付にする
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/services/wake_alarm_choice.dart';
import 'package:shiftsleep/services/wake_alarm_registration_service.dart';

const _alarmChannel = MethodChannel('com.sakizoapps.shiftsleep/alarm');
const _notificationChannel = MethodChannel('dexterous.com/flutter/local_notifications');

/// DB の偽物
class _FakeShiftRepository extends ShiftRepository {
  List<Map<String, dynamic>> rows = [];
  ShiftPatternModel? pattern;
  bool failRead = false;
  int readCount = 0;

  @override
  Future<List<Map<String, dynamic>>> getShiftsForDateRange(DateTime startDate, DateTime endDate) async {
    readCount++;
    if (failRead) throw Exception('read failed');
    return rows;
  }

  @override
  Future<ShiftPatternModel?> getPatternById(String patternId) async => pattern;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeShiftRepository repository;
  late List<int> scheduledIds;
  late List<int> cancelledIds;
  late Set<int> armedIds;  // AlarmManager に入っている ID
  late List<String> events;  // 呼ばれた順
  late Set<int> failScheduleIds;
  late String failCode;
  late bool failCancel;

  final real = DateTime.now();
  final day = DateTime(real.year, real.month, real.day + 1);
  final now = DateTime(day.year, day.month, day.day, 9, 0);
  final mainId = _id(day, 0);
  final preId = _id(day, 1);

  AppSettings settings({int minutes = 30}) => AppSettings(
        id: 1,
        userId: 'test_user',
        alarmTimeBeforeShift: minutes,
        createdAt: now,
        updatedAt: now,
      );

  /// 今日（テストの now の日）に 15:00 始まりの出勤シフトを入れる（pre は 14:30）
  void workShift() {
    repository.rows = [
      {'shift_date': 'x', 'pattern_id': 'p'},
    ];
    repository.pattern = ShiftPatternModel(
      id: 'p',
      patternName: '3番',
      patternType: ShiftType.work,
      startTime: const TimeOfDay(hour: 15, minute: 0),
      endTime: const TimeOfDay(hour: 23, minute: 0),
    );
  }

  /// 手動起床（今夜だけの予約）を保存する
  void manualAt(int hour, int minute) {
    SharedPreferences.setMockInitialValues({
      'shiftsleep_manual_wake_at': DateTime(day.year, day.month, day.day, hour, minute).toIso8601String(),
    });
  }

  Future<WakeAlarmRegistrationResult> register({int minutes = 30}) {
    return WakeAlarmRegistrationService.register(
      now: now,
      settings: settings(minutes: minutes),
      vibrateOnMain: false,
    );
  }

  setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);

  setUp(() {
    repository = _FakeShiftRepository();
    WakeAlarmRegistrationService.shiftRepositoryForTest = repository;
    scheduledIds = [];
    cancelledIds = [];
    armedIds = {};
    events = [];
    failScheduleIds = {};
    failCode = 'SCHEDULE_FAILED';
    failCancel = false;
    SharedPreferences.setMockInitialValues({});
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_alarmChannel, (call) async {
      final id = (call.arguments as Map)['alarmId'] as int;
      if (call.method == 'scheduleAlarmWithAlarmManager') {
        if (failScheduleIds.contains(id)) throw PlatformException(code: failCode);
        scheduledIds.add(id);
        armedIds.add(id);
        events.add('schedule:$id');
      } else if (call.method == 'cancelAlarmWithAlarmManager') {
        cancelledIds.add(id);
        armedIds.remove(id);
        events.add('cancel:$id');
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_notificationChannel, (call) async {
      if (failCancel && call.method == 'cancel') throw PlatformException(code: 'CANCEL_FAILED');
      return null;
    });
  });

  group('登録するアラーム', () {
    test('手動なし・シフトなし → 何も登録せず、main も取り消さない', () async {
      final result = await register();

      expect(result.plan, WakeAlarmPlan.none);
      expect(scheduledIds, isEmpty);
      expect(cancelledIds, isEmpty);
    });

    test('仕様 5：手動なし・出勤日 → pre だけで、main を登録も取り消しもしない', () async {
      workShift();

      final result = await register();

      expect(result.plan, WakeAlarmPlan.preOnly);
      expect(result.manualWakeAt, isNull);
      expect(scheduledIds, [preId]);
      expect(cancelledIds, isEmpty);
    });

    test('手動あり・シフトなし → main だけ', () async {
      manualAt(12, 0);

      final result = await register();

      expect(result.plan, WakeAlarmPlan.mainOnly);
      expect(scheduledIds, [mainId]);
    });

    test('仕様 3：手動が早い → main と pre の 2 本', () async {
      manualAt(12, 0);
      workShift();

      final result = await register();

      expect(result.plan, WakeAlarmPlan.mainAndPre);
      expect(scheduledIds, unorderedEquals([mainId, preId]));
      expect(result.preAlarmAt, DateTime(day.year, day.month, day.day, 14, 30));
    });

    test('手動が遅い → pre だけで、古い main を取り消す', () async {
      manualAt(16, 0);
      workShift();

      final result = await register();

      expect(result.plan, WakeAlarmPlan.preOnly);
      expect(scheduledIds, [preId]);
      expect(cancelledIds, contains(mainId));
    });

    test('pre が過ぎている → main だけ', () async {
      manualAt(12, 0);
      workShift();
      repository.pattern = ShiftPatternModel(
        id: 'p',
        patternName: '早番',
        patternType: ShiftType.work,
        startTime: const TimeOfDay(hour: 9, minute: 15),  // pre は 8:45（now は 9:00）
        endTime: const TimeOfDay(hour: 17, minute: 0),
      );

      final result = await register();

      expect(result.plan, WakeAlarmPlan.mainOnly);
      expect(scheduledIds, [mainId]);
    });

    test('分数 0 → シフトを読まず main だけ', () async {
      manualAt(12, 0);
      workShift();

      final result = await register(minutes: 0);

      expect(result.plan, WakeAlarmPlan.mainOnly);
      expect(repository.readCount, 0);
    });

    test('今日が既定の休日 → pre なし', () async {
      manualAt(12, 0);
      repository.rows = [
        {'shift_date': 'x', 'pattern_id': 'default_dayoff'},
      ];

      expect((await register()).plan, WakeAlarmPlan.mainOnly);
    });

    test('アラーム OFF → 何もせず、手動起床は結果に入れる', () async {
      SharedPreferences.setMockInitialValues({
        'is_alarm_enabled': false,
        'shiftsleep_manual_wake_at': DateTime(day.year, day.month, day.day, 12, 0).toIso8601String(),
      });
      workShift();

      final result = await register();

      expect(result.alarmDisabled, isTrue);
      expect(result.manualWakeAt, isNotNull);
      expect(scheduledIds, isEmpty);
      expect(cancelledIds, isEmpty);
      expect(wakeAlarmMessages(result), isEmpty);
    });
  });

  group('失敗', () {
    test('シフトを読めない → 手動起床で進めて知らせる', () async {
      manualAt(12, 0);
      repository.failRead = true;

      final result = await register();

      expect(result.plan, WakeAlarmPlan.mainOnly);
      expect(result.shiftsReadFailed, isTrue);
      expect(scheduledIds, [mainId]);
    });

    test('pre だけで登録に失敗 → 古い main を取り消さず、⚠️ を返す', () async {
      manualAt(16, 0);
      workShift();
      failScheduleIds = {preId};
      failCode = 'EXACT_ALARM_DENIED';

      final result = await register();

      expect(result.plan, WakeAlarmPlan.preOnly);
      expect(result.preError, contains('アラームとリマインダー'));
      expect(cancelledIds, isEmpty);
      final messages = wakeAlarmMessages(result);
      expect(messages.single.color, Colors.orange);
      expect(messages.single.text, isNot(contains('鳴ります')));
    });

    test('2 本で main だけ失敗 → pre は登録する', () async {
      manualAt(12, 0);
      workShift();
      failScheduleIds = {mainId};

      final result = await register();

      expect(result.mainError, isNotNull);
      expect(result.preError, isNull);
      expect(scheduledIds, [preId]);
    });

    test('2 本で pre だけ失敗 → main は登録する', () async {
      manualAt(12, 0);
      workShift();
      failScheduleIds = {preId};

      final result = await register();

      expect(result.mainError, isNull);
      expect(result.preError, isNotNull);
      expect(scheduledIds, [mainId]);
    });

    test('main の登録で例外 → 結果で返し、pre は登録する', () async {
      manualAt(12, 0);
      workShift();
      failCancel = true;  // scheduleAlarm の先頭の取り消しで例外になる

      final result = await register();

      expect(result.mainError, contains('起床アラームを登録できませんでした'));
      expect(scheduledIds, [preId]);
    });

    test('pre だけのとき古い main の取り消しで例外 → pre は登録済みなので成功扱い', () async {
      manualAt(16, 0);
      workShift();
      failCancel = true;

      final result = await register();

      expect(result.preError, isNull);
      expect(result.mainError, isNull);
      expect(scheduledIds, [preId]);
      expect(
        wakeAlarmMessages(result).single.text,
        '⏰ 設定した起床時刻 16:00 は出社予定時刻（15:00）より遅いため、出勤前アラーム（30分前）の 14:30 に鳴ります',
      );
    });
  });

  group('N17：日付が変わる変更で古い main を残さない', () {
    final realToday = DateTime(real.year, real.month, real.day);

    // 「今から寝る」（バイブあり）と睡眠中の設定変更（バイブなし）は同じ処理を通る
    for (final vibrate in [true, false]) {
      test('今日の main → 明日の時刻：今日の main が消え、明日の main だけ残る（バイブ: $vibrate）', () async {
        manualAt(7, 0);
        armedIds.add(_id(realToday, 0));

        final result = await WakeAlarmRegistrationService.register(
          now: now.subtract(const Duration(hours: 2)),  // 明日の 7:00 より前
          settings: settings(),
          vibrateOnMain: vibrate,
        );

        expect(result.plan, WakeAlarmPlan.mainOnly);
        expect(armedIds, {mainId});
      });

      test('2 本でも、今日の main が消える（バイブ: $vibrate）', () async {
        manualAt(12, 0);
        workShift();
        armedIds.add(_id(realToday, 0));

        final result = await WakeAlarmRegistrationService.register(
          now: now,
          settings: settings(),
          vibrateOnMain: vibrate,
        );

        expect(result.plan, WakeAlarmPlan.mainAndPre);
        expect(armedIds, {mainId, preId});
      });
    }

    test('取り消してから登録する（古い関数と同じ順番）', () async {
      manualAt(12, 0);
      armedIds.add(_id(realToday, 0));

      await register();

      final cancelToday = events.indexOf('cancel:${_id(realToday, 0)}');
      final cancelTomorrow = events.indexOf('cancel:$mainId');
      final schedule = events.indexOf('schedule:$mainId');
      expect(cancelToday, greaterThanOrEqualTo(0));
      expect(cancelTomorrow, greaterThanOrEqualTo(0));
      expect(schedule, greaterThan(cancelToday));
      expect(schedule, greaterThan(cancelTomorrow));
    });

    test('手動なしなら、残っている main には触らない（今の仕様）', () async {
      armedIds.add(_id(realToday, 0));

      await register();

      expect(armedIds, {_id(realToday, 0)});
    });
  });
}

int _id(DateTime date, int type) {
  final y = date.year.toString();
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return int.parse('$y$m$d$type');
}
