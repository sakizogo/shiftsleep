// N19 1/2：起床（「起きる」・通知の「停止」）で main・pre を取り消す
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/wake_up_service.dart';
import 'package:shiftsleep/widgets/sleep_button.dart';

const _alarmChannel = MethodChannel('com.sakizoapps.shiftsleep/alarm');
const _notificationChannel = MethodChannel('dexterous.com/flutter/local_notifications');

/// DB の偽物（メモリの Map に持つ）
class _FakeRepository extends SleepRepository {
  final Map<String, SleepRecord> records = {};

  @override
  Future<SleepRecord?> getSleepRecordById(String id) async => records[id];

  @override
  Future<void> updateSleepRecord(SleepRecord record) async {
    records[record.id] = record;
  }

  @override
  Future<SleepRecord?> getLatestSleepRecord(String userId) async => null;

  @override
  Future<List<SleepRecord>> getSleepRecordsByDateRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async =>
      [];
}

SleepRecord _record(DateTime start) {
  return SleepRecord(
    id: 'record-1',
    userId: 'test_user',
    sleepDate: DateTime(start.year, start.month, start.day),
    sleepStartTime: start,
    sleepStartAuto: true,
    sleepEndTime: start.add(const Duration(hours: 8)),
    sleepEndAuto: false,
    wakeUpType: '',
    durationMinutes: 0,
    modifiedCount: 0,
    lastModifiedAt: start,
    canEditUntil: start.add(const Duration(days: 2)),
    createdAt: start,
    updatedAt: start,
  );
}

