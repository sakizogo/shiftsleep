import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';
import 'package:shiftsleep/services/accrual_sync_messages.dart';  // N165 3b：accrualSyncNeedsConfirmation
import 'package:shiftsleep/services/vacation_allocation.dart';  // N169：allocateUsage・CarryOver

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

  // N165 3b：［⚡ 付与スケジュールを自動生成］用（保存済みの初回付与日で合わせ直す。持ち越しには触らない）
  group('evaluateAccrualSync（keepStoredCarryOver・countUsagesBeforeFirst）', () {
    /// previewResyncWithSavedSettings と同じ渡し方（carriedOverDays は DB の日数）
    AccrualSyncImpact resyncImpactFor({
      required List<VacationAccrual> existing,
      required DateTime savedFirstAccrualDate,
      List<VacationUsage> usages = const [],
      int storedDays = 5,
      required DateTime? storedBaseDate,
      bool keepStoredCarryOver = true,
      bool countUsagesBeforeFirst = false,
    }) {
      final plan = VacationRepository.planAccrualSync(
        existing: existing,
        schedule: VacationRepository.accrualsUntil(savedFirstAccrualDate, today),
      );
      return VacationRepository.evaluateAccrualSync(
        existing: existing,
        plan: plan,
        usages: usages,
        carriedOverDays: storedDays,
        storedDays: storedDays,
        storedBaseDate: storedBaseDate,
        firstAccrualDate: savedFirstAccrualDate,
        today: today,
        keepStoredCarryOver: keepStoredCarryOver,
        countUsagesBeforeFirst: countUsagesBeforeFirst,
      );
    }

    test('K1. 失効した持ち越しが復活しない（基準日は DB のまま。既定値だと決め直されて変わる）', () {
      // 基準日 2025/10/1 → 対象 2024/10/1（2026/9/30 で失効）。差分はない
      // 使用 20 日（2026/10/20）：前は 2025/10/1（11）＋2026/10/1（12）から引けて、入らない分は 0
      final usages = [usage(2026, 10, 20, 20)];
      final kept = resyncImpactFor(
        existing: existingFrom20241001(),
        savedFirstAccrualDate: DateTime(2024, 10, 1),
        usages: usages,
        storedBaseDate: DateTime(2025, 10, 1),
      );
      expect(kept.carryOverTargetLost, isFalse);
      expect(kept.unallocatedBefore, 0.0);
      expect(kept.unallocatedAfter, 0.0);

      // 既定値（2b の保存）なら基準日が 2026/10/1 に決め直され、2025/10/1 が持ち越し 5 日の対象になる
      final recalculated = resyncImpactFor(
        existing: existingFrom20241001(),
        savedFirstAccrualDate: DateTime(2024, 10, 1),
        usages: usages,
        storedBaseDate: DateTime(2025, 10, 1),
        keepStoredCarryOver: false,
      );
      expect(recalculated.unallocatedAfter, 3.0);
    });

    test('K2. 消す行が持ち越しの対象でも、予定の行が足されれば対象は残る → carryOverTargetLost が false', () {
      // N165 の形：保存済みの初回付与日は 2024/10/1 だが、行は 10/2 で作られている。基準日 2026/10/1 → 対象 2025/10/2
      // 合わせ直し後：10/2 の 3 行を消し、10/1 の 3 行を足す → 対象は 2025/10/1（有効）
      final impact = resyncImpactFor(
        existing: [
          autoAccrual(2024, 10, 2, 10),
          autoAccrual(2025, 10, 2, 11),
          autoAccrual(2026, 10, 2, 12),
        ],
        savedFirstAccrualDate: DateTime(2024, 10, 1),
        storedBaseDate: DateTime(2026, 10, 1),
      );
      expect(impact.carryOverTargetLost, isFalse);
    });

    test('K3. 消す行が持ち越しの対象で、その前に予定の行がない → carryOverTargetLost が true', () {
      // 保存済みの初回付与日 2026/10/1：2024/10/1・2025/10/1 を消す。基準日 2026/10/1 のまま → その前に付与がない
      final impact = resyncImpactFor(
        existing: existingFrom20241001(),
        savedFirstAccrualDate: DateTime(2026, 10, 1),
        storedBaseDate: DateTime(2026, 10, 1),
      );
      expect(impact.carryOverTargetLost, isTrue);
    });

    test('K4. 差分 0 で初回付与日より前の使用があっても、数えず ⚠️ も出ない → ダイアログを出さない', () {
      final usages = [usage(2024, 5, 1)];  // 初回付与日 2024/10/1 より前。前も後も入らない
      final impact = resyncImpactFor(
        existing: existingFrom20241001(),
        savedFirstAccrualDate: DateTime(2024, 10, 1),
        usages: usages,
        storedBaseDate: DateTime(2026, 10, 1),
      );
      expect(impact.usagesBeforeFirstCount, 0);
      expect(impact.usagesBeforeFirstDays, 0.0);
      expect(impact.unallocatedBefore, 1.0);
      expect(impact.unallocatedAfter, 1.0);
      expect(
        accrualSyncNeedsConfirmation(
          plan: VacationRepository.planAccrualSync(
            existing: existingFrom20241001(),
            schedule: VacationRepository.accrualsUntil(DateTime(2024, 10, 1), today),
          ),
          impact: impact,
          firstAccrualDate: DateTime(2024, 10, 1),
          carriedOverDays: 5,
        ),
        isFalse,
      );

      // 数える（既定値）なら 1 件・1 日になる
      final counted = resyncImpactFor(
        existing: existingFrom20241001(),
        savedFirstAccrualDate: DateTime(2024, 10, 1),
        usages: usages,
        storedBaseDate: DateTime(2026, 10, 1),
        countUsagesBeforeFirst: true,
      );
      expect(counted.usagesBeforeFirstCount, 1);
      expect(counted.usagesBeforeFirstDays, 1.0);
    });

    test('K5. 既定値のまま（引数を渡さない）なら、既定値を明示したときと同じ結果（2b の保存は変わらない）', () {
      final usages = [usage(2026, 5, 1), usage(2026, 10, 3, 0.5), usage(2026, 10, 20)];
      for (final newFirst in [DateTime(2026, 10, 5), DateTime(2024, 10, 2)]) {
        final plan = VacationRepository.planAccrualSync(
          existing: existingFrom20241001(),
          schedule: VacationRepository.accrualsUntil(newFirst, today),
        );
        AccrualSyncImpact evaluate({bool explicitDefaults = false}) => explicitDefaults
            ? VacationRepository.evaluateAccrualSync(
                existing: existingFrom20241001(),
                plan: plan,
                usages: usages,
                carriedOverDays: 5,
                storedDays: 5,
                storedBaseDate: DateTime(2026, 10, 1),
                firstAccrualDate: newFirst,
                today: today,
                keepStoredCarryOver: false,
                countUsagesBeforeFirst: true,
              )
            : VacationRepository.evaluateAccrualSync(
                existing: existingFrom20241001(),
                plan: plan,
                usages: usages,
                carriedOverDays: 5,
                storedDays: 5,
                storedBaseDate: DateTime(2026, 10, 1),
                firstAccrualDate: newFirst,
                today: today,
              );
        expect(evaluate(), evaluate(explicitDefaults: true));
      }
      // E4 と同じ値（2b の結果）であることも確かめる
      expect(
        impactFor(
          existing: existingFrom20241001(),
          newFirstAccrualDate: DateTime(2026, 10, 5),
          storedBaseDate: DateTime(2026, 10, 1),
          usages: usages,
        ),
        (
          carryOverTargetLost: true,
          unallocatedBefore: 0.0,
          unallocatedAfter: 1.5,
          usagesBeforeFirstCount: 2,
          usagesBeforeFirstDays: 1.5,
        ),
      );
    });
  });

  group('isSavedFirstAccrualDateUnchanged（D5）', () {
    test('S1. 年月日が同じ → true（時刻や Z があっても）', () {
      final expected = DateTime(2024, 10, 1);
      expect(VacationRepository.isSavedFirstAccrualDateUnchanged(expected: expected, current: DateTime(2024, 10, 1)), isTrue);
      expect(VacationRepository.isSavedFirstAccrualDateUnchanged(expected: expected, current: DateTime(2024, 10, 1, 9, 30)), isTrue);
      expect(VacationRepository.isSavedFirstAccrualDateUnchanged(expected: expected, current: DateTime.utc(2024, 10, 1)), isTrue);
    });

    test('S2. 年・月・日のどれかが違う → false', () {
      final expected = DateTime(2024, 10, 1);
      for (final current in [DateTime(2025, 10, 1), DateTime(2024, 11, 1), DateTime(2024, 10, 2)]) {
        expect(VacationRepository.isSavedFirstAccrualDateUnchanged(expected: expected, current: current), isFalse);
      }
    });

    test('S3. DB が未登録（null）になった → false', () {
      expect(VacationRepository.isSavedFirstAccrualDateUnchanged(expected: DateTime(2024, 10, 1), current: null), isFalse);
    });
  });

  group('N169：初回付与日を変えて合わせ直したあと、基準日がどの付与日とも合わなければ決め直す', () {
    // 初回付与日 2024/10/2 で作られた付与。持ち越し 5 日・基準日 2026/10/2（対象は 2025/10/2 の付与）
    List<VacationAccrual> existingFrom20241002() => [
          autoAccrual(2024, 10, 2, 10),
          autoAccrual(2025, 10, 2, 11),
          autoAccrual(2026, 10, 2, 12),
        ];
    final storedBase = DateTime(2026, 10, 2);

    /// 合わせ直したあとの付与の行（existing から toDelete を除き、toAdd を足す。evaluateAccrualSync と同じ作り方）
    List<VacationAccrual> afterSync(List<VacationAccrual> existing, DateTime newFirst) {
      final plan = VacationRepository.planAccrualSync(
        existing: existing,
        schedule: VacationRepository.accrualsUntil(newFirst, today),
      );
      return [
        ...existing.where((a) => !plan.toDelete.contains(a)),
        for (final s in plan.toAdd) autoAccrual(s.date.year, s.date.month, s.date.day, s.days.toDouble()),
      ];
    }

    test('N169-0. 前提：合わせ直す前は 2025/10/2 の付与が対象で、残りは 5 + 12 = 17 日', () {
      final balance = allocateUsage(
        accruals: existingFrom20241002(),
        usages: const [],
        today: today,
        carryOver: CarryOver(baseDate: storedBase, days: 5),
      );
      final target = balance.accruals.singleWhere((a) => a.isCarryOverTarget);
      expect(target.accrual.accrualDate, DateTime(2025, 10, 2));
      expect(balance.totalRemaining, 17.0);
    });

    test('N169-1. 10/2 → 10/1 に合わせ直したあとの基準日は、新しい予定の 2026/10/1', () {
      final after = afterSync(existingFrom20241002(), DateTime(2024, 10, 1));
      final base = VacationRepository.decideCarriedOverBaseDate(
        carriedOverDays: 5,
        storedDays: 5,
        storedBaseDate: storedBase,
        accruals: after,
        firstAccrualDate: DateTime(2024, 10, 1),
        today: today,
      );
      expect(base, DateTime(2026, 10, 1));
    });

    test('N169-2. 合わせ直したあと、持ち越しの対象は 2025/10/1 の付与で、残り 17 日・消滅予定は 2025/10/1 の 5 日', () {
      final after = afterSync(existingFrom20241002(), DateTime(2024, 10, 1));
      final base = VacationRepository.decideCarriedOverBaseDate(
        carriedOverDays: 5,
        storedDays: 5,
        storedBaseDate: storedBase,
        accruals: after,
        firstAccrualDate: DateTime(2024, 10, 1),
        today: today,
      )!;
      final balance = allocateUsage(
        accruals: after,
        usages: const [],
        today: today,
        carryOver: CarryOver(baseDate: base, days: 5),
      );
      final target = balance.accruals.singleWhere((a) => a.isCarryOverTarget);
      final next = balance.nextExpiring!;
      expect(
        (
          target: target.accrual.accrualDate,
          totalRemaining: balance.totalRemaining,
          nextExpiringDate: next.accrual.accrualDate,
          nextExpiringRemaining: next.remainingDays,
        ),
        (
          target: DateTime(2025, 10, 1),
          totalRemaining: 17.0,
          nextExpiringDate: DateTime(2025, 10, 1),
          nextExpiringRemaining: 5.0,
        ),
      );
    });

    test('N169-3. 対照：10/1 → 10/2 に遅らせる向きでも、対象は前年度の付与', () {
      final existing = [
        autoAccrual(2024, 10, 1, 10),
        autoAccrual(2025, 10, 1, 11),
        autoAccrual(2026, 10, 1, 12),
      ];
      final after = afterSync(existing, DateTime(2024, 10, 2));
      final base = VacationRepository.decideCarriedOverBaseDate(
        carriedOverDays: 5,
        storedDays: 5,
        storedBaseDate: DateTime(2026, 10, 1),
        accruals: after,
        firstAccrualDate: DateTime(2024, 10, 2),
        today: today,
      )!;
      final balance = allocateUsage(
        accruals: after,
        usages: const [],
        today: today,
        carryOver: CarryOver(baseDate: base, days: 5),
      );
      final target = balance.accruals.singleWhere((a) => a.isCarryOverTarget);
      expect(target.accrual.accrualDate, DateTime(2025, 10, 2));
      expect(balance.totalRemaining, 17.0);
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
