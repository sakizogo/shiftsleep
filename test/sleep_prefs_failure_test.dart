// N142 2/5：SharedPreferences の保存・消去の失敗を見つけて、元に戻す・知らせる
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/sleep_preference_service.dart';
import 'package:shiftsleep/services/wake_up_service.dart';
import 'package:shiftsleep/widgets/sleep_button.dart';

import 'fakes/fake_shift_repository.dart';

const _idKey = 'current_sleep_record_id';
const _startKey = 'sleep_start_time_ms';
const _shiftKey = 'current_shift_id';
const _stoppedAtKey = 'alarm_stopped_at_ms';
const _wokeText = '✅ 起床しました。睡眠が記録されました。';
const _sleepingText = '💤 睡眠中...「起きる」ボタンで終了します';

/// 端末のファイルの偽物。指定のキーの書き込みは false を返すか例外を投げ、中身は変わらない
class _FakeStore extends SharedPreferencesStorePlatform {
  _FakeStore(Map<String, Object> initial)
      : data = {for (final entry in initial.entries) 'flutter.${entry.key}': entry.value};

  final Map<String, Object> data;
  final Set<String> failKeys = {};
  final Set<String> throwKeys = {};
  final List<String> setKeys = [];

  bool hasKey(String key) => data.containsKey('flutter.$key');

  bool _canWrite(String prefixedKey) {
    final key = prefixedKey.substring('flutter.'.length);
    if (throwKeys.contains(key)) throw PlatformException(code: 'WRITE_FAILED');
    return !failKeys.contains(key);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    setKeys.add(key.substring('flutter.'.length));
    if (!_canWrite(key)) return false;
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (!_canWrite(key)) return false;
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
  bool failInsert = false;
  bool failDelete = false;
  int deleteCalls = 0;

  @override
  Future<void> insertSleepRecord(SleepRecord record) async {
    if (failInsert) throw Exception('insert failed');
    records[record.id] = record;
  }

  @override
  Future<void> deleteSleepRecord(String id) async {
    deleteCalls++;
    if (failDelete) throw Exception('delete failed');
    records.remove(id);
  }

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepository repository;
  late _FakeStore store;
  late List<String> alarmCalls;

  /// 偽物の store を入れる（SharedPreferences のキャッシュも作り直す）
  void useStore(Map<String, Object> initial) {
    SharedPreferences.resetStatic();
    store = _FakeStore(initial);
    SharedPreferencesStorePlatform.instance = store;
  }

  /// プロセスが終わって起動し直した状態の Provider（store の中身から復元する）
  Future<SleepProvider> restartedProvider() async {
    SharedPreferences.resetStatic();
    final provider = SleepProvider(repository);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await provider.initializeSleepState();
    return provider;
  }

  /// 記録 a で睡眠中の状態を作る
  Future<SleepProvider> sleepingProvider(DateTime start, {Map<String, Object> extra = const {}}) {
    repository.records['a'] = _record('a', start);
    useStore({_startKey: start.millisecondsSinceEpoch, _idKey: 'a', ...extra});
    return restartedProvider();
  }

  Future<SleepProvider> awakeProvider() async {
    final provider = SleepProvider(repository);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return provider;
  }

  // テスト環境では通知プラグインが自動で登録されない（呼び出し先は下の偽物のチャンネル）
  setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);

