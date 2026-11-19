// N193：案内の表示（advicePromoVisible）を切り替えたら、保存して Provider の値をすぐ変える
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';

class _NoRepository extends SleepRepository {
  @override
  Future<SleepRecord?> getLatestSleepRecord(String userId) async => null;

  @override
  Future<List<SleepRecord>> getSleepRecordsByDateRange(String userId, DateTime startDate, DateTime endDate) async =>
      const [];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('保存できたら true を返し、値が変わり、notifyListeners が 1 回呼ばれる', () async {
    final provider = SleepProvider(_NoRepository());
    var notified = 0;
    provider.addListener(() => notified++);
    expect(provider.advicePromoVisible, isTrue);

    final saved = await provider.setAdvicePromoVisible(false, save: (userId, visible) async {});

    expect(saved, isTrue);
    expect(provider.advicePromoVisible, isFalse);
    expect(notified, 1);
  });

  test('保存できなければ false を返し、値は変えず、notifyListeners も呼ばない', () async {
    final provider = SleepProvider(_NoRepository());
    var notified = 0;
    provider.addListener(() => notified++);

    final saved = await provider.setAdvicePromoVisible(false, save: (userId, visible) async => throw Exception('db'));

    expect(saved, isFalse);
    expect(provider.advicePromoVisible, isTrue);
    expect(notified, 0);
  });

  test('save には test_user と指定した値が渡る', () async {
    final provider = SleepProvider(_NoRepository());
    final calls = <(String, bool)>[];

    await provider.setAdvicePromoVisible(false, save: (userId, visible) async => calls.add((userId, visible)));
    await provider.setAdvicePromoVisible(true, save: (userId, visible) async => calls.add((userId, visible)));

    expect(calls, [('test_user', false), ('test_user', true)]);
    expect(provider.advicePromoVisible, isTrue);
  });

  testWidgets('保存できたら、Provider を見ている画面は開き直さなくても変わる', (tester) async {
    final provider = SleepProvider(_NoRepository());
    await tester.pumpWidget(
      ChangeNotifierProvider<SleepProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Consumer<SleepProvider>(
            builder: (context, p, _) => Text(p.advicePromoVisible ? '案内あり' : '案内なし'),
          ),
        ),
      ),
    );
    expect(find.text('案内あり'), findsOneWidget);

    await provider.setAdvicePromoVisible(false, save: (userId, visible) async {});
    await tester.pump();

    expect(find.text('案内なし'), findsOneWidget);
  });
}
