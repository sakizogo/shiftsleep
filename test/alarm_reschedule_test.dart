import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/alarm_reschedule.dart';
import 'package:shiftsleep/services/alarm_service.dart';

// N123：preAlarmRescheduleTargets・summarizeRescheduleResults・rescheduleMessage のテスト
// N124：soundSaveMessages のテスト
// N125：settingsToSave・preMinutesAction・preAlarmCancelDates・settingsSaveMessages のテスト

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

    test('4. N180 3/3：開始 0:30 は登録した日の翌日に始まり、60 分前は登録した日の 23:30 に鳴る（どちらの欄も入る）', () {
      final targets = preAlarmRescheduleTargets(
        [row('2026-11-02', 'p_night'), row('2026-11-03', 'p_night')],
        patterns,
        dayOff,
        60,
        now,
        rangeEnd,
      );
      expect(targets.map((t) => t.date), [DateTime(2026, 11, 2), DateTime(2026, 11, 3)]);
      expect(targets.map((t) => t.startAt), [DateTime(2026, 11, 3, 0, 30), DateTime(2026, 11, 4, 0, 30)]);
      expect(targets.map((t) => t.preAt), [DateTime(2026, 11, 2, 23, 30), DateTime(2026, 11, 3, 23, 30)]);
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

    // N180 3/3：0:00〜4:59 開始は前日の欄に登録する（2026-11-16 は月曜）
    group('N180 3/3：0 時台の開始', () {
      final zero = ShiftPatternModel(
        id: 'p_zero',
        patternName: '深夜 0 時',
        patternType: ShiftType.work,
        startTime: const TimeOfDay(hour: 0, minute: 0),
        endTime: const TimeOfDay(hour: 9, minute: 0),
        colorIndex: 5,
      );
      final four = ShiftPatternModel(
        id: 'p_four',
        patternName: '4 時',
        patternType: ShiftType.work,
        startTime: const TimeOfDay(hour: 4, minute: 0),
        endTime: const TimeOfDay(hour: 12, minute: 0),
        colorIndex: 5,
      );
      final all = [...patterns, zero, four];

      test('月曜の欄の 0:00・60 分前は月曜 23:00 に鳴る（日曜に登録し直しても）', () {
        final targets = preAlarmRescheduleTargets(
            [row('2026-11-16', 'p_zero')], all, dayOff, 60, DateTime(2026, 11, 15, 10, 0), rangeEnd);
        expect(targets.single.date, DateTime(2026, 11, 16));
        expect(targets.single.startAt, DateTime(2026, 11, 17, 0, 0));
        expect(targets.single.preAt, DateTime(2026, 11, 16, 23, 0));
      });

      test('月曜の昼に登録し直しても、月曜の欄の pre（月曜 23:00）は入る', () {
        final targets = preAlarmRescheduleTargets(
            [row('2026-11-16', 'p_zero')], all, dayOff, 60, DateTime(2026, 11, 16, 12, 0), rangeEnd);
        expect(targets.single.preAt, DateTime(2026, 11, 16, 23, 0));
      });

      test('夜勤が続く（月・火・水の欄）：月・火・水の 23:00 に鳴り、前の日曜には鳴らない', () {
        final targets = preAlarmRescheduleTargets(
          [row('2026-11-16', 'p_zero'), row('2026-11-17', 'p_zero'), row('2026-11-18', 'p_zero')],
          all,
          dayOff,
          60,
          DateTime(2026, 11, 15, 10, 0),
          rangeEnd,
        );
        expect(targets.map((t) => t.date), [DateTime(2026, 11, 16), DateTime(2026, 11, 17), DateTime(2026, 11, 18)]);
        expect(targets.map((t) => t.preAt),
            [DateTime(2026, 11, 16, 23, 0), DateTime(2026, 11, 17, 23, 0), DateTime(2026, 11, 18, 23, 0)]);
      });

      test('昨日の欄の 4:00・30 分前は今日 3:30 に鳴るので入る（ID は昨日の欄）', () {
        final targets = preAlarmRescheduleTargets(
            [row('2026-11-15', 'p_four')], all, dayOff, 30, DateTime(2026, 11, 16, 1, 0), rangeEnd);
        expect(targets.single.date, DateTime(2026, 11, 15));
        expect(targets.single.preAt, DateTime(2026, 11, 16, 3, 30));
      });

      test('昨日の欄でも、鳴る時刻が過ぎていれば入らない／一昨日の欄は入らない', () {
        final targets = preAlarmRescheduleTargets(
          [row('2026-11-14', 'p_four'), row('2026-11-15', 'p_four')],
          all,
          dayOff,
          30,
          DateTime(2026, 11, 16, 4, 0),
          rangeEnd,
        );
        expect(targets, isEmpty);
      });
    });
  });

  // N181：アラームを OFF にしたあとの知らせ
  group('alarmOffMessage', () {
    test('1. どちらも成功 → 🔕（既定の色）', () {
      final message = alarmOffMessage(savedCancelFailed: false, dailyCancelFailed: false);
      expect(message.text, alarmOffDoneText);
      expect(message.color, isNull);
    });

    test('2. 控えのまとめての取り消しだけ失敗 → ⚠️（オレンジ）', () {
      final message = alarmOffMessage(savedCancelFailed: true, dailyCancelFailed: false);
      expect(message.text, alarmOffPartialText);
      expect(message.color, Colors.orange);
    });

    test('3. 1 日ずつの取り消しだけ失敗（シフトを読めなかった・途中で例外）→ ⚠️', () {
      final message = alarmOffMessage(savedCancelFailed: false, dailyCancelFailed: true);
      expect(message.text, alarmOffPartialText);
      expect(message.color, Colors.orange);
    });

    test('4. どちらも失敗 → ⚠️ を 1 つだけ', () {
      final message = alarmOffMessage(savedCancelFailed: true, dailyCancelFailed: true);
      expect(message.text, alarmOffPartialText);
    });
  });

  // N181：控えの予約のまとめての取り消しの結果
  group('AlarmService.cancelAllSucceeded', () {
    test('failed が 0 なら成功（取り消した件数が 0 でも）', () {
      expect(AlarmService.cancelAllSucceeded({'cancelled': 3, 'failed': 0}), isTrue);
      expect(AlarmService.cancelAllSucceeded({'cancelled': 0, 'failed': 0}), isTrue);
    });

    test('failed が 1 以上なら失敗', () {
      expect(AlarmService.cancelAllSucceeded({'cancelled': 2, 'failed': 1}), isFalse);
    });

    test('結果がない・failed がないなら失敗', () {
      expect(AlarmService.cancelAllSucceeded(null), isFalse);
      expect(AlarmService.cancelAllSucceeded({'cancelled': 2}), isFalse);
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

  // N124：アラーム音の保存のあとの文言
  group('soundSaveMessages', () {
    test('1. 成功 n 件 → 括弧つきの ✅ 1 本（既定の色）', () {
      final messages = soundSaveMessages(count: 3, errorMessage: null, readFailed: false, alarmDisabled: false);
      expect(messages, hasLength(1));
      expect(messages[0].text, '✅ アラーム音と音量を保存しました（出勤前アラーム 3件に反映）');
      expect(messages[0].color, isNull);
    });

    test('2. 0 件 → 括弧なしの ✅ 1 本', () {
      final messages = soundSaveMessages(count: 0, errorMessage: null, readFailed: false, alarmDisabled: false);
      expect(messages.map((m) => m.text), [soundSavedText]);
      expect(messages[0].color, isNull);
    });

    test('3. 分が 0 → 括弧なしの ✅ 1 本', () {
      final messages = soundSaveMessages(count: 0, errorMessage: null, readFailed: false, alarmDisabled: true);
      expect(messages.map((m) => m.text), [soundSavedText]);
    });

    test('4. エラーのみ → 括弧なしの ✅ のあとにエラーの文言（オレンジ）', () {
      final messages = soundSaveMessages(count: 0, errorMessage: '⚠️ 失敗', readFailed: false, alarmDisabled: false);
      expect(messages.map((m) => m.text), [soundSavedText, '⚠️ 失敗']);
      expect(messages[0].color, isNull);
      expect(messages[1].color, Colors.orange);
    });

    test('5. 一部成功＋エラー → 件数は出さず、括弧なしの ✅ とエラーの文言', () {
      final messages = soundSaveMessages(count: 2, errorMessage: '⚠️ 失敗', readFailed: false, alarmDisabled: false);
      expect(messages.map((m) => m.text), [soundSavedText, '⚠️ 失敗']);
      expect(messages[1].color, Colors.orange);
    });

    test('6. 読み直し失敗 → 括弧なしの ✅ のあとに反映できなかった案内（ほかより優先・オレンジ）', () {
      final messages = soundSaveMessages(count: 0, errorMessage: '⚠️ 失敗', readFailed: true, alarmDisabled: true);
      expect(messages.map((m) => m.text), [
        soundSavedText,
        '⚠️ 出勤前アラームに反映できませんでした。もう一度保存するか、シフトを確定し直してください',
      ]);
      expect(messages[1].color, Colors.orange);
    });

    test('7. 権限エラーと失敗が混ざったら、権限エラーの文言を出す（AlarmService.alarmErrorMessage を通す）', () {
      final result = summarizeRescheduleResults([null, 'EXACT_ALARM_DENIED', 'SCHEDULE_FAILED']);
      final messages = soundSaveMessages(
        count: result.count,
        errorMessage: AlarmService.alarmErrorMessage(result.errorCode),
        readFailed: false,
        alarmDisabled: false,
      );
      expect(messages.map((m) => m.text), [
        soundSavedText,
        AlarmService.alarmErrorMessage('EXACT_ALARM_DENIED'),
      ]);
      expect(messages[1].color, Colors.orange);
    });
  });

  // N125：設定の保存で DB に書く設定
  group('settingsToSave', () {
    final createdAt = DateTime(2026, 1, 1);
    final base = AppSettings(
      id: 7,
      userId: 'test_user',
      alarmTimeBeforeShift: 30,
      wakeUpTime: '07:00',
      selectedAlarmSound: 'gentle',
      advicePromoVisible: true,
      isPremiumUser: true,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    test('1. 分数・起床時刻・案内表示だけが変わる', () {
      final saved = settingsToSave(base, alarmTimeBeforeShift: 60, wakeUpTime: '05:30', advicePromoVisible: false);
      expect(saved.alarmTimeBeforeShift, 60);
      expect(saved.wakeUpTime, '05:30');
      expect(saved.advicePromoVisible, false);
    });

    test('2. 音・premium・id・userId・createdAt は元のまま', () {
      final saved = settingsToSave(base, alarmTimeBeforeShift: 0, wakeUpTime: '05:30', advicePromoVisible: false);
      expect(saved.selectedAlarmSound, 'gentle');
      expect(saved.isPremiumUser, true);
      expect(saved.id, 7);
      expect(saved.userId, 'test_user');
      expect(saved.createdAt, createdAt);
    });
  });

  // N125：分数の変化 → pre に行うこと
  group('preMinutesAction', () {
    test('1. 分数が同じ → 何もしない', () {
      expect(preMinutesAction(30, 30), PreMinutesAction.none);
      expect(preMinutesAction(0, 0), PreMinutesAction.none);
    });

    test('2. 30→60 → 取り消して登録し直す', () {
      expect(preMinutesAction(30, 60), PreMinutesAction.cancelAndReschedule);
    });

    test('3. 30→0 → 取り消すだけ', () {
      expect(preMinutesAction(30, 0), PreMinutesAction.cancelOnly);
    });

    test('4. 0→30 → 取り消して登録し直す', () {
      expect(preMinutesAction(0, 30), PreMinutesAction.cancelAndReschedule);
    });

    test('5. 行がない（呼び出し元が 30 と比べる）→ 30 なら何もしない・40 なら登録し直す', () {
      const AppSettings? noRow = null;
      final oldMinutes = noRow?.alarmTimeBeforeShift ?? 30;
      expect(preMinutesAction(oldMinutes, 30), PreMinutesAction.none);
      expect(preMinutesAction(oldMinutes, 40), PreMinutesAction.cancelAndReschedule);
    });
  });

  // N125：分数が変わったときに pre を取り消す日
  group('preAlarmCancelDates', () {
    final today = DateTime(2026, 11, 3, 10, 0);
    final rangeEnd = DateTime(2028, 12, 31);

    Map<String, dynamic> row(String date) => {'shift_date': date, 'pattern_id': 'p_early'};

    test('1. 行がなければ空', () {
      expect(preAlarmCancelDates([], today, rangeEnd), isEmpty);
    });

    test('2. 今日と範囲の終わりの日は入り、前日・翌日は入らない（日付順・日付だけ）', () {
      final dates = preAlarmCancelDates([
        row('2029-01-01'),
        row('2028-12-31'),
        row('2026-11-02'),
        row('2026-11-03'),
      ], today, rangeEnd);
      expect(dates, [DateTime(2026, 11, 3), DateTime(2028, 12, 31)]);
    });

    test('3. 同じ日が 2 行あっても 1 回（時刻つきでも日付だけで比べる）', () {
      final dates = preAlarmCancelDates([
        row('2026-11-05'),
        row('2026-11-05T12:00:00'),
      ], today, rangeEnd);
      expect(dates, [DateTime(2026, 11, 5)]);
    });

    test('4. shift_date が読めない行があれば例外（読み込みの失敗として扱い、何も取り消さない）', () {
      expect(
        () => preAlarmCancelDates([row('2026-11-05'), row('broken')], today, rangeEnd),
        throwsFormatException,
      );
    });
  });

  // N125：設定を保存したあとの文言
  group('settingsSaveMessages', () {
    const saved = '✅ 起床時刻 7:00 に更新されました';
    const mainError = 'main error';

    test('1. 分数が変わっていない・OFF → 今の成功の文言だけ（緑）', () {
      final messages = settingsSaveMessages(savedText: saved, mainAlarmError: null, preAction: PreMinutesAction.none);
      expect(messages.map((m) => m.text), [saved]);
      expect(messages[0].color, Colors.green);
    });

    test('2. 分数が変わっていない・main の失敗 → 今のオレンジだけ', () {
      final messages = settingsSaveMessages(savedText: saved, mainAlarmError: mainError, preAction: PreMinutesAction.none);
      expect(messages.map((m) => m.text), [mainError]);
      expect(messages[0].color, Colors.orange);
    });

    test('3. 登録し直し n 件 → 成功の文言の後ろに件数', () {
      final messages = settingsSaveMessages(
        savedText: saved,
        mainAlarmError: null,
        preAction: PreMinutesAction.cancelAndReschedule,
        preCount: 3,
      );
      expect(messages.map((m) => m.text), ['$saved（出勤前アラーム 3件を登録し直しました）']);
      expect(messages[0].color, Colors.green);
    });

    test('4. 登録し直しが 0 件 → 括弧なし', () {
      final messages = settingsSaveMessages(
        savedText: saved,
        mainAlarmError: null,
        preAction: PreMinutesAction.cancelAndReschedule,
      );
      expect(messages.map((m) => m.text), [saved]);
    });

    test('5. 0 にして取り消した → 成功の文言の後ろに取り消し', () {
      final messages = settingsSaveMessages(savedText: saved, mainAlarmError: null, preAction: PreMinutesAction.cancelOnly);
      expect(messages.map((m) => m.text), ['$saved（出勤前アラームを取り消しました）']);
    });

    test('6. 読めなかった → 括弧なしの成功の文言のあとにオレンジ（エラーより優先）', () {
      for (final action in [PreMinutesAction.cancelAndReschedule, PreMinutesAction.cancelOnly]) {
        final messages = settingsSaveMessages(
          savedText: saved,
          mainAlarmError: null,
          preAction: action,
          preCount: 2,
          preErrorMessage: 'error',
          preReadFailed: true,
        );
        expect(messages.map((m) => m.text), [saved, preMinutesFailedText]);
        expect(messages[0].color, Colors.green);
        expect(messages[1].color, Colors.orange);
      }
    });

    test('7. 権限エラー → 括弧なしの成功の文言のあとに権限エラーの文言（EXACT_ALARM_DENIED を優先）', () {
      final result = summarizeRescheduleResults([null, 'EXACT_ALARM_DENIED', 'SCHEDULE_FAILED']);
      final messages = settingsSaveMessages(
        savedText: saved,
        mainAlarmError: null,
        preAction: PreMinutesAction.cancelAndReschedule,
        preCount: result.count,
        preErrorMessage: AlarmService.alarmErrorMessage(result.errorCode),
      );
      expect(messages.map((m) => m.text), [saved, AlarmService.alarmErrorMessage('EXACT_ALARM_DENIED')]);
      expect(messages[1].color, Colors.orange);
    });

    test('8. main の失敗と pre の失敗が両方 → main のオレンジのあとに pre のオレンジ（成功の文言は出さない）', () {
      final messages = settingsSaveMessages(
        savedText: saved,
        mainAlarmError: mainError,
        preAction: PreMinutesAction.cancelAndReschedule,
        preReadFailed: true,
      );
      expect(messages.map((m) => m.text), [mainError, preMinutesFailedText]);
    });

    test('9. main の失敗で pre は登録し直せた → main のオレンジだけ（括弧はつけない）', () {
      final messages = settingsSaveMessages(
        savedText: saved,
        mainAlarmError: mainError,
        preAction: PreMinutesAction.cancelAndReschedule,
        preCount: 3,
      );
      expect(messages.map((m) => m.text), [mainError]);
    });
  });
}
