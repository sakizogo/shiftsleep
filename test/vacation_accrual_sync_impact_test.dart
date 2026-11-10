import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';

// N165 2a：decideCarriedOverBaseDate（持ち越しの基準日の判定）と
// evaluateAccrualSync（合わせ直したときの影響）のテスト。today はすべて固定する

final today = DateTime(2026, 11, 10);

/// 自動生成の付与の行（日数は法定の表と関係なく、渡した値）
VacationAccrual autoAccrual(int year, int month, int day, double days) {
  return VacationAccrual.create(
    userId: 'test_user',
    accrualDate: DateTime(year, month, day),
    daysGranted: days,
    notes: VacationRepository.autoAccrualNotes(DateTime(year, month, day)),
  );
}

VacationUsage usage(int year, int month, int day, [double days = 1.0]) {
  return VacationUsage.create(
    userId: 'test_user',
    usageDate: DateTime(year, month, day),
    daysUsed: days,
  );
}

/// 初回付与日 2024/10/1 で今日（2026/11/10）までに作られた付与
List<VacationAccrual> existingFrom20241001() => [
      autoAccrual(2024, 10, 1, 10),
      autoAccrual(2025, 10, 1, 11),
      autoAccrual(2026, 10, 1, 12),
    ];

/// 合わせ直しの計画と影響を、保存と同じ流れで計算する
AccrualSyncImpact impactFor({
  required List<VacationAccrual> existing,
  required DateTime newFirstAccrualDate,
  List<VacationUsage> usages = const [],
  int carriedOverDays = 5,
  int storedDays = 5,
  DateTime? storedBaseDate,
}) {
  final plan = VacationRepository.planAccrualSync(
    existing: existing,
    schedule: VacationRepository.accrualsUntil(newFirstAccrualDate, today),
  );
  return VacationRepository.evaluateAccrualSync(
    existing: existing,
    plan: plan,
    usages: usages,
    carriedOverDays: carriedOverDays,
    storedDays: storedDays,
    storedBaseDate: storedBaseDate,
    firstAccrualDate: newFirstAccrualDate,
    today: today,
  );
}

