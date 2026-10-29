import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';

// N70：dayRangeForSql（SQL で日付の範囲を比べるための文字列）のテスト

/// SQL の「列 >= start AND 列 < endExclusive」と同じ比べ方（TEXT は文字コード順で比べられる）
bool inRange(String value, ({String start, String endExclusive}) range) {
  return value.compareTo(range.start) >= 0 && value.compareTo(range.endExclusive) < 0;
}

void main() {
  test('1. 日付だけの引数：開始日と、終了日の翌日', () {
    final range = VacationRepository.dayRangeForSql(DateTime(2024, 1, 1), DateTime(2028, 12, 31));
    expect(range.start, '2024-01-01');
    expect(range.endExclusive, '2029-01-01');
  });

  test('2. 引数の時刻は捨てて、日付だけで範囲を決める', () {
    final range = VacationRepository.dayRangeForSql(
      DateTime(2026, 10, 29, 14, 30),
      DateTime(2026, 11, 28, 14, 30),
    );
    expect(range.start, '2026-10-29');
    expect(range.endExclusive, '2026-11-29');
  });

  test('3. UTC の引数も年・月・日のまま（toLocal しない）', () {
    final range = VacationRepository.dayRangeForSql(
      DateTime.utc(2026, 9, 30, 15),
      DateTime.utc(2026, 12, 31, 20),
    );
    expect(range.start, '2026-09-30');
    expect(range.endExclusive, '2027-01-01');
  });

  test('4. 月末・うるう年の翌日', () {
    expect(VacationRepository.dayRangeForSql(DateTime(2026, 2, 1), DateTime(2026, 2, 28)).endExclusive, '2026-03-01');
    expect(VacationRepository.dayRangeForSql(DateTime(2028, 2, 1), DateTime(2028, 2, 28)).endExclusive, '2028-02-29');
  });

  test('5. usage_date：終了日の行は Z つき・Z なしとも入り、翌日の行は入らない', () {
    final range = VacationRepository.dayRangeForSql(DateTime(2024, 1, 1), DateTime(2026, 12, 31));
    expect(inRange('2024-01-01T00:00:00.000', range), isTrue);
    expect(inRange('2024-01-01T00:00:00.000Z', range), isTrue);
    expect(inRange('2026-12-31T00:00:00.000', range), isTrue);
    expect(inRange('2026-12-31T00:00:00.000Z', range), isTrue);
    expect(inRange('2027-01-01T00:00:00.000Z', range), isFalse);
    expect(inRange('2023-12-31T00:00:00.000Z', range), isFalse);
  });

  test('6. expiry_date（23:59:59.999）：今日・30 日後の日は入り、前日・31 日後は入らない', () {
    final range = VacationRepository.dayRangeForSql(
      DateTime(2026, 9, 1, 10),
      DateTime(2026, 10, 1, 10),
    );
    expect(inRange('2026-08-31T23:59:59.999', range), isFalse);  // 昨日で失効済み
    expect(inRange('2026-09-01T23:59:59.999', range), isTrue);   // 今日まで使える
    expect(inRange('2026-10-01T23:59:59.999', range), isTrue);   // 30 日後の日
    expect(inRange('2026-10-02T23:59:59.999', range), isFalse);  // 31 日後
  });
}
