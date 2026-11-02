import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/alarm_reschedule.dart';

// N123：preAlarmRescheduleTargets・summarizeRescheduleResults・rescheduleMessage のテスト

void main() {
  group('preAlarmRescheduleTargets', () {
    final now = DateTime(2026, 11, 2, 10, 0);
    final rangeEnd = DateTime(2028, 12, 31);
    final dayOff = ShiftPatternModel(id: 'default_dayoff', patternName: '休日', patternType: ShiftType.dayOff, colorIndex: 0);
    final vacation = ShiftPatternModel(id: 'default_vacation_1day', patternName: '有休', patternType: ShiftType.vacation, colorIndex: 3);
    final halfVacation = ShiftPatternModel(id: 'default_vacation_half', patternName: '半休', patternType: ShiftType.halfVacation, colorIndex: 4);
    final early = ShiftPatternModel(
      id: 'p_early',
      patternName: '早番',
      patternType: ShiftType.work,
      startTime: const TimeOfDay(hour: 7, minute: 0),
      endTime: const TimeOfDay(hour: 16, minute: 0),
      colorIndex: 1,
    );
    final late = ShiftPatternModel(
      id: 'p_late',
      patternName: '遅番',
      patternType: ShiftType.work,
      startTime: const TimeOfDay(hour: 15, minute: 0),
      endTime: const TimeOfDay(hour: 23, minute: 0),
      colorIndex: 2,
    );
    final night = ShiftPatternModel(
      id: 'p_night',
      patternName: '深夜',
      patternType: ShiftType.work,
      startTime: const TimeOfDay(hour: 0, minute: 30),
      endTime: const TimeOfDay(hour: 9, minute: 0),
      colorIndex: 5,
    );
    final patterns = [dayOff, vacation, halfVacation, early, late, night];

    Map<String, dynamic> row(String date, String? patternId) => {'shift_date': date, 'pattern_id': patternId};

    test('1. 行がなければ空', () {
      expect(preAlarmRescheduleTargets([], patterns, dayOff, 30, now, rangeEnd), isEmpty);
    });

    test('2. 分が 0（無効）なら出勤日があっても空', () {
      final targets = preAlarmRescheduleTargets([row('2026-11-03', 'p_early')], patterns, dayOff, 0, now, rangeEnd);
      expect(targets, isEmpty);
    });

    test('3. 今日の pre がすでに過ぎている日は入らない／まだの日は入る', () {
      // 早番 7:00−30 分 = 6:30（過ぎた）、遅番 15:00−30 分 = 14:30（まだ）
      final passed = preAlarmRescheduleTargets([row('2026-11-02', 'p_early')], patterns, dayOff, 30, now, rangeEnd);
      expect(passed, isEmpty);
      final notYet = preAlarmRescheduleTargets([row('2026-11-02', 'p_late')], patterns, dayOff, 30, now, rangeEnd);
      expect(notYet.single.date, DateTime(2026, 11, 2));
      expect(notYet.single.startTime, const TimeOfDay(hour: 15, minute: 0));
      expect(notYet.single.preAt, DateTime(2026, 11, 2, 14, 30));
    });

    test('4. 開始 0:30・60 分前は前日 23:30 に鳴る（明日の分は入り、今日の分は過ぎている）', () {
      final targets = preAlarmRescheduleTargets(
        [row('2026-11-02', 'p_night'), row('2026-11-03', 'p_night')],
        patterns,
        dayOff,
        60,
        now,
        rangeEnd,
      );
      expect(targets.single.date, DateTime(2026, 11, 3));
      expect(targets.single.preAt, DateTime(2026, 11, 2, 23, 30));
    });

    test('5. 削除済み・有休・半休・休日（pattern_id が null も）は入らない', () {
      final targets = preAlarmRescheduleTargets([
        row('2026-11-03', 'gone'),
        row('2026-11-04', 'default_vacation_1day'),
        row('2026-11-05', 'default_vacation_half'),
        row('2026-11-06', 'default_dayoff'),
        row('2026-11-07', null),
      ], patterns, dayOff, 30, now, rangeEnd);
      expect(targets, isEmpty);
    });

    test('6. 範囲の終わりの日は入り、その次の日と過去の日は入らない（日付順）', () {
      final targets = preAlarmRescheduleTargets([
        row('2029-01-01', 'p_early'),
        row('2028-12-31', 'p_early'),
        row('2026-11-01', 'p_late'),
        row('2026-11-03', 'p_early'),
      ], patterns, dayOff, 30, now, rangeEnd);
      expect(targets.map((t) => t.date), [DateTime(2026, 11, 3), DateTime(2028, 12, 31)]);
    });

    test('7. shift_date が読めない行があれば例外（読み込みの失敗として扱う）', () {
      expect(
        () => preAlarmRescheduleTargets([row('broken', 'p_early')], patterns, dayOff, 30, now, rangeEnd),
        throwsFormatException,
      );
    });
  });

  group('summarizeRescheduleResults', () {
    test('1. 何もなければ 0 件・エラーなし', () {
      final result = summarizeRescheduleResults([]);
      expect(result.count, 0);
      expect(result.errorCode, isNull);
    });

    test('2. null の数が成功件数', () {
      final result = summarizeRescheduleResults([null, null, null]);
      expect(result.count, 3);
      expect(result.errorCode, isNull);
    });

    test('3. 権限エラーと失敗が混ざったら EXACT_ALARM_DENIED を優先（後に失敗が来ても）', () {
      final result = summarizeRescheduleResults([null, 'EXACT_ALARM_DENIED', 'SCHEDULE_FAILED', null]);
      expect(result.count, 2);
      expect(result.errorCode, 'EXACT_ALARM_DENIED');
    });

    test('4. 失敗のあとに権限エラーが来ても EXACT_ALARM_DENIED', () {
      final result = summarizeRescheduleResults(['SCHEDULE_FAILED', 'EXACT_ALARM_DENIED']);
      expect(result.count, 0);
      expect(result.errorCode, 'EXACT_ALARM_DENIED');
    });

    test('5. 失敗だけなら SCHEDULE_FAILED', () {
      final result = summarizeRescheduleResults([null, 'SCHEDULE_FAILED']);
      expect(result.count, 1);
      expect(result.errorCode, 'SCHEDULE_FAILED');
    });
  });

  group('rescheduleMessage', () {
    test('1. 成功 → ✅ と件数（緑）', () {
      final message = rescheduleMessage(count: 3, errorMessage: null, readFailed: false, alarmDisabled: false);
      expect(message.text, '✅ 出勤前アラームを 3件 登録し直しました');
      expect(message.color, Colors.green);
    });

    test('2. 0 件 → ℹ️（既定の色）', () {
      final message = rescheduleMessage(count: 0, errorMessage: null, readFailed: false, alarmDisabled: false);
      expect(message.text, 'ℹ️ 登録し直す出勤日はありません');
      expect(message.color, isNull);
    });

    test('3. 分が 0 → ℹ️ 無効（0 件より優先）', () {
      final message = rescheduleMessage(count: 0, errorMessage: null, readFailed: false, alarmDisabled: true);
      expect(message.text, 'ℹ️ 出勤前アラームは無効（0分）のため登録しません');
      expect(message.color, isNull);
    });

    test('4. エラー → 件数は出さず、エラーの文言だけ（オレンジ）', () {
      final message = rescheduleMessage(count: 2, errorMessage: '⚠️ 権限', readFailed: false, alarmDisabled: false);
      expect(message.text, '⚠️ 権限');
      expect(message.color, Colors.orange);
    });

    test('5. 読めなかった → ⚠️ やり直しの案内（ほかより優先・オレンジ）', () {
      final message = rescheduleMessage(count: 0, errorMessage: '⚠️ 権限', readFailed: true, alarmDisabled: true);
      expect(message.text, '⚠️ 出勤前アラームを登録し直せませんでした。もう一度 OFF → ON にするか、シフトを確定し直してください');
      expect(message.color, Colors.orange);
    });
  });
}
