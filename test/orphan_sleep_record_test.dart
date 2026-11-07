// N142 5/5：起動時に、記録だけ残ったものを片付ける
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/orphan_sleep_record_service.dart';
import 'package:shiftsleep/services/wake_up_service.dart';

const _idKey = 'current_sleep_record_id';
const _startKey = 'sleep_start_time_ms';
const _stoppedAtKey = 'alarm_stopped_at_ms';

/// 「今から寝る」が作る記録（sleep_button.dart と同じ形）
SleepRecord _orphan(String id, DateTime start) {
  return SleepRecord(
    id: id,
    userId: 'test_user',
    sleepDate: DateTime(start.year, start.month, start.day),
    sleepStartTime: start,
    sleepStartAuto: true,
    sleepEndTime: DateTime(start.year, start.month, start.day + 1, 7),
    sleepEndAuto: false,
    wakeUpType: '',
    durationMinutes: 0,
    modifiedCount: 0,
    lastModifiedAt: start,
    canEditUntil: DateTime(start.year, start.month, start.day + 3, 7),
    createdAt: start,
    updatedAt: start,
  );
}

/// 端末のファイルの偽物。failRead の間は読み取りが例外になる
class _FakeStore extends SharedPreferencesStorePlatform {
  _FakeStore(Map<String, Object> initial)
      : data = {for (final entry in initial.entries) 'flutter.${entry.key}': entry.value};

  final Map<String, Object> data;
  bool failRead = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (failRead) throw PlatformException(code: 'READ_FAILED');
    return Map.of(data);
  }
}

/// DB の偽物（メモリの Map に持つ）
class _FakeRepository extends SleepRepository {
  final Map<String, SleepRecord> records = {};
  bool failRead = false;
  final Set<String> failDeleteIds = {};
  int loadCalls = 0;

  @override
  Future<List<SleepRecord>> getSleepRecordsByUserId(String userId) async {
    if (failRead) throw Exception('read failed');
    return records.values.toList();
  }

  @override
  Future<void> deleteSleepRecord(String id) async {
    if (failDeleteIds.contains(id)) throw Exception('delete failed');
    records.remove(id);
  }

  @override
  Future<SleepRecord?> getSleepRecordById(String id) async => records[id];

  @override
  Future<void> updateSleepRecord(SleepRecord record) async {
    records[record.id] = record;
  }

  @override
  Future<SleepRecord?> getLatestSleepRecord(String userId) async {
    loadCalls++;
    return null;
  }

  @override
  Future<List<SleepRecord>> getSleepRecordsByDateRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async =>
      records.values.toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isOrphanSleepRecord', () {
    final start = DateTime(2026, 11, 6, 23, 0, 12, 345);
    final startedAt = DateTime(2026, 11, 7, 8, 0);

    bool judge(
      SleepRecord record, {
      Set<int> startTimes = const {},
      Set<String> ids = const {},
    }) =>
        isOrphanSleepRecord(
          record,
          appStartedAt: startedAt,
          currentStartTimesMs: startTimes,
          currentRecordIds: ids,
        );

    test('「今から寝る」のまま残った記録は対象', () {
      expect(judge(_orphan('a', start)), isTrue);
    });

    test('0 時すぎの就寝は、その日の翌日 7:00 で判定する', () {
      expect(judge(_orphan('a', DateTime(2026, 11, 7, 0, 30))), isTrue);
    });

    test('月末の就寝も翌月 1 日の 7:00 で判定する', () {
      final record = _orphan('a', DateTime(2026, 10, 31, 23, 0));
      expect(record.sleepEndTime, DateTime(2026, 11, 1, 7));
      expect(judge(record), isTrue);
    });

    test('開始時刻がミリ秒まで一致する記録は、今の睡眠中なので対象外', () {
      final record = _orphan('a', start);
      expect(judge(record, startTimes: {start.millisecondsSinceEpoch}), isFalse);
      expect(judge(record, startTimes: {start.millisecondsSinceEpoch + 1}), isTrue);
    });

    test('保存された ID の記録は、今の睡眠中なので対象外', () {
      final record = _orphan('a', start);
      expect(judge(record, ids: {'a'}), isFalse);
      expect(judge(record, ids: {'b'}), isTrue);
    });

    test('手動で追加した記録は対象外', () {
      expect(judge(_orphan('a', start).copyWith(sleepStartAuto: false, wakeUpType: 'manual')), isFalse);
    });

    test('1 分未満で起きた記録は対象外（時間は 0 だが、終了が起きた時刻）', () {
      final record = _orphan('a', start).copyWith(
        sleepEndTime: start.add(const Duration(seconds: 30)),
      );
      expect(record.durationMinutes, 0);
      expect(judge(record), isFalse);
    });

    test('翌日 7:00 ちょうどに起きた記録は対象外（時間が 0 でない）', () {
      expect(judge(_orphan('a', start).copyWith(durationMinutes: 479)), isFalse);
    });

    test('修正した記録は対象外', () {
      expect(judge(_orphan('a', start).copyWith(modifiedCount: 1)), isFalse);
    });

