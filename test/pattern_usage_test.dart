import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/pattern_usage.dart';

// N104：classifyPatternUsage（パターンを使っている日を今日以降と過去に分ける）のテスト

void main() {
  // 時刻つきでも日付だけで比べることを確かめるため、昼の時刻にしておく
  final today = DateTime(2026, 11, 1, 14, 30);

  test('1. 空のリスト：今日以降 0・過去 0・最初の日 null', () {
    final usage = classifyPatternUsage([], today);
    expect(usage.futureCount, 0);
    expect(usage.pastCount, 0);
    expect(usage.firstFutureDate, isNull);
  });

  test('2. 過去だけ：今日以降 0・過去の件数', () {
    final usage = classifyPatternUsage(['2026-10-01', '2026-10-15', '2026-10-31'], today);
    expect(usage.futureCount, 0);
    expect(usage.pastCount, 3);
    expect(usage.firstFutureDate, isNull);
  });

  test('3. 今日だけ：今日は今日以降に含める', () {
    final usage = classifyPatternUsage(['2026-11-01'], today);
    expect(usage.futureCount, 1);
    expect(usage.pastCount, 0);
    expect(usage.firstFutureDate, '2026-11-01');
  });

  test('4. 未来と過去が混ざる：それぞれの件数と、未来のいちばん早い日', () {
    final usage = classifyPatternUsage(
      ['2026-09-30', '2026-10-31', '2026-11-02', '2026-12-10', '2027-01-05'],
      today,
    );
    expect(usage.futureCount, 3);
    expect(usage.pastCount, 2);
    expect(usage.firstFutureDate, '2026-11-02');
  });

  test('5. 並びがばらばらでも、未来のいちばん早い日を返す', () {
    final usage = classifyPatternUsage(
      ['2027-01-05', '2026-10-31', '2026-11-20', '2026-11-03', '2026-09-30', '2026-12-10'],
      today,
    );
    expect(usage.futureCount, 4);
    expect(usage.pastCount, 2);
    expect(usage.firstFutureDate, '2026-11-03');
  });
}
