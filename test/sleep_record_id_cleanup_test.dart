// N143：起床・起動時に current_sleep_record_id を残さない
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/wake_up_service.dart';

const _idKey = 'current_sleep_record_id';
const _startKey = 'sleep_start_time_ms';

/// DB の偽物（メモリの Map に持つ）
class _FakeRepository extends SleepRepository {
  final Map<String, SleepRecord> records = {};
  bool failUpdate = false;

  @override
  Future<void> insertSleepRecord(SleepRecord record) async {
    records[record.id] = record;
  }

  @override
  Future<SleepRecord?> getSleepRecordById(String id) async => records[id];

  @override
  Future<void> updateSleepRecord(SleepRecord record) async {
    if (failUpdate) throw Exception('update failed');
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

SleepRecord _record(String id, DateTime start) {
  return SleepRecord(
    id: id,
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

/// コンストラクタの非同期の復元が終わるのを待つ
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepository repository;

  /// 記録 record-1 で睡眠中の状態を作り、Provider に復元する
  Future<SleepProvider> sleepingProvider(DateTime start, {Map<String, Object> extra = const {}}) async {
    repository.records['record-1'] = _record('record-1', start);
    SharedPreferences.setMockInitialValues({
      _startKey: start.millisecondsSinceEpoch,
      _idKey: 'record-1',
      ...extra,
    });
    final provider = SleepProvider(repository);
    await _settle();
    await provider.initializeSleepState();
    return provider;
  }

  // テスト環境では通知プラグインが自動で登録されない（呼び出し先は下の偽物のチャンネル）
  setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);

  setUp(() {
    repository = _FakeRepository();
    WakeUpService.sleepRepositoryForTest = repository;
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

  group('起床（N143）', () {
    test('更新に成功したら SharedPreferences の ID も消える', () async {
      final start = DateTime.now().subtract(const Duration(hours: 8));
      final provider = await sleepingProvider(start);

      await WakeUpService.wakeUp(provider, DateTime.now());

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_idKey), isNull);
      expect(prefs.getInt(_startKey), isNull);
      expect(provider.currentSleepRecordIdNow, isNull);
      expect(provider.isSleepingNow, isFalse);
      expect(repository.records['record-1']!.durationMinutes, greaterThan(0));
    });

    test('1 分未満の睡眠でも ID が消える', () async {
      final start = DateTime.now().subtract(const Duration(seconds: 10));
      final provider = await sleepingProvider(start);

      await WakeUpService.wakeUp(provider, DateTime.now());

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_idKey), isNull);
      expect(provider.isSleepingNow, isFalse);
    });

    test('更新に失敗したら ID を残し、もう一度「起きる」で成功する', () async {
      final start = DateTime.now().subtract(const Duration(hours: 8));
      final provider = await sleepingProvider(start);
      repository.failUpdate = true;

      await expectLater(WakeUpService.wakeUp(provider, DateTime.now()), throwsException);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_idKey), 'record-1');
      expect(prefs.getInt(_startKey), isNotNull);
      expect(provider.currentSleepRecordIdNow, 'record-1');
      expect(provider.isSleepingNow, isTrue);

      repository.failUpdate = false;
      await WakeUpService.wakeUp(provider, DateTime.now());

      expect(prefs.getString(_idKey), isNull);
      expect(provider.isSleepingNow, isFalse);
    });

    test('通知の「停止」の起床でも ID が消える', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 8));
      final provider = await sleepingProvider(start, extra: {
        'alarm_stopped_at_ms': now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
      });

      expect(await WakeUpService.processPendingAlarmStop(provider), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_idKey), isNull);
      expect(provider.isSleepingNow, isFalse);
    });

    test('前の睡眠の ID が残らないので、次の睡眠で前の記録を上書きしない', () async {
      final start = DateTime.now().subtract(const Duration(hours: 8));
      final provider = await sleepingProvider(start);
      await WakeUpService.wakeUp(provider, DateTime.now());
      final firstRecord = repository.records['record-1'];

      final nextStart = DateTime.now().subtract(const Duration(hours: 2));
      await provider.insertSleepRecord(_record('record-2', nextStart));
      await WakeUpService.wakeUp(provider, DateTime.now());

      expect(identical(repository.records['record-1'], firstRecord), isTrue);
      expect(repository.records['record-2']!.durationMinutes, greaterThan(0));
    });
  });

  group('起動時の復元（N143）', () {
    test('睡眠中でなければ古い ID をメモリに読まず、SharedPreferences からも消す', () async {
      SharedPreferences.setMockInitialValues({_idKey: 'old-record'});

      final provider = SleepProvider(repository);
      await _settle();

      expect(provider.currentSleepRecordIdNow, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_idKey), isNull);
    });

    test('睡眠中なら ID を復元し、消さない', () async {
      SharedPreferences.setMockInitialValues({_startKey: 1, _idKey: 'record-1'});

      final provider = SleepProvider(repository);
      await _settle();

      expect(provider.currentSleepRecordIdNow, 'record-1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_idKey), 'record-1');
    });
  });

  group('「今から寝る」の保存（N143）', () {
    test('insertSleepRecord の時点で ID と開始時刻の両方が保存される', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = SleepProvider(repository);
      await _settle();

      await provider.insertSleepRecord(_record('record-2', DateTime.now()));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_idKey), 'record-2');
      expect(prefs.getInt(_startKey), isNotNull);
    });
  });
}