    test('終了が 7:00 ちょうどでない記録は対象外', () {
      final base = _orphan('a', start);
      expect(judge(base.copyWith(sleepEndTime: DateTime(2026, 11, 7, 7, 1))), isFalse);
      expect(judge(base.copyWith(sleepEndTime: DateTime(2026, 11, 7, 7, 0, 0, 1))), isFalse);
      expect(judge(base.copyWith(sleepEndTime: DateTime(2026, 11, 8, 7))), isFalse);
    });

    test('今回の起動のあと（同じ時刻を含む）に作られた記録は対象外', () {
      final base = _orphan('a', start);
      expect(judge(base.copyWith(createdAt: startedAt)), isFalse);
      expect(judge(base.copyWith(createdAt: startedAt.add(const Duration(milliseconds: 1)))), isFalse);
      expect(judge(base.copyWith(createdAt: startedAt.subtract(const Duration(milliseconds: 1)))), isTrue);
    });
  });

  group('orphanRecordsRemovedText', () {
    test('1 件', () {
      expect(
        orphanRecordsRemovedText([_orphan('a', DateTime(2026, 11, 6, 23, 0))]),
        '⚠️ 11/6 23:00 の『今から寝る』が途中で終わっていたため取り消しました。必要なら睡眠記録の「追加」で入れてください',
      );
    });

    test('2 件は 1 つにまとめ、新しい順に並べる', () {
      expect(
        orphanRecordsRemovedText([
          _orphan('a', DateTime(2026, 11, 5, 1, 5)),
          _orphan('b', DateTime(2026, 11, 6, 23, 0)),
        ]),
        '⚠️ 『今から寝る』が途中で終わっていた 2 件（11/6 23:00、11/5 1:05）を取り消しました。必要なら睡眠記録の「追加」で入れてください',
      );
    });

    test('4 件以上は新しい 3 件と「ほか N 件」', () {
      expect(
        orphanRecordsRemovedText([
          for (var day = 1; day <= 5; day++) _orphan('$day', DateTime(2026, 11, day, 23, 0)),
        ]),
        '⚠️ 『今から寝る』が途中で終わっていた 5 件（11/5 23:00、11/4 23:00、11/3 23:00 ほか 2 件）を取り消しました。必要なら睡眠記録の「追加」で入れてください',
      );
    });
  });

  group('OrphanSleepRecordService.cleanUp', () {
    late _FakeRepository repository;
    late _FakeStore store;
    late DateTime appStartedAt;
    late DateTime orphanStart;

    void useStore(Map<String, Object> initial) {
      SharedPreferences.resetStatic();
      store = _FakeStore(initial);
      SharedPreferencesStorePlatform.instance = store;
    }

    Future<SleepProvider> restoredProvider() async {
      final provider = SleepProvider(repository);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await provider.initializeSleepState();
      return provider;
    }

    Future<List<SleepRecord>> cleanUp(SleepProvider provider) => OrphanSleepRecordService.cleanUp(
          provider: provider,
          repository: repository,
          appStartedAt: appStartedAt,
        );

    setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);

    setUp(() {
      repository = _FakeRepository();
      WakeUpService.sleepRepositoryForTest = repository;
      WakeUpService.resetFailedStoppedAtForTest();
      useStore({});
      // SharedPreferences に保存するとマイクロ秒が落ちるので、はじめからミリ秒にそろえる
      appStartedAt = DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch);
      orphanStart = appStartedAt.subtract(const Duration(days: 1));
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.sakizoapps.shiftsleep/alarm'),
        (call) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async => null,
      );
    });

    test('見つかったら消して返し、ホームの表示を読み直す', () async {
      repository.records['a'] = _orphan('a', orphanStart);
      final provider = await restoredProvider();

      final removed = await cleanUp(provider);

      expect(removed.map((record) => record.id), ['a']);
      expect(repository.records, isEmpty);
      expect(repository.loadCalls, 1);
    });

    test('2 回目の片付けでは何も返さない（⚠️ は 1 回だけ）', () async {
      repository.records['a'] = _orphan('a', orphanStart);
      final provider = await restoredProvider();

      await cleanUp(provider);

      expect(await cleanUp(provider), isEmpty);
    });

    test('対象がなければ読み直さない（ホームがスピナーにならない）', () async {
      final provider = await restoredProvider();

      expect(await cleanUp(provider), isEmpty);
      expect(repository.loadCalls, 0);
    });

    test('復元の前は何も消さない', () async {
      repository.records['a'] = _orphan('a', orphanStart);
      final provider = SleepProvider(repository);

      expect(await cleanUp(provider), isEmpty);
      expect(repository.records.keys, ['a']);
    });

    test('今の睡眠中の記録は残し、別の残った記録だけ消す', () async {
      final sleepingStart = appStartedAt.subtract(const Duration(hours: 2));
      repository.records['current'] = _orphan('current', sleepingStart);
      repository.records['old'] = _orphan('old', orphanStart);
      useStore({_startKey: sleepingStart.millisecondsSinceEpoch, _idKey: 'current'});
      final provider = await restoredProvider();

      final removed = await cleanUp(provider);

      expect(removed.map((record) => record.id), ['old']);
      expect(repository.records.keys, ['current']);
    });

    test('今回の起動のあとに「今から寝る」で作られた記録は消さない', () async {
      final provider = await restoredProvider();
      final later = appStartedAt.add(const Duration(milliseconds: 100));
      repository.records['new'] = _orphan('new', later);

      expect(await cleanUp(provider), isEmpty);
      expect(repository.records.keys, ['new']);
    });

    test('SharedPreferences を読めないときは、睡眠中の記録を消さない', () async {
      final sleepingStart = appStartedAt.subtract(const Duration(hours: 2));
      repository.records['current'] = _orphan('current', sleepingStart);
      repository.records['old'] = _orphan('old', orphanStart);
      useStore({_startKey: sleepingStart.millisecondsSinceEpoch, _idKey: 'current'});
      store.failRead = true;
      final provider = await restoredProvider();
      expect(provider.isSleepingNow, isFalse);  // 復元は失敗を握りつぶして「睡眠中でない」になる

      expect(await cleanUp(provider), isEmpty);
      expect(repository.records.keys, containsAll(['current', 'old']));
    });

    test('保存された開始時刻の型が壊れていたら、何も消さない', () async {
      repository.records['a'] = _orphan('a', orphanStart);
      useStore({_startKey: 'broken'});
      final provider = await restoredProvider();

      expect(await cleanUp(provider), isEmpty);
      expect(repository.records.keys, ['a']);
    });

    test('復元で読めなくても、片付けのときに読めれば睡眠中の記録を除く', () async {
      final sleepingStart = appStartedAt.subtract(const Duration(hours: 2));
      repository.records['current'] = _orphan('current', sleepingStart);
      useStore({_startKey: sleepingStart.millisecondsSinceEpoch});
      store.failRead = true;
      final provider = await restoredProvider();
      store.failRead = false;

      expect(await cleanUp(provider), isEmpty);
      expect(repository.records.keys, ['current']);
    });

    test('DB を読めないときは何も消さない', () async {
      repository.records['a'] = _orphan('a', orphanStart);
      final provider = await restoredProvider();
      repository.failRead = true;

      expect(await cleanUp(provider), isEmpty);
      expect(repository.records.keys, ['a']);
    });

    test('消せなかった記録は返さず、次の機会に消す', () async {
      repository.records['a'] = _orphan('a', orphanStart);
      repository.records['b'] = _orphan('b', orphanStart.subtract(const Duration(days: 1)));
      repository.failDeleteIds.add('a');
      final provider = await restoredProvider();

      final first = await cleanUp(provider);
      expect(first.map((record) => record.id), ['b']);
      expect(repository.records.keys, ['a']);

      repository.failDeleteIds.clear();
      final second = await cleanUp(provider);
      expect(second.map((record) => record.id), ['a']);
      expect(repository.records, isEmpty);
    });

    test('通知の「停止」で起床した記録は、そのあとの片付けで消さない', () async {
      final sleepingStart = appStartedAt.subtract(const Duration(hours: 8));
      final stoppedAt = appStartedAt.subtract(const Duration(hours: 1));
      repository.records['a'] = _orphan('a', sleepingStart);
      useStore({
        _startKey: sleepingStart.millisecondsSinceEpoch,
        _idKey: 'a',
        _stoppedAtKey: stoppedAt.millisecondsSinceEpoch,
      });
      final provider = await restoredProvider();

      final result = await WakeUpService.processPendingAlarmStop(provider);
      expect(result.recordedWake, isTrue);
      expect(provider.isSleepingNow, isFalse);

      expect(await cleanUp(provider), isEmpty);
      expect(repository.records['a']!.sleepEndTime.millisecondsSinceEpoch, stoppedAt.millisecondsSinceEpoch);
      expect(repository.records['a']!.durationMinutes, 420);
    });

    test('通知の「停止」の起床に失敗して睡眠中のままなら、片付けで消さない', () async {
      final sleepingStart = appStartedAt.subtract(const Duration(hours: 8));
      repository.records['a'] = _orphan('a', sleepingStart);
      useStore({
        _startKey: sleepingStart.millisecondsSinceEpoch,
        _idKey: 'a',
        _stoppedAtKey: appStartedAt.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      });
      final provider = await restoredProvider();
      WakeUpService.sleepRepositoryForTest = _ThrowingRepository();

      final result = await WakeUpService.processPendingAlarmStop(provider);
      expect(result.isFailed, isTrue);
      expect(provider.isSleepingNow, isTrue);

      expect(await cleanUp(provider), isEmpty);
      expect(repository.records.keys, ['a']);
    });
  });
}

/// 起床処理の DB の読み取りが例外になる
class _ThrowingRepository extends SleepRepository {
  @override
  Future<SleepRecord?> getSleepRecordById(String id) async => throw Exception('read failed');

  @override
  Future<List<SleepRecord>> getSleepRecordsByDateRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async =>
      throw Exception('read failed');
}
