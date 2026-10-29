import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';

// N66：付与年度（fiscalYearOn）と、その範囲の使用日数（usedDaysInFiscalYear）のテスト。today はすべて固定する

VacationUsage usage(DateTime date, [double days = 1.0]) {
  return VacationUsage.create(
    userId: 'test_user',
    usageDate: date,
    daysUsed: days,
  );
}

void main() {
  final first = DateTime(2020, 10, 1);
  final today = DateTime(2026, 10, 29);

  test('1. 付与年度：初回 2020/10/1・今日 2026/10/29 → 2026/10/1〜2027/9/30', () {
    final fy = VacationRepository.fiscalYearOn(first, today)!;
    expect(fy.start, DateTime(2026, 10, 1));
    expect(fy.end, DateTime(2027, 9, 30));
    expect(fy.isCalendarYear, isFalse);
  });

  test('2. 今日が付与日の当日 → その日から始まる', () {
    final fy = VacationRepository.fiscalYearOn(first, DateTime(2026, 10, 1))!;
    expect(fy.start, DateTime(2026, 10, 1));
    expect(fy.end, DateTime(2027, 9, 30));
  });

  test('3. 今日が付与日の前日 → 前の付与年度', () {
    final fy = VacationRepository.fiscalYearOn(first, DateTime(2026, 9, 30))!;
    expect(fy.start, DateTime(2025, 10, 1));
    expect(fy.end, DateTime(2026, 9, 30));
  });

  test('4. 今日が初回付与日より前 → null', () {
    expect(VacationRepository.fiscalYearOn(first, DateTime(2020, 9, 30)), isNull);
  });

  test('5. 2/29 の初回付与（うるう年でない年は 2/28）', () {
    final fy = VacationRepository.fiscalYearOn(DateTime(2024, 2, 29), DateTime(2026, 3, 10))!;
    expect(fy.start, DateTime(2026, 2, 28));
    expect(fy.end, DateTime(2027, 2, 27));
  });

  test('6. 境目：開始日と最後の日（9/30）は含む・次の付与日と前の年度の 9/30 は含まない', () {
    final fy = VacationRepository.fiscalYearOn(first, today)!;
    final used = VacationRepository.usedDaysInFiscalYear([
      usage(DateTime(2026, 9, 30)),   // 前の年度の最後の日 → 含まない
      usage(DateTime(2026, 10, 1)),   // 開始日 → 含む
      usage(DateTime(2027, 9, 30)),   // 最後の日 → 含む
      usage(DateTime(2027, 10, 1)),   // 次の付与日 → 含まない
    ], fy);
    expect(used, 2.0);
    expect(fy.contains(DateTime(2027, 9, 30, 23, 59)), isTrue);
  });

  test('7. 今日より後の使用（予定）も含む', () {
    final fy = VacationRepository.fiscalYearOn(first, today)!;
    final used = VacationRepository.usedDaysInFiscalYear([
      usage(DateTime(2026, 12, 20)),
      usage(DateTime(2027, 5, 1)),
    ], fy);
    expect(used, 2.0);
  });

  test('8. Z つき・Z なしの行がどちらも同じ日として数えられる（toLocal しない）', () {
    final fy = VacationRepository.fiscalYearOn(first, today)!;
    final used = VacationRepository.usedDaysInFiscalYear([
      usage(DateTime.parse('2026-12-04T00:00:00.000Z')),  // Z つき
      usage(DateTime(2026, 12, 4), 0.5),                  // Z なし
      usage(DateTime.parse('2026-10-01T00:00:00.000Z')),  // 開始日（Z つき）
      usage(DateTime.utc(2026, 9, 30, 15)),               // 年・月・日は 9/30 → 範囲外
    ], fy);
    expect(used, 2.5);
  });

  test('9. 0.5 日の使用（半休 2 回で 1.0）', () {
    final fy = VacationRepository.fiscalYearOn(first, today)!;
    final used = VacationRepository.usedDaysInFiscalYear([
      usage(DateTime(2026, 10, 5), 0.5),
      usage(DateTime(2026, 10, 6), 0.5),
      usage(DateTime(2026, 10, 7), 0.5),
    ], fy);
    expect(used, 1.5);
  });

  test('10. 付与が 1 件もない（初回付与より前）→ 付与年度は null、使用がなければ 0', () {
    expect(VacationRepository.fiscalYearOn(DateTime(2027, 4, 1), today), isNull);

    final fy = VacationRepository.fiscalYearOn(first, today)!;
    expect(VacationRepository.usedDaysInFiscalYear([], fy), 0.0);
  });

  test('11. 実機に近いデータ：1〜9 月に 2 日、10/1 以降に 3 日（うち 2 日は今日より後）→ 3.0', () {
    final fy = VacationRepository.fiscalYearOn(first, today)!;
    final used = VacationRepository.usedDaysInFiscalYear([
      usage(DateTime(2026, 3, 10)),
      usage(DateTime(2026, 7, 15)),
      usage(DateTime(2026, 10, 5)),
      usage(DateTime.parse('2026-11-20T00:00:00.000Z')),
      usage(DateTime(2026, 12, 4)),
    ], fy);
    expect(used, 3.0);
  });

  test('12. 時刻つきの初回付与日（9 時）でも、付与日の当日からその付与年度になる', () {
    final fy = VacationRepository.fiscalYearOn(DateTime(2020, 10, 1, 9), DateTime(2026, 10, 1))!;
    expect(fy.start, DateTime(2026, 10, 1));
    expect(fy.end, DateTime(2027, 9, 30));
  });
}
