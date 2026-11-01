import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/sleep_record_validation.dart';

// N106：睡眠を手で追加するときの日時の決め方と保存前のチェックのテスト

/// テスト用の既存の記録
SleepRecord record(String id, DateTime start, DateTime end) {
  return SleepRecord(
    id: id,
    userId: 'test_user',
    sleepDate: DateTime(start.year, start.month, start.day),
    sleepStartTime: start,
    sleepStartAuto: true,
    sleepEndTime: end,
    sleepEndAuto: false,
    wakeUpType: '',
    durationMinutes: end.difference(start).inMinutes,
    lastModifiedAt: start,
    canEditUntil: end.add(const Duration(days: 2)),
    createdAt: start,
    updatedAt: start,
  );
}

/// Flutter の Slider（divisions あり）が onChanged に渡す値と同じ計算
/// 0〜1 の位置を k / divisions に丸め、min〜max に戻す（slider.dart の _discretize と _lerp）
double flutterSliderValue(int k, {required int divisions, double min = 0, required double max}) {
  final t = k / divisions;
  return t * (max - min) + min;
}

void main() {
  final now = DateTime(2026, 11, 1, 12, 0);

  group('スライダーの値 → 時・分', () {
    test('21. 時（0〜23・divisions 23）はすべての値が出る', () {
      final hours = [
        for (var k = 0; k <= 23; k++)
          SleepRecordValidation.sliderValueToTimePart(flutterSliderValue(k, divisions: 23, max: 23), max: 23),
      ];
      expect(hours, List.generate(24, (i) => i));
    });

    test('22. 分（0〜59・divisions 59）はすべての値が出る', () {
      final minutes = [
        for (var k = 0; k <= 59; k++)
          SleepRecordValidation.sliderValueToTimePart(flutterSliderValue(k, divisions: 59, max: 59), max: 59),
      ];
      expect(minutes, List.generate(60, (i) => i));
    });

    test('23. 前の toInt() では飛ぶ値があった（不具合の再現）', () {
      final skippedHours = [
        for (var k = 0; k <= 23; k++)
          if (flutterSliderValue(k, divisions: 23, max: 23).toInt() != k) k,
      ];
      final skippedMinutes = [
        for (var k = 0; k <= 59; k++)
          if (flutterSliderValue(k, divisions: 59, max: 59).toInt() != k) k,
      ];
      // 13 / 23 * 23 = 12.999999999999998 になり、toInt() で 12 になる
      expect(skippedHours, [13]);
      expect(skippedMinutes, isEmpty);
    });

    test('24. 範囲の外の値は 0〜max に収める', () {
      expect(SleepRecordValidation.sliderValueToTimePart(-0.4, max: 23), 0);
      expect(SleepRecordValidation.sliderValueToTimePart(23.4, max: 23), 23);
      expect(SleepRecordValidation.sliderValueToTimePart(24.0, max: 23), 23);
    });
  });

  group('起床日の自動決定', () {
    test('1. 日をまたぐ（23:00 → 7:00）は起床が翌日', () {
      final t = SleepRecordValidation.resolveTimes(
        bedDate: DateTime(2026, 10, 31),
        bedHour: 23, bedMinute: 0, wakeHour: 7, wakeMinute: 0,
      );
      expect(t.start, DateTime(2026, 10, 31, 23, 0));
      expect(t.end, DateTime(2026, 11, 1, 7, 0));
    });

    test('2. 日をまたがない（1:00 → 7:30）は起床も同じ日', () {
      final t = SleepRecordValidation.resolveTimes(
        bedDate: DateTime(2026, 10, 31),
        bedHour: 1, bedMinute: 0, wakeHour: 7, wakeMinute: 30,
      );
      expect(t.start, DateTime(2026, 10, 31, 1, 0));
      expect(t.end, DateTime(2026, 10, 31, 7, 30));
    });

    test('3. 同じ時刻（7:00 → 7:00）は起床が翌日（24 時間）', () {
      final t = SleepRecordValidation.resolveTimes(
        bedDate: DateTime(2026, 10, 30),
        bedHour: 7, bedMinute: 0, wakeHour: 7, wakeMinute: 0,
      );
      expect(t.end, DateTime(2026, 10, 31, 7, 0));
      expect(t.end.difference(t.start), const Duration(hours: 24));
    });

    test('4. 月末をまたぐ（10/31 22:00 → 11/1 6:00）', () {
      final t = SleepRecordValidation.resolveTimes(
        bedDate: DateTime(2026, 10, 31),
        bedHour: 22, bedMinute: 0, wakeHour: 6, wakeMinute: 0,
      );
      expect(t.end, DateTime(2026, 11, 1, 6, 0));
    });
  });

  group('長さ・未来・30 日', () {
    test('5. 10 分ちょうどは tooShort', () {
      final start = DateTime(2026, 11, 1, 9, 0);
      expect(
        SleepRecordValidation.validate(
          start: start, end: start.add(const Duration(minutes: 10)), now: now, existingRecords: const [],
        ),
        ManualSleepError.tooShort,
      );
    });

    test('6. 11 分は通る', () {
      final start = DateTime(2026, 11, 1, 9, 0);
      expect(
        SleepRecordValidation.validate(
          start: start, end: start.add(const Duration(minutes: 11)), now: now, existingRecords: const [],
        ),
        isNull,
      );
    });

    test('7. 起床が今より 1 分後は future', () {
      expect(
        SleepRecordValidation.validate(
          start: DateTime(2026, 11, 1, 4, 0), end: DateTime(2026, 11, 1, 12, 1), now: now, existingRecords: const [],
        ),
        ManualSleepError.future,
      );
    });

    test('8. 起床がちょうど今は通る', () {
      expect(
        SleepRecordValidation.validate(
          start: DateTime(2026, 11, 1, 4, 0), end: now, now: now, existingRecords: const [],
        ),
        isNull,
      );
    });

    test('9. 30 日前は選べる・31 日前と明日は選べない', () {
      expect(SleepRecordValidation.earliestBedDate(now), DateTime(2026, 10, 2));
      expect(SleepRecordValidation.isBedDateInRange(DateTime(2026, 10, 2), now), isTrue);
      expect(SleepRecordValidation.isBedDateInRange(DateTime(2026, 10, 1), now), isFalse);
      expect(SleepRecordValidation.isBedDateInRange(DateTime(2026, 11, 1, 23, 59), now), isTrue);
      expect(SleepRecordValidation.isBedDateInRange(DateTime(2026, 11, 2), now), isFalse);
    });
  });

  group('重なり', () {
    // 既存：10/31 23:00 → 11/1 7:00
    final existing = [record('a', DateTime(2026, 10, 31, 23, 0), DateTime(2026, 11, 1, 7, 0))];

    ManualSleepError? check(DateTime start, DateTime end, {List<SleepRecord>? records, String? sleepingId, DateTime? sleepingStart}) {
      return SleepRecordValidation.validate(
        start: start,
        end: end,
        now: now,
        existingRecords: records ?? existing,
        sleepingRecordId: sleepingId,
        sleepingStartTime: sleepingStart,
      );
    }

    test('10. 前側で重なる（22:00 → 0:00）', () {
      expect(check(DateTime(2026, 10, 31, 22, 0), DateTime(2026, 11, 1, 0, 0)), ManualSleepError.overlap);
    });

    test('11. 後側で重なる（6:00 → 9:00）', () {
      expect(check(DateTime(2026, 11, 1, 6, 0), DateTime(2026, 11, 1, 9, 0)), ManualSleepError.overlap);
    });

    test('12. 中に含まれる（1:00 → 3:00）', () {
      expect(check(DateTime(2026, 11, 1, 1, 0), DateTime(2026, 11, 1, 3, 0)), ManualSleepError.overlap);
    });

    test('13. 既存を丸ごと含む（22:00 → 8:00）', () {
      expect(check(DateTime(2026, 10, 31, 22, 0), DateTime(2026, 11, 1, 8, 0)), ManualSleepError.overlap);
    });

    test('14. 端が同じ（既存の起床 7:00 ＝ 追加の入眠 7:00）は重ならない', () {
      expect(check(DateTime(2026, 11, 1, 7, 0), DateTime(2026, 11, 1, 9, 0)), isNull);
    });

    test('15. 端が同じ（追加の起床 23:00 ＝ 既存の入眠 23:00）は重ならない', () {
      expect(check(DateTime(2026, 10, 31, 20, 0), DateTime(2026, 10, 31, 23, 0)), isNull);
    });

    test('16. 睡眠中の記録は「開始〜今」として重なる（仮の終了 翌日 7:00 は使わない）', () {
      // 睡眠中：11/1 10:00 開始（DB 上は 11/2 7:00 終了）。今は 12:00
      final sleeping = record('s', DateTime(2026, 11, 1, 10, 0), DateTime(2026, 11, 2, 7, 0));
      expect(
        check(DateTime(2026, 11, 1, 9, 0), DateTime(2026, 11, 1, 11, 0), records: [sleeping], sleepingId: 's'),
        ManualSleepError.overlap,
      );
    });

    test('17. 睡眠中の記録の開始より前で終わる追加は重ならない', () {
      final sleeping = record('s', DateTime(2026, 11, 1, 10, 0), DateTime(2026, 11, 2, 7, 0));
      expect(
        check(DateTime(2026, 11, 1, 8, 0), DateTime(2026, 11, 1, 10, 0), records: [sleeping], sleepingId: 's'),
        isNull,
      );
    });

    test('18. 睡眠中は開始時刻の一致でも判定する（ID がまだ復元されていないとき）', () {
      final start = DateTime(2026, 11, 1, 10, 0);
      final sleeping = record('s', start, DateTime(2026, 11, 2, 7, 0));
      final range = SleepRecordValidation.occupiedRange(sleeping, now: now, sleepingStartTime: start);
      expect(range.end, now);
    });

    test('19. 睡眠中でなければ DB の終了時刻をそのまま使う', () {
      final r = record('b', DateTime(2026, 11, 1, 10, 0), DateTime(2026, 11, 1, 11, 0));
      final range = SleepRecordValidation.occupiedRange(r, now: now);
      expect(range.end, DateTime(2026, 11, 1, 11, 0));
    });

    test('20. 終了が開始より前の既存の記録は終了を +1 日として判定する', () {
      // 修正画面で保存された形（10/30 23:00 → 10/30 7:00）
      final r = record('c', DateTime(2026, 10, 30, 23, 0), DateTime(2026, 10, 30, 7, 0));
      expect(
        check(DateTime(2026, 10, 31, 6, 0), DateTime(2026, 10, 31, 9, 0), records: [r]),
        ManualSleepError.overlap,
      );
    });
  });

  // N107：長すぎる睡眠の上限と、修正のときの自分自身の除外
  group('20 時間の上限', () {
    test('25. 20 時間ちょうどは通る', () {
      final start = DateTime(2026, 10, 31, 15, 0);
      expect(
        SleepRecordValidation.validate(
          start: start, end: start.add(const Duration(hours: 20)), now: now, existingRecords: const [],
        ),
        isNull,
      );
    });

    test('26. 20 時間 1 分は tooLong', () {
      final start = DateTime(2026, 10, 31, 15, 0);
      expect(
        SleepRecordValidation.validate(
          start: start, end: start.add(const Duration(hours: 20, minutes: 1)), now: now, existingRecords: const [],
        ),
        ManualSleepError.tooLong,
      );
    });

    test('27. 追加の 7:00 → 7:00（24 時間）は tooLong', () {
      final t = SleepRecordValidation.resolveTimes(
        bedDate: DateTime(2026, 10, 30),
        bedHour: 7, bedMinute: 0, wakeHour: 7, wakeMinute: 0,
      );
      expect(
        SleepRecordValidation.validate(start: t.start, end: t.end, now: now, existingRecords: const []),
        ManualSleepError.tooLong,
      );
    });
  });

  group('修正のときの自分自身の除外', () {
    // 修正する記録：10/31 23:00 → 11/1 7:00
    final self = record('self', DateTime(2026, 10, 31, 23, 0), DateTime(2026, 11, 1, 7, 0));
    // ほかの記録：11/1 8:00 → 11/1 9:00
    final other = record('other', DateTime(2026, 11, 1, 8, 0), DateTime(2026, 11, 1, 9, 0));

    test('28. excludeRecordId を渡すと自分自身とは重ならない', () {
      expect(
        SleepRecordValidation.validate(
          start: DateTime(2026, 10, 31, 23, 30),
          end: DateTime(2026, 11, 1, 7, 30),
          now: now,
          existingRecords: [self, other],
          excludeRecordId: 'self',
        ),
        isNull,
      );
    });

    test('29. excludeRecordId を渡しても、ほかの記録との重なりは overlap', () {
      expect(
        SleepRecordValidation.validate(
          start: DateTime(2026, 10, 31, 23, 30),
          end: DateTime(2026, 11, 1, 8, 30),
          now: now,
          existingRecords: [self, other],
          excludeRecordId: 'self',
        ),
        ManualSleepError.overlap,
      );
    });
  });
}
