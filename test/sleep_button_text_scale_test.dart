// N51 F：大きい文字（font_scale 1.3・2.0）でも SleepButton の文字が丸の中に 1 行で収まる
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/widgets/sleep_button.dart';

const _startKey = 'sleep_start_time_ms';

/// DB の偽物（記録は使わない）
class _FakeRepository extends SleepRepository {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 復元まで終えた SleepButton を、文字の倍率 scale で出す
  Future<void> pumpRestoredButton(WidgetTester tester, double scale) async {
    late SleepProvider provider;
    await tester.runAsync(() async {
      provider = SleepProvider(_FakeRepository());
      await provider.initializeSleepState();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<SleepProvider>.value(
        value: provider,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(body: Center(child: SleepButton())),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 文字が丸（120×120）の中に収まり、1 行（テスト用フォントは 1 文字 1em 四方）である
  void expectFitsInOneLine(WidgetTester tester, String text, double fontSize, double scale) {
    final button = tester.getRect(find.byType(SleepButton));
    final label = tester.getRect(find.text(text));
    expect(button.contains(label.topLeft), isTrue, reason: '$text の左上が丸の外');
    expect(button.contains(label.bottomRight - const Offset(0.01, 0.01)), isTrue, reason: '$text の右下が丸の外');
    // 折り返すと幅が 1 行ぶん（文字数 × 文字の大きさ。letterSpacing の分は広くてよい）より狭くなる
    expect(tester.getSize(find.text(text)).width, greaterThanOrEqualTo(text.length * fontSize * scale - 0.01),
        reason: '$text が折り返している');
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('倍率 $scale：「今から寝る」が丸の中に 1 行で収まる', (tester) async {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.withData({
        'flutter.is_alarm_enabled': false,
      });
      await pumpRestoredButton(tester, scale);

      expect(tester.takeException(), isNull);
      expectFitsInOneLine(tester, '今から寝る', 16, scale);
    });

    testWidgets('倍率 $scale：「睡眠中」「起きる」が丸の中に 1 行ずつで収まる', (tester) async {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.withData({
        'flutter.is_alarm_enabled': false,
        'flutter.$_startKey': DateTime.now().millisecondsSinceEpoch,
      });
      await pumpRestoredButton(tester, scale);

      expect(tester.takeException(), isNull);
      expectFitsInOneLine(tester, '睡眠中', 14, scale);
      expectFitsInOneLine(tester, '起きる', 12, scale);
    });
  }
}