void main() {
  group('decideCarriedOverBaseDate', () {
    test('D1. 日数が 0 以下 → null（DB に基準日があっても）', () {
      for (final days in [0, -1]) {
        expect(
          VacationRepository.decideCarriedOverBaseDate(
            carriedOverDays: days,
            storedDays: days,
            storedBaseDate: DateTime(2026, 10, 1),
            accruals: existingFrom20241001(),
            firstAccrualDate: DateTime(2024, 10, 1),
            today: today,
          ),
          isNull,
        );
      }
    });

    test('D2. 日数が DB と同じで基準日があり、対象の付与が有効 → 基準日はそのまま', () {
      // 基準日 2026/10/1 → 対象は 2025/10/1 の付与（2027/9/30 まで有効）
      // 初回付与日から計算すると 2026/10/2 になる日を渡し、そちらが使われないことも確かめる
      expect(
        VacationRepository.decideCarriedOverBaseDate(
          carriedOverDays: 5,
          storedDays: 5,
          storedBaseDate: DateTime(2026, 10, 1),
          accruals: existingFrom20241001(),
          firstAccrualDate: DateTime(2024, 10, 2),
          today: today,
        ),
        DateTime(2026, 10, 1),
      );
    });

    test('D3a. 日数が DB と違う → 初回付与日から計算した今日までで最後の付与日', () {
      expect(
        VacationRepository.decideCarriedOverBaseDate(
          carriedOverDays: 3,
          storedDays: 5,
          storedBaseDate: DateTime(2025, 10, 1),
          accruals: existingFrom20241001(),
          firstAccrualDate: DateTime(2024, 10, 1),
          today: today,
        ),
        DateTime(2026, 10, 1),
      );
    });

    test('D3b. 日数は同じだが DB に基準日がない → 今日までで最後の付与日', () {
      expect(
        VacationRepository.decideCarriedOverBaseDate(
          carriedOverDays: 5,
          storedDays: 5,
          storedBaseDate: null,
          accruals: existingFrom20241001(),
          firstAccrualDate: DateTime(2024, 10, 1),
          today: today,
        ),
        DateTime(2026, 10, 1),
      );
    });

    test('D3c. 日数も基準日も同じだが、対象の付与が失効している → 今日までで最後の付与日', () {
      // 基準日 2025/10/1 → 対象は 2024/10/1 の付与（2026/9/30 で失効）
      expect(
        VacationRepository.decideCarriedOverBaseDate(
          carriedOverDays: 5,
          storedDays: 5,
          storedBaseDate: DateTime(2025, 10, 1),
          accruals: existingFrom20241001(),
          firstAccrualDate: DateTime(2024, 10, 1),
          today: today,
        ),
        DateTime(2026, 10, 1),
      );
    });

    test('D3d. 日数も基準日も同じだが、基準日より前に付与がない → 新しい初回付与日から計算した最後の付与日', () {
      // 合わせ直したあと（初回付与日 2025/10/2）の付与では、基準日 2025/10/1 より前の付与がない
      expect(
        VacationRepository.decideCarriedOverBaseDate(
          carriedOverDays: 5,
          storedDays: 5,
          storedBaseDate: DateTime(2025, 10, 1),
          accruals: [autoAccrual(2025, 10, 2, 10), autoAccrual(2026, 10, 2, 11)],
          firstAccrualDate: DateTime(2025, 10, 2),
          today: today,
        ),
        DateTime(2026, 10, 2),
      );
    });

    test('D3e. それ以外で、初回付与日がない・まだ付与が来ていない → null', () {
      for (final first in [null, DateTime(2027, 1, 1)]) {
        expect(
          VacationRepository.decideCarriedOverBaseDate(
            carriedOverDays: 3,
            storedDays: 5,
            storedBaseDate: DateTime(2026, 10, 1),
            accruals: existingFrom20241001(),
            firstAccrualDate: first,
            today: today,
          ),
          isNull,
        );
      }
    });
  });

  group('evaluateAccrualSync', () {
    test('E1. 持ち越しの対象がなくなる（初回付与日を基準日より後へ）→ carryOverTargetLost が true', () {
      // 今：基準日 2026/10/1 → 対象 2025/10/1（有効）
      // 合わせ直し後：付与は 2026/10/5 だけ → 基準日は 2026/10/5 に決め直され、その前の付与がない
      final impact = impactFor(
        existing: existingFrom20241001(),
        newFirstAccrualDate: DateTime(2026, 10, 5),
        storedBaseDate: DateTime(2026, 10, 1),
      );
      expect(impact.carryOverTargetLost, isTrue);
    });

    test('E2. 持ち越しの対象がなくならない（初回付与日を 1 日後へ）→ carryOverTargetLost が false', () {
      // 合わせ直し後：2024/10/2・2025/10/2・2026/10/2 → 基準日 2026/10/1 のまま、対象は 2025/10/2（有効）
      final impact = impactFor(
        existing: existingFrom20241001(),
        newFirstAccrualDate: DateTime(2024, 10, 2),
        storedBaseDate: DateTime(2026, 10, 1),
      );
      expect(impact.carryOverTargetLost, isFalse);
    });

    test('E3. 持ち越しの入力が 0 なら、対象がなくなる場合でも知らせない', () {
      final impact = impactFor(
        existing: existingFrom20241001(),
        newFirstAccrualDate: DateTime(2026, 10, 5),
        carriedOverDays: 0,
        storedBaseDate: DateTime(2026, 10, 1),
      );
      expect(impact.carryOverTargetLost, isFalse);
    });

    test('E4. 新しい初回付与日より前の使用がある → 件数・日数を数え、どの付与にも入らない日数が増える', () {
      final impact = impactFor(
        existing: existingFrom20241001(),
        newFirstAccrualDate: DateTime(2026, 10, 5),
        storedBaseDate: DateTime(2026, 10, 1),
        usages: [
          usage(2026, 5, 1),          // 前：2024/10/1 の付与から引ける
          usage(2026, 10, 3, 0.5),    // 前：持ち越しの対象（2025/10/1）から引ける
          usage(2026, 10, 20),        // 後：2026/10/5 の付与から引ける
        ],
      );
      expect(impact.usagesBeforeFirstCount, 2);
      expect(impact.usagesBeforeFirstDays, 1.5);
      expect(impact.unallocatedBefore, 0.0);
      expect(impact.unallocatedAfter, 1.5);
    });

    test('E5. 新しい初回付与日より前の使用がない → 0 件・0 日、どの付与にも入らない日数も増えない', () {
      final impact = impactFor(
        existing: existingFrom20241001(),
        newFirstAccrualDate: DateTime(2024, 10, 2),
        storedBaseDate: DateTime(2026, 10, 1),
        usages: [usage(2026, 10, 20)],
      );
      expect(impact.usagesBeforeFirstCount, 0);
      expect(impact.usagesBeforeFirstDays, 0.0);
      expect(impact.unallocatedBefore, 0.0);
      expect(impact.unallocatedAfter, 0.0);
    });
  });

  test('accrualsUntil は accrualsUntilToday と同じ一覧（今日を渡したとき）', () {
    final first = DateTime(2023, 4, 1);
    expect(
      VacationRepository.accrualsUntil(first, DateTime.now()),
      VacationRepository.accrualsUntilToday(first),
    );
  });
}