int _mainId(DateTime date) => _id(date, 0);
int _preId(DateTime date) => _id(date, 1);
int _id(DateTime date, int type) {
  final y = date.year.toString();
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return int.parse('$y$m$d$type');
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepository repository;
  late List<int> cancelledIds;
  late bool failNativeCancel;
  late bool failNotificationCancel;

  /// 記録 record-1 で睡眠中の状態を作り、Provider に復元する
  Future<SleepProvider> sleepingProvider(DateTime start, {DateTime? stoppedAt}) async {
    repository.records['record-1'] = _record(start);
    SharedPreferences.setMockInitialValues({
      'sleep_start_time_ms': start.millisecondsSinceEpoch,
      'current_sleep_record_id': 'record-1',
      if (stoppedAt != null) 'alarm_stopped_at_ms': stoppedAt.millisecondsSinceEpoch,
    });
    final provider = SleepProvider(repository);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await provider.initializeSleepState();
    return provider;
  }

  // テスト環境では通知プラグインが自動で登録されない（呼び出し先は下の偽物のチャンネル）
  setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);

  setUp(() {
    repository = _FakeRepository();
    WakeUpService.sleepRepositoryForTest = repository;
    cancelledIds = [];
    failNativeCancel = false;
    failNotificationCancel = false;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_alarmChannel, (call) async {
      if (call.method != 'cancelAlarmWithAlarmManager') return null;
      if (failNativeCancel) throw PlatformException(code: 'CANCEL_FAILED');
      cancelledIds.add((call.arguments as Map)['alarmId'] as int);
      return null;
    });
    messenger.setMockMethodCallHandler(_notificationChannel, (call) async {
      if (failNotificationCancel && call.method == 'cancel') {
        throw PlatformException(code: 'CANCEL_FAILED');
      }
      return null;
    });
  });

  group('取り消す ID', () {
    test('「起きる」：今日の main・pre と明日の main を取り消す（明日の pre は残す）', () async {
      final now = DateTime.now();
      final today = _dateOnly(now);
      final tomorrow = today.add(const Duration(days: 1));
      final provider = await sleepingProvider(now.subtract(const Duration(hours: 8)));

      expect(await WakeUpService.wakeUp(provider, now), isTrue);

      expect(cancelledIds, containsAll([_mainId(today), _preId(today), _mainId(tomorrow)]));
      expect(cancelledIds, isNot(contains(_preId(tomorrow))));
    });

    test('通知の「停止」：「起きる」と同じ ID を取り消す', () async {
      final now = DateTime.now();
      final today = _dateOnly(now);
      final tomorrow = today.add(const Duration(days: 1));
      final provider = await sleepingProvider(
        now.subtract(const Duration(hours: 8)),
        stoppedAt: now,
      );

      final result = await WakeUpService.processPendingAlarmStop(provider);

      expect(result, PendingAlarmStopResult.woke);
      expect(cancelledIds, containsAll([_mainId(today), _preId(today), _mainId(tomorrow)]));
      expect(cancelledIds, isNot(contains(_preId(tomorrow))));
    });

    test('翌日にアプリを開いた「停止」：押した日の pre を取り消し、今日の pre は残す', () async {
      final now = DateTime.now();
      final today = _dateOnly(now);
      final tomorrow = today.add(const Duration(days: 1));
      final yesterday = today.subtract(const Duration(days: 1));
      final stoppedAt = now.subtract(const Duration(days: 1));
      final provider = await sleepingProvider(
        stoppedAt.subtract(const Duration(hours: 8)),
        stoppedAt: stoppedAt,
      );

      final result = await WakeUpService.processPendingAlarmStop(provider);

      expect(result, PendingAlarmStopResult.woke);
      expect(cancelledIds, contains(_preId(yesterday)));
      expect(cancelledIds, containsAll([_mainId(today), _mainId(tomorrow)]));
      expect(cancelledIds, isNot(contains(_preId(today))));
    });

    test('日をまたぐ睡眠：昨夜に寝て今朝起きると、今日の main・pre を取り消す', () async {
      final now = DateTime.now();
      final today = _dateOnly(now);
      final lastNight = today.subtract(const Duration(hours: 1));
      final provider = await sleepingProvider(lastNight, stoppedAt: now);

      final result = await WakeUpService.processPendingAlarmStop(provider);

      expect(result, PendingAlarmStopResult.woke);
      expect(cancelledIds, containsAll([_mainId(today), _preId(today)]));
    });

    test('起床処理をしない停止時刻（睡眠の開始より前）では取り消さない', () async {
      final now = DateTime.now();
      final provider = await sleepingProvider(
        now.subtract(const Duration(hours: 1)),
        stoppedAt: now.subtract(const Duration(hours: 2)),
      );

      final result = await WakeUpService.processPendingAlarmStop(provider);

      expect(result, PendingAlarmStopResult.notProcessed);
      expect(cancelledIds, isEmpty);
      expect(provider.isSleepingNow, isTrue);
    });
  });

  group('取り消しの失敗', () {
    Future<void> expectWokeUp(SleepProvider provider) async {
      expect(provider.isSleepingNow, isFalse);
      expect(repository.records['record-1']!.durationMinutes, greaterThan(0));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('current_sleep_record_id'), isNull);
    }

    test('AlarmManager の取り消しに失敗しても起床は最後まで進み、false を返す', () async {
      failNativeCancel = true;
      final now = DateTime.now();
      final provider = await sleepingProvider(now.subtract(const Duration(hours: 8)));

      expect(await WakeUpService.wakeUp(provider, now), isFalse);

      await expectWokeUp(provider);
    });

    test('通知プラグインの例外でも起床は最後まで進み、false を返す', () async {
      failNotificationCancel = true;
      final now = DateTime.now();
      final provider = await sleepingProvider(now.subtract(const Duration(hours: 8)));

      expect(await WakeUpService.wakeUp(provider, now), isFalse);

      await expectWokeUp(provider);
    });

    test('通知の「停止」では結果で知らせる', () async {
      failNativeCancel = true;
      final now = DateTime.now();
      final provider = await sleepingProvider(
        now.subtract(const Duration(hours: 8)),
        stoppedAt: now,
      );

      final result = await WakeUpService.processPendingAlarmStop(provider);

      expect(result, PendingAlarmStopResult.wokeButAlarmCancelFailed);
      await expectWokeUp(provider);
    });

    testWidgets('「起きる」ボタン：✅ のあとにオレンジの ⚠️ を出す', (tester) async {
      failNativeCancel = true;
      late SleepProvider provider;
      await tester.runAsync(() async {
        provider = await sleepingProvider(DateTime.now().subtract(const Duration(hours: 8)));
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<SleepProvider>.value(
          value: provider,
          child: const MaterialApp(home: Scaffold(body: SleepButton())),
        ),
      );

      await tester.tap(find.byType(SleepButton));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('✅ 起床しました。睡眠が記録されました。'), findsOneWidget);

      // ✅ の 3 秒が終わると ⚠️ に変わる
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.orange);
      expect(find.text(alarmCancelFailedText), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