  setUp(() {
    repository = _FakeRepository();
    WakeUpService.sleepRepositoryForTest = repository;
    WakeUpService.shiftRepositoryForTest = FakeShiftRepository();  // N180 2/3：シフトなし（pre は取り消さない）
    useStore({});
    alarmCalls = [];
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

  group('保存メソッド', () {
    test('記録 ID：false で例外を投げる', () async {
      store.failKeys.add(_idKey);
      await expectLater(SleepPreferenceService.setCurrentSleepRecordId('a'), throwsException);
    });

    test('記録 ID：ストアの例外をそのまま外に出す', () async {
      store.throwKeys.add(_idKey);
      await expectLater(
        SleepPreferenceService.setCurrentSleepRecordId('a'),
        throwsA(isA<PlatformException>()),
      );
    });

    test('開始時刻：false で例外を投げる', () async {
      store.failKeys.add(_startKey);
      await expectLater(SleepPreferenceService.saveSleepStartTime(DateTime.now()), throwsException);
    });

    test('シフト ID：false で例外を投げる', () async {
      store.failKeys.add(_shiftKey);
      await expectLater(
        SleepPreferenceService.saveSleepStartTime(DateTime.now(), shiftId: 1),
        throwsException,
      );
    });

    test('成功すれば保存され、例外は出ない', () async {
      await SleepPreferenceService.setCurrentSleepRecordId('a');
      await SleepPreferenceService.saveSleepStartTime(DateTime.now(), shiftId: 1);
      expect(store.hasKey(_idKey), isTrue);
      expect(store.hasKey(_startKey), isTrue);
      expect(store.hasKey(_shiftKey), isTrue);
    });
  });

  group('消去メソッド', () {
    setUp(() => useStore({_startKey: 1, _shiftKey: 2, _idKey: 'a'}));

    test('成功すれば true', () async {
      expect(await SleepPreferenceService.clearSleepState(), isTrue);
      expect(await SleepPreferenceService.clearCurrentSleepRecordId(), isTrue);
      expect(store.data, isEmpty);
    });

    test('開始時刻が false なら false。シフト ID は消しにいく', () async {
      store.failKeys.add(_startKey);
      expect(await SleepPreferenceService.clearSleepState(), isFalse);
      expect(store.hasKey(_shiftKey), isFalse);
    });

    test('シフト ID が false でも false', () async {
      store.failKeys.add(_shiftKey);
      expect(await SleepPreferenceService.clearSleepState(), isFalse);
    });

    test('記録 ID が false なら false', () async {
      store.failKeys.add(_idKey);
      expect(await SleepPreferenceService.clearCurrentSleepRecordId(), isFalse);
    });

    test('ストアの例外は外に出さず false', () async {
      store.throwKeys.addAll([_startKey, _idKey]);
      expect(await SleepPreferenceService.clearSleepState(), isFalse);
      expect(await SleepPreferenceService.clearCurrentSleepRecordId(), isFalse);
    });
  });

  group('insertSleepRecord', () {
    Future<void> expectRolledBack(SleepProvider provider) async {
      expect(repository.records, isEmpty);
      expect(provider.isLoading, isFalse);
      expect(provider.isSleepingNow, isFalse);
      expect(provider.currentSleepRecordIdNow, isNull);
      expect(provider.sleepStartTime, isNull);
      expect(store.hasKey(_idKey), isFalse);
      expect(store.hasKey(_startKey), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_idKey), isNull);
      expect(prefs.getInt(_startKey), isNull);
    }

    test('ID を保存できなければ DB の行を消し、状態を戻して投げ直す', () async {
      final provider = await awakeProvider();
      store.failKeys.add(_idKey);

      await expectLater(provider.insertSleepRecord(_record('a', DateTime.now())), throwsException);

      expect(repository.deleteCalls, 1);
      await expectRolledBack(provider);
    });

    test('開始時刻を保存できなければ、先に保存した ID も DB の行も消す', () async {
      final provider = await awakeProvider();
      store.failKeys.add(_startKey);

      await expectLater(provider.insertSleepRecord(_record('a', DateTime.now())), throwsException);

      expect(repository.deleteCalls, 1);
      await expectRolledBack(provider);
    });

    test('insert が失敗したときは行を消しにいかない', () async {
      final provider = await awakeProvider();
      repository.failInsert = true;

      await expectLater(provider.insertSleepRecord(_record('a', DateTime.now())), throwsException);

      expect(repository.deleteCalls, 0);
      await expectRolledBack(provider);
    });

    test('行を消せなくても、元の保存の失敗を投げ直して状態は戻す', () async {
      final provider = await awakeProvider();
      store.failKeys.add(_idKey);
      repository.failDelete = true;

      await expectLater(
        provider.insertSleepRecord(_record('a', DateTime.now())),
        throwsA(predicate((e) => e.toString().contains('SharedPreferences'))),
      );

      expect(repository.records.keys, ['a']);
      expect(provider.isSleepingNow, isFalse);
      expect(provider.isLoading, isFalse);
    });

    test('戻しきれず ID だけが端末に残っても、起動時に消えて睡眠中にならない（N143）', () async {
      useStore({_idKey: 'b'});

      final restarted = await restartedProvider();

      expect(restarted.isSleepingNow, isFalse);
      expect(store.hasKey(_idKey), isFalse);
    });
  });

  group('起床の消去の失敗', () {
    test('開始時刻を消せなくても起床は最後まで進み、stateCleared が false', () async {
      final now = DateTime.now();
      final provider = await sleepingProvider(now.subtract(const Duration(hours: 8)));
      store.failKeys.add(_startKey);

      final result = await WakeUpService.wakeUp(provider, now);

      expect(result, (recorded: true, alarmsCancelled: true, stateCleared: false));
      expect(repository.records['a']!.durationMinutes, 480);
      expect(alarmCalls, contains('cancelAlarmWithAlarmManager'));
      expect(provider.isSleepingNow, isFalse);
      expect(provider.sleepStartTime, isNull);
      expect(store.hasKey(_startKey), isTrue);
      expect(store.hasKey(_idKey), isFalse);
    });

    test('ID を消せなくても stateCleared が false', () async {
      final now = DateTime.now();
      final provider = await sleepingProvider(now.subtract(const Duration(hours: 8)));
      store.failKeys.add(_idKey);

      expect((await WakeUpService.wakeUp(provider, now)).stateCleared, isFalse);
      expect(provider.isSleepingNow, isFalse);
    });

    test('1 分未満の睡眠でも消せなければ stateCleared が false', () async {
      final now = DateTime.now();
      final provider = await sleepingProvider(now.subtract(const Duration(seconds: 10)));
      store.failKeys.add(_startKey);

      expect((await WakeUpService.wakeUp(provider, now)).stateCleared, isFalse);
    });

    test('消せたら stateCleared が true', () async {
      final now = DateTime.now();
      final provider = await sleepingProvider(now.subtract(const Duration(hours: 8)));

      expect((await WakeUpService.wakeUp(provider, now)).stateCleared, isTrue);
      expect(store.data, isEmpty);
    });

    test('再起動で睡眠中に戻っても、もう一度の起床で完了済みの記録を上書きせず抜けられる', () async {
      final firstWake = DateTime.now();
      final provider = await sleepingProvider(firstWake.subtract(const Duration(hours: 8)));
      store.failKeys.addAll([_startKey, _idKey]);
      await WakeUpService.wakeUp(provider, firstWake);
      final finished = repository.records['a'];

      store.failKeys.clear();
      final restarted = await restartedProvider();
      expect(restarted.isSleepingNow, isTrue);

      final result = await WakeUpService.wakeUp(restarted, firstWake.add(const Duration(hours: 6)));

      expect(result.recorded, isFalse);
      expect(result.stateCleared, isTrue);
      expect(identical(repository.records['a'], finished), isTrue);
      expect(restarted.isSleepingNow, isFalse);
      expect(store.data, isEmpty);
    });

    test('通知の「停止」：⏰ を出す結果で、⚠️ も付く', () async {
      final now = DateTime.now();
      final provider = await sleepingProvider(
        now.subtract(const Duration(hours: 8)),
        extra: {_stoppedAtKey: now.millisecondsSinceEpoch},
      );
      store.failKeys.add(_startKey);

      final result = await WakeUpService.processPendingAlarmStop(provider);

      expect(result.recordedWake, isTrue);
      expect(result.warningTexts, [stateClearFailedText]);
      expect(result, isNot(PendingAlarmStopResult.woke));
      expect(provider.isSleepingNow, isFalse);
    });
  });

  group('⚠️ の文言', () {
    test('失敗したものを 記録なし → 取り消し → 消去 の順に出す', () {
      expect(wakeUpWarningTexts((recorded: true, alarmsCancelled: true, stateCleared: true)), isEmpty);
      expect(
        wakeUpWarningTexts((recorded: true, alarmsCancelled: true, stateCleared: false)),
        [stateClearFailedText],
      );
      expect(
        wakeUpWarningTexts((recorded: false, alarmsCancelled: false, stateCleared: false)),
        [noRecordWakeText, noRecordAlarmCancelFailedText, stateClearFailedText],
      );
    });
  });

  group('「今から寝る」ボタン', () {
    Future<void> tapButton(WidgetTester tester, SleepProvider provider) async {
      await tester.runAsync(provider.initializeSleepState);  // N142：復元が終わるまでは押せない
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
    }

    testWidgets('保存の失敗：赤の ❌ を出し、DB の行は残らず、アラームも登録しない', (tester) async {
      late SleepProvider provider;
      await tester.runAsync(() async {
        provider = await awakeProvider();
      });
      store.failKeys.add(_idKey);

      await tapButton(tester, provider);

      expect(find.textContaining('❌ 睡眠の記録を保存できませんでした'), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.red);
      expect(find.text(_sleepingText), findsNothing);
      expect(repository.records, isEmpty);
      expect(provider.isSleepingNow, isFalse);
      expect(alarmCalls, isEmpty);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('重複した保存を外しても、ID と開始時刻が 1 回ずつ保存されて睡眠中になる', (tester) async {
      useStore({'is_alarm_enabled': false});
      late SleepProvider provider;
      await tester.runAsync(() async {
        provider = await awakeProvider();
      });

      await tapButton(tester, provider);

      expect(find.text(_sleepingText), findsOneWidget);
      expect(store.setKeys.where((key) => key == _idKey), hasLength(1));
      expect(store.setKeys.where((key) => key == _startKey), hasLength(1));
      expect(provider.isSleepingNow, isTrue);
      expect(repository.records.keys, [provider.currentSleepRecordIdNow]);
      expect(store.data['flutter.$_idKey'], provider.currentSleepRecordIdNow);
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('「起きる」ボタン', () {
    testWidgets('消去の失敗：✅ のあとにオレンジの ⚠️ を出して、睡眠中を抜ける', (tester) async {
      late SleepProvider provider;
      await tester.runAsync(() async {
        provider = await sleepingProvider(DateTime.now().subtract(const Duration(hours: 8)));
      });
      store.failKeys.add(_startKey);
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
      expect(find.text(_wokeText), findsOneWidget);
      expect(provider.isSleepingNow, isFalse);

      // ✅ の 3 秒が終わると ⚠️ に変わる
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text(stateClearFailedText), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.orange);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
