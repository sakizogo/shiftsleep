import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/services/vacation_allocation.dart';

// N80：allocateUsage のテスト。today はすべて固定する

VacationAccrual accrual(int year, int month, int day, double days) {
  return VacationAccrual.create(
    userId: 'test_user',
    accrualDate: DateTime(year, month, day),
    daysGranted: days,
  );
}

VacationUsage usage(DateTime date, [double days = 1.0]) {
  return VacationUsage.create(
    userId: 'test_user',
    usageDate: date,
    daysUsed: days,
  );
}

/// 付与日で割り当て結果を探す
AccrualBalance balanceOf(VacationBalance balance, int year, int month, int day) {
  return balance.accruals.firstWhere((a) =>
      a.accrual.accrualDate.year == year &&
      a.accrual.accrualDate.month == month &&
      a.accrual.accrualDate.day == day);
}

void main() {
  final today = DateTime(2026, 10, 29);

  test('1. 付与がない → 残り 0、nextExpiring は null', () {
    final balance = allocateUsage(
      accruals: [],
      usages: [usage(DateTime(2026, 10, 5))],
      today: today,
    );
    expect(balance.totalRemaining, 0.0);
    expect(balance.nextExpiring, isNull);
    expect(balance.unallocatedDays, 1.0);
  });

  test('2. 付与 1 つ・使用なし → 付与日数がそのまま残る', () {
    final balance = allocateUsage(
      accruals: [accrual(2026, 10, 1, 20)],
      usages: [],
      today: today,
    );
    expect(balance.totalRemaining, 20.0);
    expect(balance.totalGranted, 20.0);
    expect(balance.totalUsed, 0.0);
  });

  test('3. 期間が重なる付与：古いほうからだけ引き、同じ使用を 2 回引かない（N80）', () {
    final balance = allocateUsage(
      accruals: [accrual(2025, 10, 1, 20), accrual(2026, 10, 1, 20)],
      usages: [
        usage(DateTime(2026, 10, 5)),
        usage(DateTime(2026, 10, 6)),
        usage(DateTime(2026, 10, 7)),
      ],
      today: today,
    );
    expect(balanceOf(balance, 2025, 10, 1).remainingDays, 17.0);
    expect(balanceOf(balance, 2026, 10, 1).remainingDays, 20.0);
    expect(balance.totalRemaining, 37.0);
    expect(balance.totalUsed, 3.0);
  });

  test('4. 古い付与が尽きたら次の付与から引く', () {
    final balance = allocateUsage(
      accruals: [accrual(2025, 10, 1, 1), accrual(2026, 10, 1, 20)],
      usages: [
        usage(DateTime(2026, 10, 5)),
        usage(DateTime(2026, 10, 6)),
        usage(DateTime(2026, 10, 7)),
      ],
      today: today,
    );
    expect(balanceOf(balance, 2025, 10, 1).usedDays, 1.0);
    expect(balanceOf(balance, 2025, 10, 1).remainingDays, 0.0);
    expect(balanceOf(balance, 2026, 10, 1).usedDays, 2.0);
    expect(balance.totalRemaining, 18.0);
  });

  test('5. 0.5 日：半休 2 回で 1 日、残り 0.5 に 1 日使うと 2 つの付与に分かれる', () {
    final balance = allocateUsage(
      accruals: [accrual(2025, 10, 1, 1.5), accrual(2026, 10, 1, 20)],
      usages: [
        usage(DateTime(2026, 10, 2), 0.5),
        usage(DateTime(2026, 10, 3), 0.5),
        usage(DateTime(2026, 10, 4), 1.0),
      ],
      today: today,
    );
    expect(balanceOf(balance, 2025, 10, 1).usedDays, 1.5);
    expect(balanceOf(balance, 2025, 10, 1).remainingDays, 0.0);
    expect(balanceOf(balance, 2026, 10, 1).usedDays, 0.5);
    expect(balance.totalRemaining, 19.5);
  });

  test('6. 付与が足りない → 残りは 0 でマイナスにならない', () {
    final balance = allocateUsage(
      accruals: [accrual(2026, 10, 1, 2)],
      usages: [
        usage(DateTime(2026, 10, 5)),
        usage(DateTime(2026, 10, 6)),
        usage(DateTime(2026, 10, 7)),
      ],
      today: today,
    );
    expect(balance.totalRemaining, 0.0);
    expect(balance.totalUsed, 2.0);
    expect(balance.unallocatedDays, 1.0);
  });

  test('7. その日に有効な付与がない使用（初回の付与より前・すべて失効したあと）は割り当てない', () {
    final beforeFirst = allocateUsage(
      accruals: [accrual(2025, 10, 1, 10)],
      usages: [usage(DateTime(2025, 9, 15))],
      today: today,
    );
    expect(beforeFirst.totalRemaining, 10.0);
    expect(beforeFirst.unallocatedDays, 1.0);

    final afterExpired = allocateUsage(
      accruals: [accrual(2022, 10, 1, 10)],  // 2024-09-30 に失効
      usages: [usage(DateTime(2025, 1, 10))],
      today: today,
    );
    expect(balanceOf(afterExpired, 2022, 10, 1).usedDays, 0.0);
    expect(afterExpired.unallocatedDays, 1.0);
  });

  test('8. 失効した付与：失効前の使用はそこから引き、有効な付与は減らない。合計にも入らない', () {
    final balance = allocateUsage(
      accruals: [accrual(2024, 10, 1, 20), accrual(2025, 10, 1, 20)],
      usages: [
        usage(DateTime(2026, 3, 10)),
        usage(DateTime(2026, 3, 11)),
      ],
      today: today,
    );
    final expired = balanceOf(balance, 2024, 10, 1);
    expect(expired.isExpired, isTrue);
    expect(expired.usedDays, 2.0);
    expect(balanceOf(balance, 2025, 10, 1).usedDays, 0.0);
    expect(balance.totalRemaining, 20.0);
    expect(balance.totalGranted, 20.0);
    expect(balance.totalUsed, 0.0);
  });

  test('9. 境目：付与日の当日と失効日の当日は有効、失効日の翌日は失効', () {
    final accruals = [accrual(2024, 10, 1, 10), accrual(2025, 10, 1, 10)];
    final usages = [
      usage(DateTime(2024, 10, 1)),   // 2024 の付与日の当日
      usage(DateTime(2026, 9, 30)),   // 2024 の付与の失効日の当日
      usage(DateTime(2026, 10, 1)),   // 失効日の翌日 → 2025 の付与から
    ];

    final balance = allocateUsage(accruals: accruals, usages: usages, today: today);
    expect(balanceOf(balance, 2024, 10, 1).usedDays, 2.0);
    expect(balanceOf(balance, 2025, 10, 1).usedDays, 1.0);

    final onExpiryDay = allocateUsage(accruals: accruals, usages: [], today: DateTime(2026, 9, 30));
    expect(balanceOf(onExpiryDay, 2024, 10, 1).isExpired, isFalse);
    final nextDay = allocateUsage(accruals: accruals, usages: [], today: DateTime(2026, 10, 1));
    expect(balanceOf(nextDay, 2024, 10, 1).isExpired, isTrue);
  });

  test('10. 持ち越しあり：対象の付与は持ち越し日数から始め、基準日より前の使用は引かない', () {
    final balance = allocateUsage(
      accruals: [accrual(2025, 10, 1, 20), accrual(2026, 10, 1, 20)],
      usages: [
        usage(DateTime(2026, 3, 2)),    // 基準日より前 → 対象から引かない
        usage(DateTime(2026, 10, 5)),   // 基準日以降 → 対象から引く
      ],
      today: today,
      carryOver: CarryOver(baseDate: DateTime(2026, 10, 1), days: 12),
    );
    final target = balanceOf(balance, 2025, 10, 1);
    expect(target.isCarryOverTarget, isTrue);
    expect(target.startingDays, 12.0);
    expect(target.usedDays, 1.0);
    expect(target.remainingDays, 11.0);
    expect(balanceOf(balance, 2026, 10, 1).isCarryOverTarget, isFalse);
    expect(balanceOf(balance, 2026, 10, 1).remainingDays, 20.0);
    expect(balance.totalRemaining, 31.0);
    expect(balance.unallocatedDays, 1.0);
  });

  test('11. 持ち越しが 0 や null → 付与日数どおり', () {
    final accruals = [accrual(2025, 10, 1, 20), accrual(2026, 10, 1, 20)];

    final zero = allocateUsage(
      accruals: accruals,
      usages: [],
      today: today,
      carryOver: CarryOver(baseDate: DateTime(2026, 10, 1), days: 0),
    );
    expect(zero.accruals.any((a) => a.isCarryOverTarget), isFalse);
    expect(balanceOf(zero, 2025, 10, 1).startingDays, 20.0);
    expect(zero.totalRemaining, 40.0);

    final none = allocateUsage(accruals: accruals, usages: [], today: today);
    expect(none.accruals.any((a) => a.isCarryOverTarget), isFalse);
    expect(none.totalRemaining, 40.0);
  });

  test('12. 来年の付与が来ても、持ち越しを 2026 年の付与の残りと読み替えない', () {
    final balance = allocateUsage(
      accruals: [
        accrual(2025, 10, 1, 20),
        accrual(2026, 10, 1, 20),
        accrual(2027, 10, 1, 20),
      ],
      usages: [usage(DateTime(2027, 10, 10))],
      today: DateTime(2027, 10, 15),
      carryOver: CarryOver(baseDate: DateTime(2026, 10, 1), days: 12),
    );
    expect(balanceOf(balance, 2025, 10, 1).isCarryOverTarget, isTrue);
    final accrual2026 = balanceOf(balance, 2026, 10, 1);
    expect(accrual2026.isCarryOverTarget, isFalse);
    expect(accrual2026.startingDays, 20.0);
    expect(accrual2026.usedDays, 1.0);
    expect(balance.totalRemaining, 39.0);
  });

  test('13. 持ち越しの対象の付与が失効したあと → 合計に入らない', () {
    final balance = allocateUsage(
      accruals: [
        accrual(2025, 10, 1, 20),
        accrual(2026, 10, 1, 20),
        accrual(2027, 10, 1, 20),
      ],
      usages: [
        usage(DateTime(2026, 10, 5)),
        usage(DateTime(2026, 10, 6)),
      ],
      today: DateTime(2027, 10, 15),
      carryOver: CarryOver(baseDate: DateTime(2026, 10, 1), days: 12),
    );
    final target = balanceOf(balance, 2025, 10, 1);
    expect(target.isCarryOverTarget, isTrue);
    expect(target.isExpired, isTrue);
    expect(target.remainingDays, 10.0);
    expect(balance.totalRemaining, 40.0);
  });

  test('14. 基準日より前に付与がない → 持ち越しを無視', () {
    final balance = allocateUsage(
      accruals: [accrual(2026, 10, 1, 20)],
      usages: [],
      today: today,
      carryOver: CarryOver(baseDate: DateTime(2026, 10, 1), days: 5),
    );
    expect(balance.accruals.any((a) => a.isCarryOverTarget), isFalse);
    expect(balance.totalRemaining, 20.0);
  });

  test('15. …Z つきの使用日も年・月・日のまま同じ日として扱う。12/31 の行も入る', () {
    final balance = allocateUsage(
      accruals: [accrual(2026, 10, 1, 20)],
      usages: [
        usage(DateTime.parse('2026-10-01T00:00:00.000Z')),  // 付与日の当日（UTC）
        usage(DateTime.parse('2026-12-31T00:00:00.000Z')),  // 12/31（UTC）
        usage(DateTime(2026, 12, 31), 0.5),                 // 12/31（Z なし）
        usage(DateTime.utc(2026, 9, 30, 15)),               // 年・月・日は 9/30 → 付与より前
      ],
      today: today,
    );
    expect(balanceOf(balance, 2026, 10, 1).usedDays, 2.5);
    expect(balance.unallocatedDays, 1.0);
  });

  test('16. 使用の行の並び順が違っても結果は同じ', () {
    final accruals = [accrual(2025, 10, 1, 1.5), accrual(2026, 10, 1, 20)];
    final usages = [
      usage(DateTime(2026, 10, 2), 0.5),
      usage(DateTime(2026, 10, 3), 1.0),
      usage(DateTime(2026, 10, 4), 0.5),
      usage(DateTime(2026, 10, 5), 1.0),
    ];

    final ascending = allocateUsage(accruals: accruals, usages: usages, today: today);
    final descending = allocateUsage(
      accruals: accruals.reversed.toList(),
      usages: usages.reversed.toList(),
      today: today,
    );
    for (final date in [DateTime(2025, 10, 1), DateTime(2026, 10, 1)]) {
      expect(
        balanceOf(descending, date.year, date.month, date.day).usedDays,
        balanceOf(ascending, date.year, date.month, date.day).usedDays,
      );
    }
    expect(descending.totalRemaining, ascending.totalRemaining);
  });

  test('17. nextExpiring：有効な付与のうち失効がいちばん早いもの（残り 0 でも返す）', () {
    final balance = allocateUsage(
      accruals: [
        accrual(2024, 10, 1, 20),  // 失効済み
        accrual(2025, 10, 1, 2),
        accrual(2026, 10, 1, 20),
      ],
      usages: [
        usage(DateTime(2026, 10, 5)),
        usage(DateTime(2026, 10, 6)),
      ],
      today: today,
    );
    final next = balance.nextExpiring!;
    expect(next.accrual.accrualDate, DateTime(2025, 10, 1));
    expect(next.remainingDays, 0.0);
  });

  test('18. 2/29 の付与（うるう年でない年は 2/28）', () {
    final balance = allocateUsage(
      accruals: [
        accrual(2024, 2, 29, 10),  // 2026-02-28 に失効
        accrual(2025, 2, 28, 10),
        accrual(2026, 2, 28, 10),
      ],
      usages: [
        usage(DateTime(2026, 2, 28)),  // 2024 の付与の失効日の当日
        usage(DateTime(2026, 3, 1)),   // 2024 の付与は失効 → 2025 の付与から
      ],
      today: DateTime(2026, 3, 10),
    );
    expect(balanceOf(balance, 2024, 2, 29).usedDays, 1.0);
    expect(balanceOf(balance, 2024, 2, 29).isExpired, isTrue);
    expect(balanceOf(balance, 2025, 2, 28).usedDays, 1.0);
    expect(balanceOf(balance, 2026, 2, 28).usedDays, 0.0);
    expect(balance.totalRemaining, 19.0);
  });

  test('19. 未来の使用（予定の有休）も残りから引く', () {
    final balance = allocateUsage(
      accruals: [accrual(2026, 10, 1, 20)],
      usages: [usage(DateTime(2026, 12, 20))],
      today: today,
    );
    expect(balance.totalRemaining, 19.0);
    expect(balance.totalUsed, 1.0);
  });

  test('20. 実機のデータ：付与 20 日×7・持ち越し 20 日・使用 5 日 → 37.0、消滅予定は 17.0', () {
    final balance = allocateUsage(
      accruals: [
        for (int year = 2020; year <= 2026; year++) accrual(year, 10, 1, 20),
      ],
      usages: [
        usage(DateTime(2026, 3, 10)),
        usage(DateTime(2026, 7, 15)),
        usage(DateTime(2026, 10, 5)),
        usage(DateTime(2026, 10, 6)),
        usage(DateTime(2026, 10, 7)),
      ],
      today: today,
      carryOver: CarryOver(baseDate: DateTime(2026, 10, 1), days: 20),
    );
    expect(balanceOf(balance, 2024, 10, 1).usedDays, 2.0);
    expect(balanceOf(balance, 2025, 10, 1).remainingDays, 17.0);
    expect(balanceOf(balance, 2026, 10, 1).remainingDays, 20.0);
    expect(balance.totalRemaining, 37.0);
    expect(balance.totalGranted, 40.0);
    expect(balance.totalUsed, 3.0);
    expect(balance.unallocatedDays, 0.0);

    final next = balance.nextExpiring!;
    expect(next.accrual.accrualDate, DateTime(2025, 10, 1));
    expect(next.accrual.expiryDate.year, 2027);
    expect(next.accrual.expiryDate.month, 9);
    expect(next.accrual.expiryDate.day, 30);
    expect(next.remainingDays, 17.0);
  });
}
