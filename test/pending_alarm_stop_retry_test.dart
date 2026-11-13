// N142 3/5：通知の「停止」の起床に失敗しても、停止時刻を失わない
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/wake_up_service.dart';

import 'fakes/fake_shift_repository.dart';

const _idKey = 'current_sleep_record_id';
const _startKey = 'sleep_start_time_ms';
const _stoppedAtKey = 'alarm_stopped_at_ms';
const _manualWakeKey = 'shiftsleep_manual_wake_at';

/// 指定のキーの remove が false を返すか例外を投げるストア
class _FakeStore extends SharedPreferencesStorePlatform {
  _FakeStore(Map<String, Object> initial)
      : data = {for (final entry in initial.entries) 'flutter.${entry.key}': entry.value};

  final Map<String, Object> data;
  final Set<String> failRemoveKeys = {};
  final Set<String> throwRemoveKeys = {};

  bool hasKey(String key) => data.containsKey('flutter.$key');

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    final plainKey = key.substring('flutter.'.length);
    if (throwRemoveKeys.contains(plainKey)) throw PlatformException(code: 'REMOVE_FAILED');
    if (failRemoveKeys.contains(plainKey)) return false;
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map.of(data);
}

/// DB の偽物（メモリの Map に持つ）
class _FakeRepository extends SleepRepository {
  final Map<String, SleepRecord> records = {};
  bool failRead = false;
  int readCalls = 0;

  @override
  Future<SleepRecord?> getSleepRecordById(String id) async {
    readCalls++;
    if (failRead) throw Exception('read failed');
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
  ) async =>
      records.values
          .where((record) => !record.sleepDate.isBefore(startDate) && !record.sleepDate.isAfter(endDate))
          .toList();
}

