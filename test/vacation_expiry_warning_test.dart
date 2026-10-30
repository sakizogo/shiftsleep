import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';
import 'package:shiftsleep/services/vacation_allocation.dart';

// N89・N90：失効の警告（警告に使う失効日の選び方と文言）のテスト。today はすべて固定する
// 付与は VacationAccrual.create で作る（失効日は最後に使える日の 23:59:59.999。N60）

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

/// 割り当てたうえで、警告に使う失効日を選ぶ（getAccrualSummary と同じ流れ）
DateTime? select(List<VacationAccrual> accruals, List<VacationUsage> usages, DateTime today) {
  final balance = allocateUsage(accruals: accruals, usages: usages, today: today);
  return VacationRepository.expiryDateForWarning(balance.validAccruals, today);
}

void main() {
  // 2025-10-01 の付与 → 2027-09-30 23:59:59.999 まで使える
  final expiry = VacationAccrual.calculateExpiryDate(DateTime(2025, 10, 1));
  const lastDayMessage = '⚠️ 本日が有給を使える最後の日です';
  const expiringMessage = '⚠️ 9月30日 までに使わないと有給が消滅してしまいます。計画的に使いましょう！';

  group('文言（expiryWarningMessageFor）', () {
    test('1. 前日 → 消滅の予告', () {
      expect(VacationSummary.expiryWarningMessageFor(expiry, DateTime(2027, 9, 29, 10)), expiringMessage);
    });

    test('2. 当日（朝・夜とも）→ 最後の日（N90）', () {
      expect(VacationSummary.expiryWarningMessageFor(expiry, DateTime(2027, 9, 30, 0, 0)), lastDayMessage);
      expect(VacationSummary.expiryWarningMessageFor(expiry, DateTime(2027, 9, 30, 10)), lastDayMessage);
      expect(VacationSummary.expiryWarningMessageFor(expiry, DateTime(2027, 9, 30, 23, 59)), lastDayMessage);
    });

    test('3. 翌日 → null', () {
      expect(VacationSummary.expiryWarningMessageFor(expiry, DateTime(2027, 10, 1, 0, 0)), isNull);
      expect(VacationSummary.expiryWarningMessageFor(expiry, DateTime(2027, 10, 1, 10)), isNull);
    });

    test('4. 30 日後に失効 → 消滅の予告', () {
      expect(VacationSummary.expiryWarningMessageFor(expiry, DateTime(2027, 8, 31, 10)), expiringMessage);
    });

    test('5. 31 日後に失効 → null（対象外）', () {
      expect(VacationSummary.expiryWarningMessageFor(expiry, DateTime(2027, 8, 30, 10)), isNull);
    });
  });

  group('警告に使う失効日（expiryDateForWarning）', () {
    final today = DateTime(2027, 9, 15, 10);

    test('6. 使い切った付与（残り 0）は選ばれない（N89）', () {
      final selected = select(
        [
          accrual(2025, 10, 1, 2),   // 2027-09-30 に失効、使い切り
          accrual(2026, 10, 1, 20),  // 2028-09-30 に失効（30 日より先）
        ],
        [usage(DateTime(2027, 9, 1)), usage(DateTime(2027, 9, 2))],
        today,
      );
      expect(selected, isNull);
    });

    test('7. 早い付与を使い切り、次の付与（30 日以内）に残りがある → 次の付与の失効日', () {
      final selected = select(
        [
          accrual(2025, 9, 20, 2),   // 2027-09-19 に失効、使い切り
          accrual(2025, 10, 1, 10),  // 2027-09-30 に失効、残り 10
        ],
        [usage(DateTime(2027, 9, 1)), usage(DateTime(2027, 9, 2))],
        today,
      );
      expect(selected, expiry);
    });

    test('8. 残り 0.5 日の付与は選ばれる', () {
      final selected = select(
        [accrual(2025, 10, 1, 1)],
        [usage(DateTime(2027, 9, 1), 0.5)],
        today,
      );
      expect(selected, expiry);
    });

    test('9. 30 日以内に該当なし → null', () {
      final selected = select(
        [
          accrual(2025, 10, 17, 10),  // 2027-10-16 に失効（31 日後）
          accrual(2026, 10, 1, 20),
        ],
        [],
        today,
      );
      expect(selected, isNull);
    });

    test('10. 当日に失効する付与（残りあり）は選ばれ、文言は最後の日', () {
      final lastDay = DateTime(2027, 9, 30, 10);
      final selected = select([accrual(2025, 10, 1, 10)], [], lastDay);
      expect(selected, expiry);
      expect(VacationSummary.expiryWarningMessageFor(selected!, lastDay), lastDayMessage);
    });

    test('11. 失効した翌日は選ばれない', () {
      final selected = select([accrual(2025, 10, 1, 10)], [], DateTime(2027, 10, 1, 10));
      expect(selected, isNull);
    });
  });
}
