import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';
import 'package:shiftsleep/services/accrual_sync_messages.dart';

// N165 2b：有給設定の保存で付与を合わせ直すときの判定と文言のテスト

AccrualSyncImpact impact({
  bool carryOverTargetLost = false,
  DateTime? carryOverExpiryBefore,  // N171
  DateTime? carryOverExpiryAfter,  // N171
  double unallocatedBefore = 0.0,
  double unallocatedAfter = 0.0,
  int usagesBeforeFirstCount = 0,
  double usagesBeforeFirstDays = 0.0,
}) =>
    (
      carryOverTargetLost: carryOverTargetLost,
      carryOverExpiryBefore: carryOverExpiryBefore,
      carryOverExpiryAfter: carryOverExpiryAfter,
      unallocatedBefore: unallocatedBefore,
      unallocatedAfter: unallocatedAfter,
      usagesBeforeFirstCount: usagesBeforeFirstCount,
      usagesBeforeFirstDays: usagesBeforeFirstDays,
    );

const AccrualSyncPlan emptyPlan = (toDelete: [], toAdd: []);

final first = DateTime(2025, 10, 2);

void main() {
  group('isFirstAccrualDateChanged', () {
    test('M1. 入力欄が空 → 変わっていない（保存済みがあってもなくても）', () {
      expect(isFirstAccrualDateChanged(saved: DateTime(2025, 10, 1), input: null), isFalse);
      expect(isFirstAccrualDateChanged(saved: null, input: null), isFalse);
    });

    test('M2. 保存済みが null で入力がある → 変わった', () {
      expect(isFirstAccrualDateChanged(saved: null, input: DateTime(2025, 10, 1)), isTrue);
    });

    test('M3. 年月日が同じ → 変わっていない（時刻や Z があっても）', () {
      expect(isFirstAccrualDateChanged(saved: DateTime(2025, 10, 1), input: DateTime(2025, 10, 1)), isFalse);
      expect(
        isFirstAccrualDateChanged(saved: DateTime.parse('2025-10-01T00:00:00.000Z'), input: DateTime(2025, 10, 1)),
        isFalse,
      );
      expect(
        isFirstAccrualDateChanged(saved: DateTime(2025, 10, 1, 9, 30), input: DateTime(2025, 10, 1)),
        isFalse,
      );
    });

    test('M4. 年・月・日のどれかが違う → 変わった', () {
      final saved = DateTime(2025, 10, 1);
      expect(isFirstAccrualDateChanged(saved: saved, input: DateTime(2025, 10, 2)), isTrue);
      expect(isFirstAccrualDateChanged(saved: saved, input: DateTime(2025, 11, 1)), isTrue);
      expect(isFirstAccrualDateChanged(saved: saved, input: DateTime(2024, 10, 1)), isTrue);
    });
  });

  group('accrualSyncWarningLines', () {
    test('W1. 知らせることがない → 空', () {
      expect(accrualSyncWarningLines(impact: impact(), firstAccrualDate: first, carriedOverDays: 5), isEmpty);
    });

    test('W2. 持ち越しの対象がなくなる → ⚠️ と持ち越しの日数', () {
      expect(
        accrualSyncWarningLines(impact: impact(carryOverTargetLost: true), firstAccrualDate: first, carriedOverDays: 5),
        ['⚠️ 持ち越し 5 日の対象の付与がなくなり、残りに数えられなくなります'],
      );
    });

    test('W3. 初回付与日より前の使用がある → 件数・日数（ほかに入らなくなる分はなし）', () {
      expect(
        accrualSyncWarningLines(
          impact: impact(usagesBeforeFirstCount: 2, usagesBeforeFirstDays: 1.5, unallocatedAfter: 1.5),
          firstAccrualDate: first,
          carriedOverDays: 5,
        ),
        ['⚠️ 2025年10月2日より前の有休 2 件（1.5日）が、どの付与にも入らなくなります'],
      );
    });

    test('W4. 初回付与日より前の使用のほかにも入らなくなる分がある → 「ほかに◯日」を添える', () {
      expect(
        accrualSyncWarningLines(
          impact: impact(usagesBeforeFirstCount: 1, usagesBeforeFirstDays: 1.0, unallocatedBefore: 0.5, unallocatedAfter: 2.0),
          firstAccrualDate: first,
          carriedOverDays: 5,
        ),
        ['⚠️ 2025年10月2日より前の有休 1 件（1.0日）が、どの付与にも入らなくなります（ほかに 0.5日）'],
      );
    });

    test('W5. 初回付与日より前の使用はないが、入らない使用が増える → 日数だけの行', () {
      expect(
        accrualSyncWarningLines(
          impact: impact(unallocatedBefore: 1.0, unallocatedAfter: 1.5),
          firstAccrualDate: first,
          carriedOverDays: 5,
        ),
        ['⚠️ 有休 0.5日分が、どの付与にも入らなくなります'],
      );
    });

    test('W6. 入らない使用が減る・変わらない → 知らせない', () {
      expect(
        accrualSyncWarningLines(
          impact: impact(unallocatedBefore: 2.0, unallocatedAfter: 1.0),
          firstAccrualDate: first,
          carriedOverDays: 5,
        ),
        isEmpty,
      );
    });
  });

  group('accrualSyncNeedsConfirmation', () {
    test('C1. 消す・足す・⚠️ がどれもない → ダイアログを出さない', () {
      expect(
        accrualSyncNeedsConfirmation(plan: emptyPlan, impact: impact(), firstAccrualDate: first, carriedOverDays: 5),
        isFalse,
      );
    });

    test('C2. 消す付与だけ・足す付与だけ・⚠️ だけ、のどれでも出す', () {
      final row = VacationAccrual.create(
        userId: 'test_user',
        accrualDate: DateTime(2025, 10, 1),
        daysGranted: 10,
        notes: VacationRepository.autoAccrualNotes(DateTime(2025, 10, 1)),
      );
      expect(
        accrualSyncNeedsConfirmation(
            plan: (toDelete: [row], toAdd: []), impact: impact(), firstAccrualDate: first, carriedOverDays: 5),
        isTrue,
      );
      expect(
        accrualSyncNeedsConfirmation(
            plan: (toDelete: [], toAdd: [(date: first, days: 10)]),
            impact: impact(),
            firstAccrualDate: first,
            carriedOverDays: 5),
        isTrue,
      );
      expect(
        accrualSyncNeedsConfirmation(
            plan: emptyPlan, impact: impact(carryOverTargetLost: true), firstAccrualDate: first, carriedOverDays: 5),
        isTrue,
      );
    });
  });

  // N171：持ち越しの失効日が早まるときの ⚠️
  group('持ち越しの失効日が早まる（N171）', () {
    final expiryBefore = DateTime(2027, 9, 30, 23, 59, 59, 999);
    final expiryAfter = DateTime(2026, 11, 19, 23, 59, 59, 999);

    test('N171-M1. 失効日が早まる → 文言（前 → 後の失効日と持ち越しの日数）', () {
      expect(
        accrualSyncWarningLines(
          impact: impact(carryOverExpiryBefore: expiryBefore, carryOverExpiryAfter: expiryAfter),
          firstAccrualDate: first,
          carriedOverDays: 5,
        ),
        ['⚠️ 持ち越し 5 日の失効日が 2027年9月30日 → 2026年11月19日 に早まります。必要なら持ち越しの日数を見直してください'],
      );
    });

    test('N171-M2. 失効日が同じ・遅くなる・どちらかが null・持ち越しが 0 → 出さない', () {
      for (final i in [
        impact(carryOverExpiryBefore: expiryBefore, carryOverExpiryAfter: expiryBefore),
        impact(carryOverExpiryBefore: expiryAfter, carryOverExpiryAfter: expiryBefore),
        impact(carryOverExpiryBefore: null, carryOverExpiryAfter: expiryAfter),
        impact(carryOverExpiryBefore: expiryBefore, carryOverExpiryAfter: null),
      ]) {
        expect(accrualSyncWarningLines(impact: i, firstAccrualDate: first, carriedOverDays: 5), isEmpty);
      }
      expect(
        accrualSyncWarningLines(
          impact: impact(carryOverExpiryBefore: expiryBefore, carryOverExpiryAfter: expiryAfter),
          firstAccrualDate: first,
          carriedOverDays: 0,
        ),
        isEmpty,
      );
    });

    test('N171-M3. 時刻だけ違って年月日が同じ → 早まっていない', () {
      expect(
        isCarryOverExpiryShortened(
          impact: impact(
            carryOverExpiryBefore: DateTime(2027, 9, 30, 23, 59, 59, 999),
            carryOverExpiryAfter: DateTime(2027, 9, 30),
          ),
          carriedOverDays: 5,
        ),
        isFalse,
      );
      expect(
        isCarryOverExpiryShortened(
          impact: impact(
            carryOverExpiryBefore: DateTime(2027, 9, 30),
            carryOverExpiryAfter: DateTime(2027, 9, 29, 23, 59, 59, 999),
          ),
          carriedOverDays: 5,
        ),
        isTrue,
      );
    });

    test('N171-M4. 対象がなくなる ⚠️ と同時に当てはまっても、持ち越しの行は 1 行だけ（なくなる方）', () {
      expect(
        accrualSyncWarningLines(
          impact: impact(
            carryOverTargetLost: true,
            carryOverExpiryBefore: expiryBefore,
            carryOverExpiryAfter: expiryAfter,
          ),
          firstAccrualDate: first,
          carriedOverDays: 5,
        ),
        ['⚠️ 持ち越し 5 日の対象の付与がなくなり、残りに数えられなくなります'],
      );
    });

    test('N171-M5. 消す・足す付与がなく、この ⚠️ だけ → ダイアログを出す', () {
      expect(
        accrualSyncNeedsConfirmation(
          plan: emptyPlan,
          impact: impact(carryOverExpiryBefore: expiryBefore, carryOverExpiryAfter: expiryAfter),
          firstAccrualDate: first,
          carriedOverDays: 5,
        ),
        isTrue,
      );
    });

    test('N171-M6. 並び順：持ち越しの行 → 初回付与日より前の使用の行', () {
      expect(
        accrualSyncWarningLines(
          impact: impact(
            carryOverExpiryBefore: expiryBefore,
            carryOverExpiryAfter: expiryAfter,
            usagesBeforeFirstCount: 1,
            usagesBeforeFirstDays: 1.0,
            unallocatedAfter: 1.0,
          ),
          firstAccrualDate: first,
          carriedOverDays: 5,
        ),
        [
          '⚠️ 持ち越し 5 日の失効日が 2027年9月30日 → 2026年11月19日 に早まります。必要なら持ち越しの日数を見直してください',
          '⚠️ 2025年10月2日より前の有休 1 件（1.0日）が、どの付与にも入らなくなります',
        ],
      );
    });
  });

  group('文言', () {
    test('T1. ダイアログの 1 行目：保存済みが null なら「未設定」', () {
      expect(firstAccrualDateChangeText(saved: null, input: first), '初回付与日を 未設定 → 2025年10月2日 に変えます。');
      expect(
        firstAccrualDateChangeText(saved: DateTime(2025, 10, 1), input: first),
        '初回付与日を 2025年10月1日 → 2025年10月2日 に変えます。',
      );
    });

    test('T2. 保存の SnackBar：合わせ直しなし／0 件・0 件／件数あり', () {
      expect(vacationSettingsSavedMessage(null), '✅ 有給設定を保存しました');
      expect(vacationSettingsSavedMessage((deletedCount: 0, addedCount: 0)), '✅ 有給設定を保存しました（付与は変わりませんでした）');
      expect(
        vacationSettingsSavedMessage((deletedCount: 2, addedCount: 1)),
        '✅ 有給設定を保存しました\n🗑️ 付与を 2 件消し、➕ 1 件足しました',
      );
    });

    test('T3. 日付と日数の表示', () {
      expect(accrualDateText(DateTime(2025, 1, 5)), '2025年1月5日');
      expect(accrualDaysText(10), '10.0日');
      expect(accrualDaysText(0.5), '0.5日');
    });
  });

  // N165 3b：［⚡ 付与スケジュールを自動生成］（保存済みの設定で合わせ直す）の文言
  group('ボタンの文言', () {
    test('B1. ダイアログの 1 行目：保存済みの初回付与日', () {
      expect(accrualResyncFirstLine(DateTime(2024, 10, 1)), '保存済みの初回付与日（2024年10月1日）の予定に、付与を合わせ直します。');
    });

    test('B2. 確定ボタン・キャンセル・変更なし', () {
      expect(accrualResyncConfirmLabel, '付与を合わせ直す');
      expect(accrualResyncCancelledMessage, 'ℹ️ 付与は変えませんでした');
      expect(accrualResyncNoChangeMessage, 'ℹ️ 付与は予定どおりです（変更なし）');
    });

    test('B3. 成功：件数あり／0 件・0 件（保存と同じく「付与は変わりませんでした」）', () {
      expect(
        accrualResyncDoneMessage((deletedCount: 2, addedCount: 1)),
        '✅ 付与を合わせ直しました\n🗑️ 2 件消し、➕ 1 件足しました',
      );
      expect(
        accrualResyncDoneMessage((deletedCount: 0, addedCount: 3)),
        '✅ 付与を合わせ直しました\n🗑️ 0 件消し、➕ 3 件足しました',
      );
      expect(accrualResyncDoneMessage((deletedCount: 0, addedCount: 0)), '✅ 付与を合わせ直しました（付与は変わりませんでした）');
    });

    test('B4. 初回付与日なし・未保存あり', () {
      expect(accrualResyncNoFirstAccrualDateMessage, '⚠️ 初回付与日を保存してから押してください');
      expect(
        accrualResyncUnsavedChangesMessage,
        '⚠️ 先に［💾 設定を保存］を押してください（初回付与日を変えた場合は保存で付与も合わせ直します）',
      );
    });

    test('B5. 失敗の文言は ❌ で始まり、例外の中身を入れない（N118 4/4・N162）', () {
      // 引数を取らない定数なので $e は入れられない。例外の文字列が混ざっていないことも確かめる
      for (final message in [
        accrualResyncPreviewFailedMessage,
        accrualResyncFailedMessage,
        accrualResyncFirstAccrualDateChangedMessage,
      ]) {
        expect(message, startsWith('❌'));
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains(': ')));
      }
      expect(accrualResyncPreviewFailedMessage, '❌ 付与を確認できませんでした（何も変えていません）');
      expect(accrualResyncFailedMessage, '❌ 付与の合わせ直しに失敗しました（何も変えていません）');
      expect(
        accrualResyncFirstAccrualDateChangedMessage,
        '❌ 保存済みの初回付与日が変わったため、付与は合わせ直しませんでした。もう一度押してください',
      );
    });
  });
}
