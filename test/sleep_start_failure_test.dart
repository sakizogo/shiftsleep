// N133・N121：「今から寝る」の失敗と SnackBar
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/widgets/sleep_button.dart';

const _sleepingText = '💤 睡眠中...「起きる」ボタンで終了します';

class _FailingRepository extends SleepRepository {
  @override
  Future<void> insertSleepRecord(SleepRecord record) async {
    throw Exception('disk full');
  }
}

/// ホームと同じく、読み込み中は SleepButton がスピナーに置き換わる
class _FakeProvider extends SleepProvider {
  _FakeProvider({this.insertError}) : super(SleepRepository());

  final Object? insertError;
  bool loading = false;

  @override
  bool get isLoading => loading;

  @override
  bool get isSleepStateRestored => true;  // N142：このファイルは復元のあとの動きを見る

  @override
  Future<void> insertSleepRecord(SleepRecord record, {int? shiftId}) async {
    if (insertError != null) throw insertError!;
    loading = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    loading = false;
    notifyListeners();
  }
}

Widget _app(SleepProvider provider) {
  return ChangeNotifierProvider<SleepProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer<SleepProvider>(
          builder: (context, sleepProvider, _) => sleepProvider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : const SleepButton(),
        ),
      ),
    ),
  );
}

SleepRecord _record() {
  final now = DateTime.now();
  return SleepRecord(
    id: 'record-1',
    userId: 'test_user',
    sleepDate: DateTime(now.year, now.month, now.day),
    sleepStartTime: now,
    sleepStartAuto: true,
    sleepEndTime: now.add(const Duration(hours: 8)),
    sleepEndAuto: false,
    wakeUpType: '',
    durationMinutes: 0,
    modifiedCount: 0,
    lastModifiedAt: now,
    canEditUntil: now.add(const Duration(days: 2)),
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // アラームの登録・取り消しが呼ばれたら記録する
  final alarmCalls = <String>[];

  setUp(() {
    alarmCalls.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.sakizoapps.shiftsleep/alarm'),
      (call) async {
        alarmCalls.add(call.method);
        return null;
      },
    );
  });

  group('SleepProvider.insertSleepRecord（N121）', () {
    test('失敗したら投げ直し、スピナーを戻し、睡眠中の状態を残さない', () async {
      SharedPreferences.setMockInitialValues({
        'sleep_start_time_ms': 1,
        'current_sleep_record_id': 'old-record',
      });
      final provider = SleepProvider(_FailingRepository());
      // コンストラクタが保存済みの ID を読み終えるのを待つ
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(provider.currentSleepRecordIdNow, 'old-record');

      await expectLater(provider.insertSleepRecord(_record()), throwsException);

      expect(provider.isLoading, isFalse);
      expect(provider.isSleepingNow, isFalse);
      expect(provider.currentSleepRecordIdNow, isNull);
      expect(provider.sleepStartTime, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('sleep_start_time_ms'), isNull);
      expect(prefs.getString('current_sleep_record_id'), isNull);
    });
  });

  group('SleepButton の「今から寝る」（N133・N121）', () {
    testWidgets('スピナーで破棄されても 💤 が出る', (tester) async {
      SharedPreferences.setMockInitialValues({'is_alarm_enabled': false});
      await tester.pumpWidget(_app(_FakeProvider()));

      await tester.tap(find.byType(SleepButton));
      await tester.pump();  // スピナーに置き換わる
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(_sleepingText), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('記録を保存できなければ赤の ❌ を出し、アラームを登録しない', (tester) async {
      await tester.pumpWidget(_app(_FakeProvider(insertError: Exception('disk full'))));

      await tester.tap(find.byType(SleepButton));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, Colors.red);
      expect(
        find.text('❌ 睡眠の記録を保存できませんでした。もう一度お試しください'),
        findsOneWidget,
      );
      expect(find.text(_sleepingText), findsNothing);
      expect(alarmCalls, isEmpty);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('保存のあとで失敗したら 💤 のあとにオレンジの ⚠️ を出す', (tester) async {
      // 手動起床の値が読めないと、アラームの登録が例外になる
      SharedPreferences.setMockInitialValues({'shiftsleep_manual_wake_at': 1});
      await tester.pumpWidget(_app(_FakeProvider()));

      await tester.tap(find.byType(SleepButton));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(_sleepingText), findsOneWidget);

      // 💤 の 3 秒が終わると ⚠️ に変わる
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, Colors.orange);
      expect(find.textContaining('アラームを登録できませんでした'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
