import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/shift_load.dart';

// N118：loadBlockMessage・loadFailureMessage・shiftMapFromRows のテスト
// N118 4/4：loadPartName・loadBatchNotice のテスト

void main() {
  group('loadBlockMessage', () {
    test('失敗している部分がなければ null（止めない）', () {
      expect(loadBlockMessage({}), isNull);
    });

    test('どれか 1 つでも失敗していれば止める文言', () {
      for (final part in ShiftLoadPart.values) {
        expect(
          loadBlockMessage({part}),
          '⚠️ シフトを読み込めていないため登録・保存できません。［再読み込み］を押してください',
        );
      }
    });

    test('全部失敗していても同じ文言', () {
      expect(loadBlockMessage(ShiftLoadPart.values.toSet()), isNotNull);
    });
  });

  group('loadFailureMessage', () {
    test('部分ごとに名前を入れる', () {
      final error = Exception('db');
      expect(loadFailureMessage(ShiftLoadPart.shifts, error), '❌ シフトの読み込みに失敗しました: Exception: db');
      expect(loadFailureMessage(ShiftLoadPart.patterns, error), '❌ パターンの読み込みに失敗しました: Exception: db');
      expect(loadFailureMessage(ShiftLoadPart.vacation, error), '❌ 有休の読み込みに失敗しました: Exception: db');
    });
  });

  group('loadPartName', () {
    test('部分ごとの名前', () {
      expect(loadPartName(ShiftLoadPart.shifts), 'シフト');
      expect(loadPartName(ShiftLoadPart.patterns), 'パターン');
      expect(loadPartName(ShiftLoadPart.vacation), '有休');
    });
  });

  // N118 4/4
  group('loadBatchNotice', () {
    const reload = '。［再読み込み］を押してください';
    const conflict = '⚠️ 別の画面で変更された日の未確定シフト 2日分は、未確定の内容を残しました';

    test('失敗も衝突の知らせもなければ null（出さない）', () {
      expect(loadBatchNotice({}), isNull);
    });

    test('1 つだけ失敗：名前入りの ❌・赤・4 秒', () {
      expect(loadBatchNotice({ShiftLoadPart.shifts}),
          (text: '❌ シフトを読み込めませんでした$reload', isError: true, seconds: 4));
      expect(loadBatchNotice({ShiftLoadPart.patterns}),
          (text: '❌ パターンを読み込めませんでした$reload', isError: true, seconds: 4));
      expect(loadBatchNotice({ShiftLoadPart.vacation}),
          (text: '❌ 有休を読み込めませんでした$reload', isError: true, seconds: 4));
    });

    test('イベントだけ失敗：［再読み込み］の文は入れない（バナーも出ないため）', () {
      expect(loadBatchNotice({}, eventsFailed: true),
          (text: '❌ イベントを読み込めませんでした', isError: true, seconds: 4));
    });

    test('シフト＋パターン', () {
      expect(loadBatchNotice({ShiftLoadPart.shifts, ShiftLoadPart.patterns})!.text,
          '❌ シフト・パターンを読み込めませんでした$reload');
    });

    test('パターン＋イベント：イベントは最後', () {
      expect(loadBatchNotice({ShiftLoadPart.patterns}, eventsFailed: true)!.text,
          '❌ パターン・イベントを読み込めませんでした$reload');
    });

    test('逆の順で渡しても、シフト・パターン・有休の順に並べる', () {
      expect(
        loadBatchNotice({ShiftLoadPart.vacation, ShiftLoadPart.patterns, ShiftLoadPart.shifts})!.text,
        '❌ シフト・パターン・有休を読み込めませんでした$reload',
      );
      expect(loadBatchNotice({ShiftLoadPart.vacation, ShiftLoadPart.shifts})!.text,
          '❌ シフト・有休を読み込めませんでした$reload');
    });

    test('4 つ全部', () {
      expect(loadBatchNotice(ShiftLoadPart.values.toSet(), eventsFailed: true),
          (text: '❌ シフト・パターン・有休・イベントを読み込めませんでした$reload', isError: true, seconds: 4));
    });

    test('衝突の知らせだけ：知らせそのまま・オレンジ（isError false）・6 秒', () {
      expect(loadBatchNotice({}, mergeNotice: conflict),
          (text: conflict, isError: false, seconds: 6));
    });

    test('失敗＋衝突の知らせ：❌ の行が先・赤・6 秒', () {
      expect(loadBatchNotice({ShiftLoadPart.patterns}, eventsFailed: true, mergeNotice: conflict),
          (text: '❌ パターン・イベントを読み込めませんでした$reload\n$conflict', isError: true, seconds: 6));
    });

    test('イベントだけの失敗＋衝突の知らせ', () {
      expect(loadBatchNotice({}, eventsFailed: true, mergeNotice: conflict),
          (text: '❌ イベントを読み込めませんでした\n$conflict', isError: true, seconds: 6));
    });

    test('2 行の衝突の知らせも改行のまま後ろに付く', () {
      const twoLines = '⚠️ 削除されたパターンの未確定シフト 1日分を外しました\n$conflict';
      expect(loadBatchNotice({ShiftLoadPart.vacation}, mergeNotice: twoLines)!.text,
          '❌ 有休を読み込めませんでした$reload\n$twoLines');
    });
  });

  group('shiftMapFromRows', () {
    final dayOff = ShiftPatternModel(
      id: 'default_dayoff',
      patternName: '休日',
      patternType: ShiftType.dayOff,
      colorIndex: 0,
    );
    final early = ShiftPatternModel(
      id: 'p_early',
      patternName: '早番',
      patternType: ShiftType.work,
      startTime: const TimeOfDay(hour: 7, minute: 0),
      endTime: const TimeOfDay(hour: 16, minute: 0),
      colorIndex: 1,
    );
    final patterns = [dayOff, early];

    test('行がなければ空の Map', () {
      expect(shiftMapFromRows([], patterns, dayOff), isEmpty);
    });

    test('日付は時刻を捨てたキー、パターンは pattern_id で決める', () {
      final map = shiftMapFromRows([
        {'shift_date': '2026-11-03', 'pattern_id': 'p_early'},
        {'shift_date': '2026-11-04', 'pattern_id': 'default_dayoff'},
      ], patterns, dayOff);
      expect(map.length, 2);
      expect(map[DateTime(2026, 11, 3)], same(early));
      expect(map[DateTime(2026, 11, 4)], same(dayOff));
    });

    test('pattern_id が null なら休日、見つからなければ削除済み（元の ID のまま）', () {
      final map = shiftMapFromRows([
        {'shift_date': '2026-11-05', 'pattern_id': null},
        {'shift_date': '2026-11-06', 'pattern_id': 'gone'},
      ], patterns, dayOff);
      expect(map[DateTime(2026, 11, 5)], same(dayOff));
      final deleted = map[DateTime(2026, 11, 6)]!;
      expect(deleted.isDeleted, isTrue);
      expect(deleted.id, 'gone');
    });

    test('パターンが既定だけ（パターンの読み込みに失敗）なら、出勤の日は削除済みになる', () {
      final map = shiftMapFromRows([
        {'shift_date': '2026-11-03', 'pattern_id': 'p_early'},
      ], [dayOff], dayOff);
      expect(map[DateTime(2026, 11, 3)]!.isDeleted, isTrue);
    });

    test('shift_date が読めない行があれば例外（今の表示を残すため）', () {
      expect(
        () => shiftMapFromRows([
          {'shift_date': 'broken', 'pattern_id': 'p_early'},
        ], patterns, dayOff),
        throwsFormatException,
      );
    });
  });
}