SleepRecord _record(String id, DateTime start) {
  return SleepRecord(
    id: id,
    userId: 'test_user',
    sleepDate: DateTime(start.year, start.month, start.day),
    sleepStartTime: start,
    sleepStartAuto: true,
    sleepEndTime: start.add(const Duration(days: 1)),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepository repository;
  late _FakeStore store;
  late List<String> alarmCalls;
  late DateTime now;
  late DateTime start;
  late DateTime stoppedAt;

  Future<SleepProvider> restartedProvider() async {
    SharedPreferences.resetStatic();
    final provider = SleepProvider(repository);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await provider.initializeSleepState();
    return provider;
  }

  /// 記録 a で睡眠中、停止時刻のキーがある状態を作る
  Future<SleepProvider> sleepingProvider({Map<String, Object> extra = const {}}) {
    repository.records['a'] = _record('a', start);
    store = _FakeStore({
      _startKey: start.millisecondsSinceEpoch,
      _idKey: 'a',
      _stoppedAtKey: stoppedAt.millisecondsSinceEpoch,
      ...extra,
    });
    SharedPreferencesStorePlatform.instance = store;
    return restartedProvider();
  }

  /// 睡眠中ではなく、停止時刻のキーだけが残っている状態を作る
  Future<SleepProvider> awakeProviderWithKey(int stoppedAtMs) {
    store = _FakeStore({_stoppedAtKey: stoppedAtMs});
    SharedPreferencesStorePlatform.instance = store;
    return restartedProvider();
  }

  // テスト環境では通知プラグインが自動で登録されない（呼び出し先は下の偽物のチャンネル）
  setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);

  setUp(() {
    repository = _FakeRepository();
    WakeUpService.sleepRepositoryForTest = repository;
    WakeUpService.shiftRepositoryForTest = FakeShiftRepository();  // N180 2/3：シフトなし（pre は取り消さない）
    WakeUpService.resetFailedStoppedAtForTest();
    alarmCalls = [];
    now = DateTime.now();
    start = now.subtract(const Duration(hours: 8));
    stoppedAt = now.subtract(const Duration(minutes: 30));
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.sakizoapps.shiftsleep/alarm'),
      (call) async {
        alarmCalls.add(call.method);
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => null,
    );
  });

  group('失敗', () {
    test('例外ならキーを残し、失敗の結果を返して、睡眠中のまま', () async {
      final provider = await sleepingProvider();
      repository.failRead = true;

      final result = await WakeUpService.processPendingAlarmStop(provider);

      expect(result.isFailed, isTrue);
      expect(result.recordedWake, isFalse);
      expect(result.failedStoppedAt!.millisecondsSinceEpoch, stoppedAt.millisecondsSinceEpoch);
      expect(store.hasKey(_stoppedAtKey), isTrue);
      expect(provider.isSleepingNow, isTrue);
      expect(repository.records['a']!.durationMinutes, 0);
      expect(alarmCalls, isNot(contains('cancelAlarmWithAlarmManager')));
    });

    test('失敗の結果は notProcessed と等しくならず、停止時刻と「知らせた」も比べる', () {
      final at = DateTime(2026, 11, 7, 7, 5);
      final failed = PendingAlarmStopResult.failed(at, alreadyNotified: false);
      final same = PendingAlarmStopResult.failed(at, alreadyNotified: false);

      expect(failed, isNot(PendingAlarmStopResult.notProcessed));
      expect(failed, same);
      expect(failed.hashCode, same.hashCode);
      expect(failed, isNot(PendingAlarmStopResult.failed(at, alreadyNotified: true)));
      expect(
        failed,
        isNot(PendingAlarmStopResult.failed(at.add(const Duration(minutes: 1)), alreadyNotified: false)),
      );
    });

    test('⚠️ に止めた時刻を入れる', () {
      expect(
        pendingStopFailedText(DateTime(2026, 11, 7, 7, 5)),
        '⚠️ 7:05 に止めたアラームの起床を記録できませんでした。次にアプリを開いたときに自動でやり直します。「起きる」を押すと、押した時刻で記録されます',
      );
    });
  });

  group('やり直し', () {
    test('次の機会に同じ停止時刻で成功し、キーが消える', () async {
      final provider = await sleepingProvider();
      repository.failRead = true;
      await WakeUpService.processPendingAlarmStop(provider);

      repository.failRead = false;
      final result = await WakeUpService.processPendingAlarmStop(provider);

      expect(result, PendingAlarmStopResult.woke);
      expect(result.warningTexts, isEmpty);
      expect(
        repository.records['a']!.sleepEndTime.millisecondsSinceEpoch,
        stoppedAt.millisecondsSinceEpoch,
      );
      expect(store.hasKey(_stoppedAtKey), isFalse);
      expect(provider.isSleepingNow, isFalse);
    });

    test('再起動のあとでも同じ停止時刻でやり直す', () async {
      final provider = await sleepingProvider();
      repository.failRead = true;
      await WakeUpService.processPendingAlarmStop(provider);

      repository.failRead = false;
      final restarted = await restartedProvider();
      final result = await WakeUpService.processPendingAlarmStop(restarted);

      expect(result, PendingAlarmStopResult.woke);
      expect(
        repository.records['a']!.sleepEndTime.millisecondsSinceEpoch,
        stoppedAt.millisecondsSinceEpoch,
      );
    });

    test('記録の更新のあとで失敗しても、やり直しで起床時刻は変わらず、睡眠中を抜ける', () async {
      final provider = await sleepingProvider();
      store.throwRemoveKeys.add(_manualWakeKey);

      final first = await WakeUpService.processPendingAlarmStop(provider);

      expect(first.isFailed, isTrue);
      expect(provider.isSleepingNow, isTrue);
      expect(store.hasKey(_stoppedAtKey), isTrue);
      final updated = repository.records['a'];
      expect(updated!.durationMinutes, greaterThan(0));

      store.throwRemoveKeys.clear();
      final second = await WakeUpService.processPendingAlarmStop(provider);

      // 完了済みの記録は上書きしないので、DB は同じまま
      expect(second.wakeUpResult!.recorded, isFalse);
      expect(identical(repository.records['a'], updated), isTrue);
      expect(store.hasKey(_stoppedAtKey), isFalse);
      expect(provider.isSleepingNow, isFalse);
    });

    test('同時に呼ばれても起床処理は 1 回だけ', () async {
      final provider = await sleepingProvider();

      final results = await Future.wait([
        WakeUpService.processPendingAlarmStop(provider),
        WakeUpService.processPendingAlarmStop(provider),
      ]);

      expect(results.where((result) => result == PendingAlarmStopResult.woke), hasLength(1));
      expect(results.where((result) => result == PendingAlarmStopResult.notProcessed), hasLength(1));
    });
  });

  group('⚠️ は 1 回だけ', () {
    test('同じ停止時刻の 2 回目の失敗では ⚠️ を出さない', () async {
      final provider = await sleepingProvider();
      repository.failRead = true;

      final first = await WakeUpService.processPendingAlarmStop(provider);
      final second = await WakeUpService.processPendingAlarmStop(provider);

      expect(first.warningTexts, [pendingStopFailedText(stoppedAt)]);
      expect(second.isFailed, isTrue);
      expect(second.warningTexts, isEmpty);
    });

    test('別の停止時刻の失敗なら、もう一度出す', () async {
      final provider = await sleepingProvider();
      repository.failRead = true;
      await WakeUpService.processPendingAlarmStop(provider);

      final newer = now.subtract(const Duration(minutes: 1));
      store.data['flutter.$_stoppedAtKey'] = newer.millisecondsSinceEpoch;
      final result = await WakeUpService.processPendingAlarmStop(provider);

      expect(result.warningTexts, [pendingStopFailedText(newer)]);
    });
  });

  group('5 秒タイマー（retryFailed: false）', () {
    test('失敗した同じ停止時刻はやり直さず、キーは残す', () async {
      final provider = await sleepingProvider();
      repository.failRead = true;
      await WakeUpService.processPendingAlarmStop(provider);
      final readCalls = repository.readCalls;

      repository.failRead = false;  // 直っていても、タイマーではやり直さない
      final result = await WakeUpService.processPendingAlarmStop(provider, retryFailed: false);

      expect(result, PendingAlarmStopResult.notProcessed);
      expect(repository.readCalls, readCalls);
      expect(store.hasKey(_stoppedAtKey), isTrue);
      expect(provider.isSleepingNow, isTrue);
    });

    test('タイマーで初めて見つけた停止時刻は処理する', () async {
      final provider = await sleepingProvider();

      final result = await WakeUpService.processPendingAlarmStop(provider, retryFailed: false);

      expect(result, PendingAlarmStopResult.woke);
    });

    test('タイマーで初めて失敗したら ⚠️ を出し、次のタイマーではやり直さない', () async {
      final provider = await sleepingProvider();
      repository.failRead = true;

      final first = await WakeUpService.processPendingAlarmStop(provider, retryFailed: false);
      final readCalls = repository.readCalls;
      final second = await WakeUpService.processPendingAlarmStop(provider, retryFailed: false);

      expect(first.warningTexts, [pendingStopFailedText(stoppedAt)]);
      expect(second, PendingAlarmStopResult.notProcessed);
      expect(repository.readCalls, readCalls);
    });

    test('別の停止時刻ならタイマーでも処理する', () async {
      final provider = await sleepingProvider();
      repository.failRead = true;
      await WakeUpService.processPendingAlarmStop(provider);

      repository.failRead = false;
      final newer = now.subtract(const Duration(minutes: 1));
      store.data['flutter.$_stoppedAtKey'] = newer.millisecondsSinceEpoch;
      final result = await WakeUpService.processPendingAlarmStop(provider, retryFailed: false);

      expect(result, PendingAlarmStopResult.woke);
      expect(
        repository.records['a']!.sleepEndTime.millisecondsSinceEpoch,
        newer.millisecondsSinceEpoch,
      );
    });
  });

  group('キーを消す場面', () {
    test('睡眠中でなければキーを消す', () async {
      final provider = await awakeProviderWithKey(stoppedAt.millisecondsSinceEpoch);

      expect(await WakeUpService.processPendingAlarmStop(provider), PendingAlarmStopResult.notProcessed);
      expect(store.hasKey(_stoppedAtKey), isFalse);
    });

    test('失敗のあとで「起きる」を押したら押した時刻で記録され、残ったキーは次の確認で消える', () async {
      final provider = await sleepingProvider();
      repository.failRead = true;
      await WakeUpService.processPendingAlarmStop(provider);

      repository.failRead = false;
      await WakeUpService.wakeUp(provider, now);
      expect(repository.records['a']!.sleepEndTime, now);
      expect(store.hasKey(_stoppedAtKey), isTrue);

      expect(await WakeUpService.processPendingAlarmStop(provider), PendingAlarmStopResult.notProcessed);

      expect(store.hasKey(_stoppedAtKey), isFalse);
      expect(repository.records['a']!.sleepEndTime, now);
    });

    test('睡眠の開始より前の停止時刻はキーを消す', () async {
      stoppedAt = start.subtract(const Duration(minutes: 1));
      final provider = await sleepingProvider();

      expect(await WakeUpService.processPendingAlarmStop(provider), PendingAlarmStopResult.notProcessed);
      expect(store.hasKey(_stoppedAtKey), isFalse);
      expect(provider.isSleepingNow, isTrue);
    });

    test('未来の停止時刻はキーを消す', () async {
      stoppedAt = now.add(const Duration(hours: 1));
      final provider = await sleepingProvider();

      expect(await WakeUpService.processPendingAlarmStop(provider), PendingAlarmStopResult.notProcessed);
      expect(store.hasKey(_stoppedAtKey), isFalse);
      expect(provider.isSleepingNow, isTrue);
    });

    test('初期化中（Provider が未復元）ならキーを残す', () async {
      repository.records['a'] = _record('a', start);
      store = _FakeStore({
        _startKey: start.millisecondsSinceEpoch,
        _idKey: 'a',
        _stoppedAtKey: stoppedAt.millisecondsSinceEpoch,
      });
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      final provider = SleepProvider(repository);  // initializeSleepState の前

      expect(await WakeUpService.processPendingAlarmStop(provider), PendingAlarmStopResult.notProcessed);
      expect(store.hasKey(_stoppedAtKey), isTrue);
    });

    test('成功のあとでキーを消せなくても結果は成功。残ったキーは次の確認で消える', () async {
      final provider = await sleepingProvider();
      store.failRemoveKeys.add(_stoppedAtKey);

      expect(await WakeUpService.processPendingAlarmStop(provider), PendingAlarmStopResult.woke);
      expect(store.hasKey(_stoppedAtKey), isTrue);

      store.failRemoveKeys.clear();
      final restarted = await restartedProvider();
      expect(await WakeUpService.processPendingAlarmStop(restarted), PendingAlarmStopResult.notProcessed);
      expect(store.hasKey(_stoppedAtKey), isFalse);
    });

    test('キーの削除が例外でも結果は成功', () async {
      final provider = await sleepingProvider();
      store.throwRemoveKeys.add(_stoppedAtKey);

      expect(await WakeUpService.processPendingAlarmStop(provider), PendingAlarmStopResult.woke);
    });
  });

  group('音の停止', () {
    test('通知の「停止」の処理では音を止めない（鳴っているのは別のアラーム）', () async {
      final provider = await sleepingProvider();

      await WakeUpService.processPendingAlarmStop(provider);

      expect(alarmCalls, isNot(contains('stopAlarm')));
    });

    test('やり直しでも音を止めない', () async {
      final provider = await sleepingProvider();
      repository.failRead = true;
      await WakeUpService.processPendingAlarmStop(provider);
      await WakeUpService.processPendingAlarmStop(provider);

      expect(alarmCalls, isNot(contains('stopAlarm')));
    });

    test('「起きる」は今までどおり音を止める', () async {
      final provider = await sleepingProvider();

      await WakeUpService.wakeUp(provider, now);

      expect(alarmCalls, contains('stopAlarm'));
    });
  });
}
