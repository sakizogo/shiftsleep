// N142 4/5：睡眠状態の復元が終わるまで SleepButton を押せない
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/widgets/sleep_button.dart';

const _startKey = 'sleep_start_time_ms';
const _sleepText = '今から寝る';
const _wakeText = '起きる';
const _sleepingSnackBarText = '💤 睡眠中...「起きる」ボタンで終了します';

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

  @override
  Future<void> insertSleepRecord(SleepRecord record) async {
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
      records.values.toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepository repository;
  late _FakeStore store;

  void useStore(Map<String, Object> initial) {
    SharedPreferences.resetStatic();
    store = _FakeStore(initial);
    SharedPreferencesStorePlatform.instance = store;
  }

  /// 起動した直後（initializeSleepState の前）の Provider
  Future<SleepProvider> startedProvider(WidgetTester tester) async {
    late SleepProvider provider;
    await tester.runAsync(() async {
      provider = SleepProvider(repository);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    return provider;
  }

  Future<void> pumpButton(WidgetTester tester, SleepProvider provider) {
    return tester.pumpWidget(
      ChangeNotifierProvider<SleepProvider>.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: SleepButton())),
      ),
    );
  }

  Future<void> restore(WidgetTester tester, SleepProvider provider) async {
    await tester.runAsync(provider.initializeSleepState);
    await tester.pump();
  }

  /// タップのあとの非同期の処理が終わるのを待つ
  Future<void> settleAfterTap(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  setUp(() {
    repository = _FakeRepository();
    useStore({'is_alarm_enabled': false});
  });

  group('isSleepStateRestored', () {
    test('initializeSleepState の前は立っておらず、終わると立つ', () async {
      final provider = SleepProvider(repository);
      expect(provider.isSleepStateRestored, isFalse);

      await provider.initializeSleepState();

      expect(provider.isSleepStateRestored, isTrue);
      expect(provider.isSleepingNow, isFalse);
    });

    test('立てたことを 1 回だけ知らせる', () async {
      final provider = SleepProvider(repository);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.initializeSleepState();

      expect(notified, 1);
    });

    test('読み取りが例外でも立ち、呼び出し元に例外を出さない', () async {
      store.failRead = true;
      final provider = SleepProvider(repository);

      await provider.initializeSleepState();

      expect(provider.isSleepStateRestored, isTrue);
      expect(provider.isSleepingNow, isFalse);
    });
  });

  group('SleepButton', () {
    testWidgets('復元の前はスピナーだけで、「今から寝る」も「起きる」も出さない', (tester) async {
      final provider = await startedProvider(tester);

      await pumpButton(tester, provider);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_sleepText), findsNothing);
      expect(find.text(_wakeText), findsNothing);
    });

    testWidgets('睡眠中の保存値があっても、復元の前は「起きる」を出さない', (tester) async {
      useStore({_startKey: DateTime.now().millisecondsSinceEpoch});
      final provider = await startedProvider(tester);

      await pumpButton(tester, provider);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_wakeText), findsNothing);

      await restore(tester, provider);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_wakeText), findsOneWidget);
    });

    testWidgets('復元の前にタップしても何も起きない', (tester) async {
      final provider = await startedProvider(tester);
      await pumpButton(tester, provider);

      await tester.tap(find.byType(SleepButton));
      await settleAfterTap(tester);

      expect(repository.records, isEmpty);
      expect(provider.isSleepingNow, isFalse);
      expect(store.data.containsKey('flutter.$_startKey'), isFalse);
      expect(find.text(_sleepingSnackBarText), findsNothing);
    });

    testWidgets('復元の前に押して、復元のあとに離しても何も起きない', (tester) async {
      final provider = await startedProvider(tester);
      await pumpButton(tester, provider);

      final gesture = await tester.startGesture(tester.getCenter(find.byType(SleepButton)));
      await tester.pump();
      await restore(tester, provider);
      await gesture.up();
      await settleAfterTap(tester);

      expect(repository.records, isEmpty);
      expect(provider.isSleepingNow, isFalse);
    });

    testWidgets('復元が終わると「今から寝る」を押せる', (tester) async {
      final provider = await startedProvider(tester);
      await pumpButton(tester, provider);
      await restore(tester, provider);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_sleepText), findsOneWidget);

      await tester.tap(find.byType(SleepButton));
      await settleAfterTap(tester);

      expect(repository.records, hasLength(1));
      expect(provider.isSleepingNow, isTrue);
      expect(find.text(_sleepingSnackBarText), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('復元で読み取りに失敗しても押せるようになる', (tester) async {
      store.failRead = true;
      final provider = await startedProvider(tester);
      await pumpButton(tester, provider);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await restore(tester, provider);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_sleepText), findsOneWidget);

      store.failRead = false;
      await tester.tap(find.byType(SleepButton));
      await settleAfterTap(tester);

      expect(repository.records, hasLength(1));
      expect(provider.isSleepingNow, isTrue);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
