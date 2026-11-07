// N142 1/5：起こす記録の探し方（① ID → ② 開始時刻 → ③ 記録なしの起床）
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

const _idKey = 'current_sleep_record_id';
const _startKey = 'sleep_start_time_ms';
const _stoppedAtKey = 'alarm_stopped_at_ms';
const _manualWakeKey = 'shiftsleep_manual_wake_at';

/// DB の偽物（メモリの Map に持つ）
class _FakeRepository extends SleepRepository {
  final Map<String, SleepRecord> records = {};
  bool failReadById = false;
  bool failReadByDate = false;

  @override
  Future<SleepRecord?> getSleepRecordById(String id) async {
    if (failReadById) throw Exception('read failed');
    return records[id];
  }

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
  ) async {
    if (failReadByDate) throw Exception('read failed');
    return records.values
        .where((record) => !record.sleepDate.isBefore(startDate) && !record.sleepDate.isAfter(endDate))
        .toList();
  }
}

SleepRecord _record(String id, DateTime start, {int durationMinutes = 0}) {
  return SleepRecord(
    id: id,
    userId: 'test_user',
    sleepDate: DateTime(start.year, start.month, start.day),
    sleepStartTime: start,
    sleepStartAuto: true,
    sleepEndTime: start.add(const Duration(hours: 8)),
    sleepEndAuto: false,
    wakeUpType: '',
    durationMinutes: durationMinutes,
    modifiedCount: 0,
    lastModifiedAt: start,
    canEditUntil: start.add(const Duration(days: 2)),
    createdAt: start,
    updatedAt: start,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepository repository;
  late List<int> cancelledIds;
  late bool failNativeCancel;

  /// 開始時刻 start で睡眠中の状態を作り、Provider に復元する（id が null なら ID は保存しない）
  Future<SleepProvider> sleepingProvider(
    DateTime start, {
    String? id,
    Map<String, Object> extra = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      _startKey: start.millisecondsSinceEpoch,
      if (id != null) _idKey: id,
      ...extra,
    });
    final provider = SleepProvider(repository);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await provider.initializeSleepState();
    return provider;
  }

  /// 起床が最後まで進み、睡眠状態が消えた
  Future<void> expectStateCleared(SleepProvider provider) async {
    expect(provider.isSleepingNow, isFalse);
    expect(provider.currentSleepRecordIdNow, isNull);
    expect(provider.sleepStartTime, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(_startKey), isNull);
    expect(prefs.getString(_idKey), isNull);
  }

  /// 睡眠中のまま（もう一度「起きる」を押せる）
  Future<void> expectStillSleeping(SleepProvider provider, {required String id}) async {
    expect(provider.isSleepingNow, isTrue);
    expect(provider.currentSleepRecordIdNow, id);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(_startKey), isNotNull);
    expect(prefs.getString(_idKey), id);
    expect(cancelledIds, isEmpty);
  }

  // テスト環境では通知プラグインが自動で登録されない（呼び出し先は下の偽物のチャンネル）
  setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);

  setUp(() {
    repository = _FakeRepository();
    WakeUpService.sleepRepositoryForTest = repository;
    cancelledIds = [];
    failNativeCancel = false;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.sakizoapps.shiftsleep/alarm'),
      (call) async {
        if (call.method != 'cancelAlarmWithAlarmManager') return null;
        if (failNativeCancel) throw PlatformException(code: 'CANCEL_FAILED');
        cancelledIds.add((call.arguments as Map)['alarmId'] as int);
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => null,
    );
  });

  group('① 保存された ID', () {
    test('開始時刻が一致する進行中の記録を採用する', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      repository.records['a'] = _record('a', start);
      final provider = await sleepingProvider(start, id: 'a');

      final result = await WakeUpService.wakeUp(provider, now);

      expect(result.recorded, isTrue);
      expect(result.alarmsCancelled, isTrue);
      expect(repository.records['a']!.sleepEndTime, now);
      expect(repository.records['a']!.durationMinutes, 480);
      await expectStateCleared(provider);
    });

    test('マイクロ秒が違っても、ミリ秒が同じなら採用する', () async {
      final now = DateTime.now();
      final base = now.subtract(const Duration(hours: 8));
      final start = DateTime(base.year, base.month, base.day, base.hour, base.minute, base.second, 123, 456);
      repository.records['a'] = _record('a', start);
      final provider = await sleepingProvider(start, id: 'a');

      expect((await WakeUpService.wakeUp(provider, now)).recorded, isTrue);
    });
  });

  group('② 保存された開始時刻', () {
    test('① の記録が完了済みなら上書きせず、開始時刻で探す', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      final finished = _record('finished', start, durationMinutes: 400);
      repository.records['finished'] = finished;
      repository.records['sleeping'] = _record('sleeping', start);
      final provider = await sleepingProvider(start, id: 'finished');

      final result = await WakeUpService.wakeUp(provider, now);

      expect(result.recorded, isTrue);
      expect(identical(repository.records['finished'], finished), isTrue);
      expect(repository.records['sleeping']!.sleepEndTime, now);
    });

    test('① の記録の開始時刻が違えば上書きせず、開始時刻で探す（古い ID が残っていたとき）', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      final old = _record('old', start.subtract(const Duration(days: 1)));
      repository.records['old'] = old;
      repository.records['sleeping'] = _record('sleeping', start);
      final provider = await sleepingProvider(start, id: 'old');

      final result = await WakeUpService.wakeUp(provider, now);

      expect(result.recorded, isTrue);
      expect(identical(repository.records['old'], old), isTrue);
      expect(repository.records['sleeping']!.sleepEndTime, now);
    });

    test('ID が保存されていなければ開始時刻で探す（開始時刻あり・ID なしから抜けられる）', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      repository.records['sleeping'] = _record('sleeping', start);
      final provider = await sleepingProvider(start);

      final result = await WakeUpService.wakeUp(provider, now);

      expect(result.recorded, isTrue);
      expect(repository.records['sleeping']!.sleepEndTime, now);
      await expectStateCleared(provider);
    });

    test('ID の記録が DB になければ開始時刻で探す', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      repository.records['sleeping'] = _record('sleeping', start);
      final provider = await sleepingProvider(start, id: 'deleted');

      expect((await WakeUpService.wakeUp(provider, now)).recorded, isTrue);
      expect(repository.records['sleeping']!.sleepEndTime, now);
    });

    test('ミリ秒が違う記録は採用しない', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      final other = _record('other', start.add(const Duration(milliseconds: 1)));
      repository.records['other'] = other;
      final provider = await sleepingProvider(start);

      expect((await WakeUpService.wakeUp(provider, now)).recorded, isFalse);
      expect(identical(repository.records['other'], other), isTrue);
    });
  });

  group('③ 記録なしの起床', () {
    test('記録がなくても、取り消し・手動起床のクリア・状態の消去まで進む', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      final provider = await sleepingProvider(
        start,
        id: 'deleted',
        extra: {_manualWakeKey: now.add(const Duration(hours: 1)).toIso8601String()},
      );

      final result = await WakeUpService.wakeUp(provider, now);

      expect(result.recorded, isFalse);
      expect(result.alarmsCancelled, isTrue);
      expect(cancelledIds, isNotEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_manualWakeKey), isNull);
      await expectStateCleared(provider);
    });

    test('完了済みの記録しかなければ上書きしない（再起動で睡眠中に戻ったとき）', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      final finished = _record('finished', start, durationMinutes: 400);
      repository.records['finished'] = finished;
      final provider = await sleepingProvider(start, id: 'finished');

      expect((await WakeUpService.wakeUp(provider, now)).recorded, isFalse);

      expect(identical(repository.records['finished'], finished), isTrue);
      await expectStateCleared(provider);
    });

    test('取り消しに失敗したら alarmsCancelled も false', () async {
      failNativeCancel = true;
      final now = DateTime.now();
      final provider = await sleepingProvider(now.subtract(const Duration(hours: 8)));

      final result = await WakeUpService.wakeUp(provider, now);

      expect(result.recorded, isFalse);
      expect(result.alarmsCancelled, isFalse);
      await expectStateCleared(provider);
    });
  });

  group('読み取りの例外', () {
    test('ID での読み取りが例外なら投げ、睡眠中のまま。もう一度で成功する', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      repository.records['a'] = _record('a', start);
      final provider = await sleepingProvider(start, id: 'a');
      repository.failReadById = true;

      await expectLater(WakeUpService.wakeUp(provider, now), throwsException);

      await expectStillSleeping(provider, id: 'a');
      expect(repository.records['a']!.durationMinutes, 0);

      repository.failReadById = false;
      expect((await WakeUpService.wakeUp(provider, now)).recorded, isTrue);
      await expectStateCleared(provider);
    });

    test('開始時刻での読み取りが例外でも投げ、記録なしの起床にしない', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      final provider = await sleepingProvider(start, id: 'deleted');
      repository.failReadByDate = true;

      await expectLater(WakeUpService.wakeUp(provider, now), throwsException);

      await expectStillSleeping(provider, id: 'deleted');
    });
  });

  group('通知の「停止」', () {
    test('② の記録を停止時刻で更新する', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      final stoppedAt = now.subtract(const Duration(minutes: 5));
      repository.records['sleeping'] = _record('sleeping', start);
      final provider = await sleepingProvider(
        start,
        extra: {_stoppedAtKey: stoppedAt.millisecondsSinceEpoch},
      );

      final result = await WakeUpService.processPendingAlarmStop(provider);

      expect(result, PendingAlarmStopResult.woke);
      expect(
        repository.records['sleeping']!.sleepEndTime.millisecondsSinceEpoch,
        stoppedAt.millisecondsSinceEpoch,
      );
    });

    test('記録がなければ wokeWithoutRecord', () async {
      final now = DateTime.now();
      final provider = await sleepingProvider(
        now.subtract(const Duration(hours: 8)),
        id: 'deleted',
        extra: {_stoppedAtKey: now.millisecondsSinceEpoch},
      );

      expect(
        await WakeUpService.processPendingAlarmStop(provider),
        PendingAlarmStopResult.wokeWithoutRecord,
      );
      await expectStateCleared(provider);
    });

    test('記録がなく取り消しも失敗したら wokeWithoutRecordButAlarmCancelFailed', () async {
      failNativeCancel = true;
      final now = DateTime.now();
      final provider = await sleepingProvider(
        now.subtract(const Duration(hours: 8)),
        extra: {_stoppedAtKey: now.millisecondsSinceEpoch},
      );

      expect(
        await WakeUpService.processPendingAlarmStop(provider),
        PendingAlarmStopResult.wokeWithoutRecordButAlarmCancelFailed,
      );
    });

    test('読み取りが例外なら失敗の結果で、睡眠中のまま', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      repository.records['a'] = _record('a', start);
      final provider = await sleepingProvider(
        start,
        id: 'a',
        extra: {_stoppedAtKey: now.millisecondsSinceEpoch},
      );
      repository.failReadById = true;

      final result = await WakeUpService.processPendingAlarmStop(provider);

      expect(result.isFailed, isTrue);
      expect(result.recordedWake, isFalse);
      await expectStillSleeping(provider, id: 'a');
    });
  });

  group('知らせの判定', () {
    test('⏰「記録しました」は記録できたときだけ', () {
      expect(PendingAlarmStopResult.woke.recordedWake, isTrue);
      expect(PendingAlarmStopResult.wokeButAlarmCancelFailed.recordedWake, isTrue);
      expect(PendingAlarmStopResult.notProcessed.recordedWake, isFalse);
      expect(PendingAlarmStopResult.wokeWithoutRecord.recordedWake, isFalse);
      expect(PendingAlarmStopResult.wokeWithoutRecordButAlarmCancelFailed.recordedWake, isFalse);
    });

    test('⚠️ の文言', () {
      expect(PendingAlarmStopResult.notProcessed.warningTexts, isEmpty);
      expect(PendingAlarmStopResult.woke.warningTexts, isEmpty);
      expect(PendingAlarmStopResult.wokeButAlarmCancelFailed.warningTexts, [alarmCancelFailedText]);
      expect(PendingAlarmStopResult.wokeWithoutRecord.warningTexts, [noRecordWakeText]);
      expect(
        PendingAlarmStopResult.wokeWithoutRecordButAlarmCancelFailed.warningTexts,
        [noRecordWakeText, noRecordAlarmCancelFailedText],
      );
    });
  });

  group('「起きる」ボタン', () {
    Future<SleepProvider> tapWakeButton(
      WidgetTester tester,
      Future<SleepProvider> Function() createProvider,
    ) async {
      late SleepProvider provider;
      await tester.runAsync(() async {
        provider = await createProvider();
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
      return provider;
    }

    testWidgets('記録なしの起床：✅ を出さず、オレンジの ⚠️ を出して睡眠中を抜ける', (tester) async {
      final provider = await tapWakeButton(
        tester,
        () => sleepingProvider(DateTime.now().subtract(const Duration(hours: 8)), id: 'deleted'),
      );

      expect(find.text('✅ 起床しました。睡眠が記録されました。'), findsNothing);
      expect(find.text(noRecordWakeText), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.orange);
      expect(provider.isSleepingNow, isFalse);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('記録なしで取り消しも失敗：「起床は記録しました」の文言を出さない', (tester) async {
      failNativeCancel = true;
      await tapWakeButton(
        tester,
        () => sleepingProvider(DateTime.now().subtract(const Duration(hours: 8)), id: 'deleted'),
      );
      expect(find.text(noRecordWakeText), findsOneWidget);

      // 1 つ目の 6 秒が終わると 2 つ目に変わる
      for (var i = 0; i < 28; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text(noRecordAlarmCancelFailedText), findsOneWidget);
      expect(find.text(alarmCancelFailedText), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('読み取りの例外：❌ を出して睡眠中のまま', (tester) async {
      final start = DateTime.now().subtract(const Duration(hours: 8));
      repository.records['a'] = _record('a', start);
      repository.failReadById = true;
      final provider = await tapWakeButton(tester, () => sleepingProvider(start, id: 'a'));

      expect(find.textContaining('❌ エラー'), findsOneWidget);
      expect(find.text('✅ 起床しました。睡眠が記録されました。'), findsNothing);
      expect(provider.isSleepingNow, isTrue);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
