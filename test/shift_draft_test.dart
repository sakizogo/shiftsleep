import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/shift_draft.dart';

// N140：未確定の差分（computeShiftDraft・editsWithoutBase・overlayShiftDraft・mergeShiftDraft・
// draftMergeNotice・ShiftDraftStore）のテスト

ShiftPatternModel _work(String id, {int hour = 8}) => ShiftPatternModel(
      id: id,
      patternName: id,
      patternType: ShiftType.work,
      startTime: TimeOfDay(hour: hour, minute: 0),
    );

void main() {
  final dayA = DateTime(2026, 11, 10);
  final dayB = DateTime(2026, 11, 11);
  final dayC = DateTime(2026, 11, 12);
  final early = _work('early');
  final late = _work('late');

  group('computeShiftDraft', () {
    test('同じ内容なら空', () {
      final draft = computeShiftDraft(base: {dayA: early}, current: {dayA: early});
      expect(draft.isEmpty, isTrue);
    });

    test('追加は基準なし（basePatternId が null）で作る', () {
      final draft = computeShiftDraft(base: {}, current: {dayA: early});
      final entry = draft.entries[dayA]!;
      expect(entry.pattern?.id, 'early');
      expect(entry.basePatternId, isNull);
      expect(entry.baseKnown, isTrue);
    });

    test('変更は基準の ID を持つ', () {
      final draft = computeShiftDraft(base: {dayA: early}, current: {dayA: late});
      final entry = draft.entries[dayA]!;
      expect(entry.pattern?.id, 'late');
      expect(entry.basePatternId, 'early');
    });

    test('削除は pattern が null で、基準の ID を持つ', () {
      final draft = computeShiftDraft(base: {dayA: early}, current: {});
      final entry = draft.entries[dayA]!;
      expect(entry.pattern, isNull);
      expect(entry.basePatternId, 'early');
    });

    test('「削除済み」の行が変わっていなければ差分にならない', () {
      final deleted = ShiftPatternModel.deleted('gone');
      final draft = computeShiftDraft(base: {dayA: deleted}, current: {dayA: deleted});
      expect(draft.isEmpty, isTrue);
    });

    test('オブジェクトが違っても ID が同じなら差分にならない', () {
      final draft = computeShiftDraft(base: {dayA: early}, current: {dayA: _work('early', hour: 9)});
      expect(draft.isEmpty, isTrue);
    });

    test('未確定の追加を × で消すと差分がなくなる', () {
      final added = {dayA: early};
      expect(computeShiftDraft(base: {}, current: added).length, 1);
      added.remove(dayA);
      expect(computeShiftDraft(base: {}, current: added).isEmpty, isTrue);
    });
  });

  group('editsWithoutBase', () {
    test('基準を読む前の変更は追加だけで baseKnown が false', () {
      final draft = editsWithoutBase({dayA: early});
      final entry = draft.entries[dayA]!;
      expect(entry.pattern?.id, 'early');
      expect(entry.basePatternId, isNull);
      expect(entry.baseKnown, isFalse);
    });

    test('何も入れていなければ空', () {
      expect(editsWithoutBase({}).isEmpty, isTrue);
    });
  });

  group('overlayShiftDraft', () {
    test('同じ日は新しい方の内容にし、基準は古い方を引き継ぐ', () {
      final older = ShiftDraft({dayA: ShiftDraftEntry(pattern: early, basePatternId: 'night')});
      final result = overlayShiftDraft(older, editsWithoutBase({dayA: late}));
      final entry = result.entries[dayA]!;
      expect(entry.pattern?.id, 'late');
      expect(entry.basePatternId, 'night');
      expect(entry.baseKnown, isTrue);
    });

    test('古い方の基準が不明なら新しい方の基準を使う', () {
      final result = overlayShiftDraft(
        editsWithoutBase({dayA: early}),
        ShiftDraft({dayA: ShiftDraftEntry(pattern: late, basePatternId: 'night')}),
      );
      final entry = result.entries[dayA]!;
      expect(entry.basePatternId, 'night');
      expect(entry.baseKnown, isTrue);
    });

    test('別の日は両方残る', () {
      final result = overlayShiftDraft(
        ShiftDraft({dayA: ShiftDraftEntry(pattern: early, basePatternId: null)}),
        ShiftDraft({dayB: ShiftDraftEntry(pattern: late, basePatternId: null)}),
      );
      expect(result.entries.keys, containsAll([dayA, dayB]));
    });
  });

  group('mergeShiftDraft', () {
    final patterns = [early, late];

    test('差分が空なら DB の内容のまま', () {
      final result = mergeShiftDraft(db: {dayA: early}, draft: const ShiftDraft(), patterns: patterns);
      expect(result.merged, {dayA: early});
      expect(result.conflictDates, isEmpty);
      expect(result.removedDates, isEmpty);
    });

    test('追加を重ねる', () {
      final draft = computeShiftDraft(base: {}, current: {dayA: early});
      final result = mergeShiftDraft(db: {}, draft: draft, patterns: patterns);
      expect(result.merged[dayA]?.id, 'early');
      expect(result.conflictDates, isEmpty);
    });

    test('変更で上書きする', () {
      final draft = computeShiftDraft(base: {dayA: early}, current: {dayA: late});
      final result = mergeShiftDraft(db: {dayA: early}, draft: draft, patterns: patterns);
      expect(result.merged[dayA]?.id, 'late');
      expect(result.conflictDates, isEmpty);
    });

    test('削除で行を消す', () {
      final draft = computeShiftDraft(base: {dayA: early}, current: {});
      final result = mergeShiftDraft(db: {dayA: early}, draft: draft, patterns: patterns);
      expect(result.merged.containsKey(dayA), isFalse);
      expect(result.conflictDates, isEmpty);
    });

    test('差分のない日は DB の新しい内容になる', () {
      final draft = computeShiftDraft(base: {dayA: early}, current: {dayA: early, dayB: late});
      final result = mergeShiftDraft(db: {dayA: late}, draft: draft, patterns: patterns);
      expect(result.merged[dayA]?.id, 'late');
      expect(result.merged[dayB]?.id, 'late');
    });

    test('DB がもう同じ内容なら捨てて、知らせない', () {
      final draft = computeShiftDraft(base: {}, current: {dayA: early});
      final result = mergeShiftDraft(db: {dayA: early}, draft: draft, patterns: patterns);
      expect(result.merged[dayA]?.id, 'early');
      expect(result.conflictDates, isEmpty);
    });

    test('削除の差分で DB の行がもうないなら捨てて、知らせない', () {
      final draft = computeShiftDraft(base: {dayA: early}, current: {});
      final result = mergeShiftDraft(db: {}, draft: draft, patterns: patterns);
      expect(result.merged.containsKey(dayA), isFalse);
      expect(result.conflictDates, isEmpty);
    });

    test('別の画面で行が消えていたら、未確定を優先して衝突に数える', () {
      final draft = computeShiftDraft(base: {dayA: early}, current: {dayA: late});
      final result = mergeShiftDraft(db: {}, draft: draft, patterns: patterns);
      expect(result.merged[dayA]?.id, 'late');
      expect(result.conflictDates, [dayA]);
    });

    test('別の画面で行が変わっていたら、未確定を優先して衝突に数える', () {
      final other = _work('other');
      final draft = computeShiftDraft(base: {dayA: early}, current: {dayA: late});
      final result = mergeShiftDraft(db: {dayA: other}, draft: draft, patterns: [early, late, other]);
      expect(result.merged[dayA]?.id, 'late');
      expect(result.conflictDates, [dayA]);
    });

    test('別の画面で行が変わった日の未確定の削除も優先する', () {
      final draft = computeShiftDraft(base: {dayA: early}, current: {});
      final result = mergeShiftDraft(db: {dayA: late}, draft: draft, patterns: patterns);
      expect(result.merged.containsKey(dayA), isFalse);
      expect(result.conflictDates, [dayA]);
    });

    test('baseKnown が false なら衝突に数えない', () {
      final result = mergeShiftDraft(
        db: {dayA: early},
        draft: editsWithoutBase({dayA: late}),
        patterns: patterns,
      );
      expect(result.merged[dayA]?.id, 'late');
      expect(result.conflictDates, isEmpty);
    });

    test('パターンが消えていたら外して、その日は DB の内容になる', () {
      final gone = _work('gone');
      final draft = computeShiftDraft(
        base: {dayA: early},
        current: {dayA: gone, dayB: gone},
      );
      final result = mergeShiftDraft(db: {dayA: early}, draft: draft, patterns: patterns);
      expect(result.merged[dayA]?.id, 'early');
      expect(result.merged.containsKey(dayB), isFalse);
      expect(result.removedDates, [dayA, dayB]);
      expect(result.conflictDates, isEmpty);
    });

    test('patterns が null なら（読めていないなら）外さず、持っているパターンを使う', () {
      final gone = _work('gone');
      final draft = computeShiftDraft(base: {}, current: {dayA: gone});
      final result = mergeShiftDraft(db: {}, draft: draft, patterns: null);
      expect(result.merged[dayA], same(gone));
      expect(result.removedDates, isEmpty);
    });

    test('同じ ID の新しいパターンに置き換わる（編集した開始時刻が使われる）', () {
      final edited = _work('early', hour: 10);
      final draft = computeShiftDraft(base: {}, current: {dayA: early});
      final result = mergeShiftDraft(db: {}, draft: draft, patterns: [edited, late]);
      expect(result.merged[dayA], same(edited));
    });

    test('マージ → 差分 → マージでも結果が同じで、衝突を 2 度数えない', () {
      final draft = computeShiftDraft(base: {dayA: early}, current: {dayA: late, dayB: early});
      final db = {dayC: early};
      final first = mergeShiftDraft(db: db, draft: draft, patterns: patterns);
      expect(first.conflictDates, [dayA]);

      final again = computeShiftDraft(base: db, current: first.merged);
      final second = mergeShiftDraft(db: db, draft: again, patterns: patterns);
      expect(second.conflictDates, isEmpty);
      expect(second.merged.keys.toSet(), first.merged.keys.toSet());
      expect(second.merged[dayA]?.id, 'late');
      expect(second.merged[dayB]?.id, 'early');
      expect(second.merged[dayC]?.id, 'early');
    });

    test('入力の Map を書き換えない', () {
      final db = {dayA: early};
      final draft = computeShiftDraft(base: {dayA: early}, current: {dayB: late});
      mergeShiftDraft(db: db, draft: draft, patterns: patterns);
      expect(db, {dayA: early});
      expect(draft.length, 2);
    });
  });

  group('draftMergeNotice', () {
    ShiftDraftMergeResult resultOf({List<DateTime> conflict = const [], List<DateTime> removed = const []}) =>
        ShiftDraftMergeResult(merged: const {}, conflictDates: conflict, removedDates: removed);

    test('知らせることがなければ null', () {
      expect(draftMergeNotice(resultOf()), isNull);
    });

    test('パターンの削除で外した日数', () {
      expect(
        draftMergeNotice(resultOf(removed: [dayA, dayB])),
        '⚠️ 削除されたパターンの未確定シフト 2日分を外しました',
      );
    });

    test('衝突の日数', () {
      expect(
        draftMergeNotice(resultOf(conflict: [dayA])),
        '⚠️ 別の画面で変更された日の未確定シフト 1日分は、未確定の内容を残しました',
      );
    });

    test('両方あれば 2 行にまとめる', () {
      expect(
        draftMergeNotice(resultOf(conflict: [dayA], removed: [dayB])),
        '⚠️ 削除されたパターンの未確定シフト 1日分を外しました\n'
        '⚠️ 別の画面で変更された日の未確定シフト 1日分は、未確定の内容を残しました',
      );
    });
  });

  group('ShiftDraftStore', () {
    test('saveFromScreen は基準と今の内容の差分を預かる', () {
      final store = ShiftDraftStore();
      store.saveFromScreen(base: {dayA: early}, current: {dayA: late, dayB: early});
      expect(store.draft.length, 2);
      expect(store.draft.entries[dayA]?.basePatternId, 'early');
    });

    test('基準を読めていない State の saveFromScreen は、今の差分を消さずに重ねる', () {
      final store = ShiftDraftStore();
      store.saveFromScreen(base: {dayA: early}, current: {dayA: late});
      store.saveFromScreen(base: null, current: {dayB: early});
      expect(store.draft.entries[dayA]?.pattern?.id, 'late');
      expect(store.draft.entries[dayB]?.baseKnown, isFalse);
    });

    test('基準を読めず何も入れていない State の saveFromScreen は、今の差分をそのまま残す', () {
      final store = ShiftDraftStore();
      store.saveFromScreen(base: {dayA: early}, current: {dayA: late});
      store.saveFromScreen(base: null, current: {});
      expect(store.draft.length, 1);
    });

    test('captureDetails は詳細確認の編集・削除を反映する', () {
      final store = ShiftDraftStore();
      store.saveFromScreen(base: {dayA: early}, current: {dayA: early, dayB: early});
      store.captureDetails({dayB: late});
      expect(store.draft.entries[dayA]?.pattern, isNull);
      expect(store.draft.entries[dayB]?.pattern?.id, 'late');
    });

    test('基準がなければ captureDetails は何もしない', () {
      final store = ShiftDraftStore();
      store.captureDetails({dayA: early});
      expect(store.draft.isEmpty, isTrue);
    });

    test('clear で空になり、そのあとの captureDetails で差分が復活しない', () {
      final store = ShiftDraftStore();
      store.saveFromScreen(base: {}, current: {dayA: early});
      store.clear();
      expect(store.draft.isEmpty, isTrue);
      store.captureDetails({dayA: early});
      expect(store.draft.isEmpty, isTrue);
    });

    test('addLateEdits は今の差分を消さずに重ねる', () {
      final store = ShiftDraftStore();
      store.saveFromScreen(base: {}, current: {dayA: early});
      store.addLateEdits(computeShiftDraft(base: {}, current: {dayB: late}));
      expect(store.draft.entries.keys, containsAll([dayA, dayB]));
    });

    test('confirmedCount は預かった基準の日数で、clear で 0 に戻る', () {
      final store = ShiftDraftStore();
      expect(store.confirmedCount, 0);
      store.saveFromScreen(base: {dayA: early, dayB: late}, current: {});
      expect(store.confirmedCount, 2);
      store.clear();
      expect(store.confirmedCount, 0);
    });
  });

  // N140 2/4
  group('未確定の日数', () {
    test('追加・変更・削除はそれぞれ 1 日に数える', () {
      final draft = computeShiftDraft(
        base: {dayA: early, dayB: early},
        current: {dayA: late, dayC: early},
      );
      expect(draft.length, 3);
    });

    test('入れて元に戻すと 0 日になる', () {
      final base = {dayA: early};
      expect(computeShiftDraft(base: base, current: {dayA: late}).length, 1);
      expect(computeShiftDraft(base: base, current: {dayA: early}).length, 0);
    });
  });

  group('ShiftDraftStore.pendingCount', () {
    test('saveFromScreen はその場では通知せず、microtask のあとに件数が変わる', () async {
      final store = ShiftDraftStore();
      store.saveFromScreen(base: {}, current: {dayA: early, dayB: early});
      expect(store.pendingCount.value, 0);
      await Future<void>.delayed(Duration.zero);
      expect(store.pendingCount.value, 2);
    });

    test('captureDetails で詳細確認の編集が反映される', () async {
      final store = ShiftDraftStore();
      store.saveFromScreen(base: {dayA: early}, current: {dayA: early});
      await Future<void>.delayed(Duration.zero);
      expect(store.pendingCount.value, 0);
      store.captureDetails({dayA: late, dayB: late});
      expect(store.pendingCount.value, 2);
    });

    test('addLateEdits で増える', () {
      final store = ShiftDraftStore();
      store.addLateEdits(computeShiftDraft(base: {}, current: {dayA: early}));
      expect(store.pendingCount.value, 1);
    });

    test('clear で 0 になる', () {
      final store = ShiftDraftStore();
      store.addLateEdits(computeShiftDraft(base: {}, current: {dayA: early}));
      store.clear();
      expect(store.pendingCount.value, 0);
    });

    test('reportLive は件数だけを変え、預かっている差分には触らない', () {
      final store = ShiftDraftStore();
      store.addLateEdits(computeShiftDraft(base: {}, current: {dayA: early}));
      store.reportLive(computeShiftDraft(base: {}, current: {dayA: early, dayB: early, dayC: early}));
      expect(store.pendingCount.value, 3);
      expect(store.draft.length, 1);
    });

    test('dispose のあとに microtask が動いても、呼ばれても例外にならない', () async {
      final store = ShiftDraftStore();
      store.saveFromScreen(base: {}, current: {dayA: early});
      store.dispose();
      await Future<void>.delayed(Duration.zero);
      store.reportLive(const ShiftDraft());
      store.addLateEdits(const ShiftDraft());
      store.clear();
    });
  });

  group('文言', () {
    test('バナーに日数と進み方が出る', () {
      expect(
        draftBannerText(3),
        '📝 未確定のシフトが 3日分あります。「確認へ進む」→「シフトを確定」で保存されます',
      );
    });

    test('バッジは 99 までそのまま、100 からは 99+', () {
      expect(draftBadgeLabel(1), '1');
      expect(draftBadgeLabel(99), '99');
      expect(draftBadgeLabel(100), '99+');
    });

    test('シフトを入れたときは未確定と書く', () {
      expect(shiftPlacedMessage('日勤', pending: true), '📝 日勤を入れました（未確定）');
    });

    test('確定済みと同じなら未確定と書かない', () {
      expect(shiftPlacedMessage('日勤', pending: false), '✅ 日勤は確定済みのシフトと同じです');
    });

    test('有休は残日数に反映済みと書く', () {
      expect(
        vacationPlacedMessage('有休', pending: true, replacedWork: false),
        '📝 有休を入れました（未確定）\n有休の残日数にはもう反映されています',
      );
    });

    test('出勤を有休にしたらアラームの案内も足す', () {
      expect(
        vacationPlacedMessage('有休', pending: true, replacedWork: true),
        '📝 有休を入れました（未確定）\n有休の残日数にはもう反映されています\n'
        '「シフトを確定」を押すと出勤前アラームが取り消されます',
      );
    });

    test('有休が確定済みと同じなら未確定と書かない', () {
      expect(
        vacationPlacedMessage('有休', pending: false, replacedWork: true),
        '✅ 有休は確定済みのシフトと同じです',
      );
    });

    test('期間指定も未確定と書く', () {
      expect(rangeAddedMessage(5), '📝 5日入れました（未確定）');
    });

    test('見出し：未確定がなければ全日数だけ', () {
      expect(shiftListHeader(20, const ShiftDraft()), '登録中のシフト: 20日');
    });

    test('見出し：未確定があれば追加・変更と削除を分ける', () {
      final draft = computeShiftDraft(
        base: {dayA: early, dayB: early},
        current: {dayA: late, dayC: early},
      );
      expect(shiftListHeader(2, draft), '登録中のシフト: 2日（📝 未確定 3日：追加・変更 2／削除 1）');
    });

    test('見出し：全部 × しても削除の日数が出る', () {
      final draft = computeShiftDraft(base: {dayA: early, dayB: early}, current: {});
      expect(shiftListHeader(0, draft), '登録中のシフト: 0日（📝 未確定 2日：追加・変更 0／削除 2）');
    });

    test('破棄のダイアログは、確定済みが変わらないことと有休が戻らないことを書く', () {
      final body = draftDiscardDialogBody(2);
      expect(body, contains('未確定の 2日分'));
      expect(body, contains('確定済みのシフトは変わりません'));
      expect(body, contains('有休・半休の登録は元に戻りません'));
    });

    test('破棄したあとの知らせに日数が出る', () {
      expect(draftDiscardedMessage(2), '📝 未確定の 2日分を破棄しました');
    });

    test('閉じるダイアログは、閉じると消えることを書く', () {
      final body = draftCloseDialogBody(4);
      expect(body, contains('未確定のシフトが 4日分'));
      expect(body, contains('閉じると消えます'));
    });

    test('全部消すダイアログは、日数とアラームの取り消しを書く', () {
      expect(
        deleteAllDialogBody(5),
        '確定済みのシフト 5日分がすべて削除され、出勤前アラームも取り消されます。',
      );
    });
  });

  group('canProceedToConfirm', () {
    test('シフトがあれば押せる', () {
      expect(canProceedToConfirm(totalDays: 3, pendingDays: 0), isTrue);
    });

    test('全部 × して 0 日でも、未確定があれば押せる', () {
      expect(canProceedToConfirm(totalDays: 0, pendingDays: 2), isTrue);
    });

    test('シフトも未確定もなければ押せない', () {
      expect(canProceedToConfirm(totalDays: 0, pendingDays: 0), isFalse);
    });
  });

  group('shouldConfirmDeleteAll', () {
    test('0 日で確定済みがあれば確かめる', () {
      expect(shouldConfirmDeleteAll(shiftDays: 0, confirmedDays: 5), isTrue);
    });

    test('1 日でも残っていれば確かめない', () {
      expect(shouldConfirmDeleteAll(shiftDays: 1, confirmedDays: 5), isFalse);
    });

    test('確定済みがなければ消えるものがないので確かめない', () {
      expect(shouldConfirmDeleteAll(shiftDays: 0, confirmedDays: 0), isFalse);
    });
  });

  group('shiftBackAction', () {
    test('詳細確認ならカレンダーへ戻る（未確定があっても閉じない）', () {
      expect(shiftBackAction(isDetails: true, pendingCount: 3), ShiftBackAction.backToCalendar);
      expect(shiftBackAction(isDetails: true, pendingCount: 0), ShiftBackAction.backToCalendar);
    });

    test('未確定があれば確かめてから閉じる', () {
      expect(shiftBackAction(isDetails: false, pendingCount: 1), ShiftBackAction.confirmClose);
    });

    test('未確定がなければそのまま閉じる', () {
      expect(shiftBackAction(isDetails: false, pendingCount: 0), ShiftBackAction.close);
    });
  });
}
