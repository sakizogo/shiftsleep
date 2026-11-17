import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/sleep_baseline.dart' show mainSleepMinAsleep;
import 'package:shiftsleep/services/sleep_record_kind.dart';

// N184：メイン睡眠・補助睡眠を記録 1 件ずつ長さで決める

/// テスト用の睡眠記録（入眠 start から length 寝た記録。unfinished なら記録中）
SleepRecord rec(
  String id,
  DateTime start, {
  Duration length = const Duration(hours: 8),
  bool unfinished = false,
  SleepRole role = SleepRole.primary,
}) {
  final end = start.add(length);
  return SleepRecord(
    id: id,
    userId: 'test_user',
    sleepDate: DateTime(start.year, start.month, start.day),
    sleepStartTime: start,
    sleepStartAuto: true,
    sleepEndTime: end,
    sleepEndAuto: false,
    wakeUpType: '',
    durationMinutes: unfinished ? 0 : length.inMinutes,
    lastModifiedAt: start,
    canEditUntil: end.add(const Duration(days: 2)),
    createdAt: start,
    updatedAt: start,
    sleepRole: role,
  );
}

DateTime t(int day, int hour, [int minute = 0]) => DateTime(2026, 11, day, hour, minute);

void main() {
  group('isMainSleepRecord / isNapSleepRecord', () {
    test('5 時間ちょうどはメイン、4 時間 59 分は補助', () {
      final five = rec('a', t(2, 23), length: const Duration(hours: 5));
      final under = rec('b', t(2, 23), length: const Duration(hours: 4, minutes: 59));
      expect(isMainSleepRecord(five), isTrue);
      expect(isNapSleepRecord(five), isFalse);
      expect(isMainSleepRecord(under), isFalse);
      expect(isNapSleepRecord(under), isTrue);
    });

    test('記録中（durationMinutes == 0）はどちらでもない', () {
      final recording = rec('a', t(2, 23), length: const Duration(hours: 8), unfinished: true);
      expect(isUnfinishedSleepRecord(recording), isTrue);
      expect(isMainSleepRecord(recording), isFalse);
      expect(isNapSleepRecord(recording), isFalse);
    });

    test('保存された SleepRole は見ない（supplementary でも 8 時間ならメイン）', () {
      final record = rec('a', t(2, 23), role: SleepRole.supplementary);
      expect(isMainSleepRecord(record), isTrue);
    });

    test('終わりが始まりより前なら +1 日として長さを出す', () {
      final base = rec('a', t(2, 23));
      final wrapped = base.copyWith(sleepEndTime: t(2, 7)); // 23:00〜同じ日付の 7:00
      expect(sleepRecordLength(wrapped), const Duration(hours: 8));
      expect(sleepRecordEnd(wrapped), t(3, 7));
      expect(isMainSleepRecord(wrapped), isTrue);
    });
  });

  group('recentSleepBreakdown（直近 24 時間）', () {
    final now = t(10, 12);

    test('メイン 1 件と昼寝 2 件：合計はメイン＋補助', () {
      final records = [
        rec('main', t(9, 23), length: const Duration(hours: 7)), // 終わり 10日 6:00
        rec('nap1', t(9, 14), length: const Duration(minutes: 30)),
        rec('nap2', t(10, 10), length: const Duration(hours: 1, minutes: 15)),
      ];
      final b = recentSleepBreakdown(records, now);
      expect(b.main, const Duration(hours: 7));
      expect(b.naps, const Duration(hours: 1, minutes: 45));
      expect(b.total, const Duration(hours: 8, minutes: 45));
    });

    test('メインが 2 件なら足す', () {
      final records = [
        rec('m1', t(9, 13), length: const Duration(hours: 5)), // 終わり 9日 18:00
        rec('m2', t(10, 0), length: const Duration(hours: 6)), // 終わり 10日 6:00
      ];
      final b = recentSleepBreakdown(records, now);
      expect(b.main, const Duration(hours: 11));
      expect(b.total, const Duration(hours: 11));
    });

    test('なにもなければメインは null・補助と合計は 0', () {
      final b = recentSleepBreakdown(const [], now);
      expect(b.main, isNull);
      expect(b.naps, Duration.zero);
      expect(b.total, Duration.zero);
    });

    test('終わりがちょうど 24 時間前は入る、それより前と今より後は入らない', () {
      final records = [
        rec('edge', t(9, 4), length: const Duration(hours: 8)), // 終わり 9日 12:00（ちょうど）
        rec('old', t(9, 3, 59), length: const Duration(hours: 8)), // 終わり 9日 11:59
        rec('future', t(10, 11), length: const Duration(hours: 2)), // 終わり 10日 13:00
      ];
      final b = recentSleepBreakdown(records, now);
      expect(b.main, const Duration(hours: 8));
      expect(b.naps, Duration.zero);
    });

    test('記録中の記録は入れない', () {
      final records = [
        rec('recording', t(9, 23), length: const Duration(hours: 8), unfinished: true),
        rec('nap', t(10, 9), length: const Duration(hours: 1)),
      ];
      final b = recentSleepBreakdown(records, now);
      expect(b.main, isNull);
      expect(b.naps, const Duration(hours: 1));
      expect(b.total, const Duration(hours: 1));
    });
  });

  test('formatSleepDuration（N199：分は 2 桁）', () {
    expect(formatSleepDuration(const Duration(hours: 7, minutes: 5)), '7h 05m');
    expect(formatSleepDuration(const Duration(hours: 7)), '7h 00m');
    expect(formatSleepDuration(const Duration(hours: 7, minutes: 30)), '7h 30m');
    expect(formatSleepDuration(Duration.zero), '0h 00m');
  });

  test('N184 2/2：formatSleepDuration はマイナスに対応（-2 分が 0h 58m にならない）', () {
    expect(formatSleepDuration(const Duration(minutes: -2)), '-0h 02m');
    expect(formatSleepDuration(const Duration(hours: -1, minutes: -5)), '-1h 05m');
  });

  test('N184 2/2：formatSignedSleepDuration', () {
    expect(formatSignedSleepDuration(const Duration(minutes: -2)), '-0h 02m');
    expect(formatSignedSleepDuration(Duration.zero), '+0h 00m');
    expect(formatSignedSleepDuration(const Duration(hours: 2, minutes: 30)), '+2h 30m');
  });

  group('N184 2/2：dailySleepTotals（起床の日付で 1 日ごと）', () {
    final first = DateTime(2026, 11, 1);
    final last = DateTime(2026, 11, 30);

    test('夜勤明けの朝寝・0:00 をまたぐ睡眠・0:00 後の入眠・昼寝は、どれも起きた日に入る', () {
      final records = [
        rec('daySleep', t(10, 9), length: const Duration(hours: 6)), // 9:00〜15:00
        rec('overnight', t(9, 23), length: const Duration(hours: 8)), // 11/9 23:00〜11/10 7:00
        rec('afterMidnight', t(10, 0, 30), length: const Duration(hours: 7, minutes: 30)), // 0:30〜8:00
        rec('nap', t(10, 13), length: const Duration(minutes: 30)),
      ];
      final totals = dailySleepTotals(records, firstDay: first, lastDay: last);
      expect(totals.keys, [DateTime(2026, 11, 10)]);
      expect(totals[DateTime(2026, 11, 10)], const Duration(hours: 22));
    });

    test('19:00〜0:10 は次の日に入る', () {
      final totals = dailySleepTotals(
        [rec('a', t(9, 19), length: const Duration(hours: 5, minutes: 10))],
        firstDay: first,
        lastDay: last,
      );
      expect(totals.keys, [DateTime(2026, 11, 10)]);
    });

    test('終わりが始まりより前の記録は +1 日にして起床の日付を出す', () {
      final wrapped = rec('a', t(9, 23)).copyWith(sleepEndTime: t(9, 7));
      expect(sleepRecordWakeDay(wrapped), DateTime(2026, 11, 10));
    });

    test('記録中は入れない・記録のない日は入らない・期間の外も入らない', () {
      final records = [
        rec('recording', t(11, 23), unfinished: true),
        rec('in', t(12, 23)), // 起床 11/13
        rec('before', DateTime(2026, 10, 31, 23)), // 起床 11/1
        rec('out', t(30, 23)), // 起床 12/1
      ];
      final totals = dailySleepTotals(records, firstDay: DateTime(2026, 11, 2), lastDay: last);
      expect(totals.keys, [DateTime(2026, 11, 13)]);
    });
  });

  group('N184 2/2：直近 4 週間・今月・平均', () {
    test('直近 4 週間は today − 27 〜 today（両端を含む）', () {
      final now = t(30, 12);
      final records = [
        rec('first', t(2, 23)), // 起床 11/3 = today − 27
        rec('tooOld', t(1, 23)), // 起床 11/2 = today − 28
        rec('today', t(29, 23)), // 起床 11/30
      ];
      final totals = recentDailySleepTotals(records, now);
      expect(totals.keys.toSet(), {DateTime(2026, 11, 3), DateTime(2026, 11, 30)});
    });

    test('今月は暦の 1 日〜今日（前の月に起きた分は入らない）', () {
      final now = t(3, 12);
      final records = [
        rec('lastMonth', DateTime(2026, 10, 30, 23)), // 起床 10/31
        rec('first', DateTime(2026, 10, 31, 23)), // 起床 11/1
        rec('second', t(1, 23)), // 起床 11/2
      ];
      final totals = thisMonthDailySleepTotals(records, now);
      expect(totals.keys.toSet(), {DateTime(2026, 11, 1), DateTime(2026, 11, 2)});
    });

    test('平均は 1 日あたりの合計の平均（昼寝を含む）。日がなければ null', () {
      final totals = dailySleepTotals(
        [
          rec('m1', t(9, 23), length: const Duration(hours: 5)), // 11/10
          rec('nap1', t(10, 13), length: const Duration(hours: 1)), // 11/10
          rec('m2', t(10, 23), length: const Duration(hours: 8)), // 11/11
        ],
        firstDay: DateTime(2026, 11, 1),
        lastDay: DateTime(2026, 11, 30),
      );
      expect(averageDailySleep(totals), const Duration(hours: 7));
      expect(averageDailySleep(const {}), isNull);
    });
  });

  group('N110：sleepDurationRating（補助／不足／良好／長すぎ）', () {
    Duration hm(int h, [int m = 0]) => Duration(hours: h, minutes: m);

    test('境目：4h59m 補助・5h00m 不足・5h59m 不足・6h00m 良好・20h00m 良好・20h01m 長すぎ', () {
      expect(sleepDurationRating(hm(4, 59)), SleepDurationRating.supplementary);
      expect(sleepDurationRating(hm(5)), SleepDurationRating.short);
      expect(sleepDurationRating(hm(5, 59)), SleepDurationRating.short);
      expect(sleepDurationRating(hm(6)), SleepDurationRating.good);
      expect(sleepDurationRating(hm(20)), SleepDurationRating.good);
      expect(sleepDurationRating(hm(20, 1)), SleepDurationRating.tooLong);
    });

    test('5h の境目はメイン睡眠と同じ（isMainSleepRecord とそろう）', () {
      expect(sleepDurationRating(mainSleepMinAsleep), isNot(SleepDurationRating.supplementary));
      expect(
        sleepDurationRating(mainSleepMinAsleep - const Duration(minutes: 1)),
        SleepDurationRating.supplementary,
      );
    });

    test('20h ちょうどの 59 秒超は保存のチェックと同じく長すぎにしない（分で比べる）', () {
      expect(sleepDurationRating(hm(20) + const Duration(seconds: 59)), SleepDurationRating.good);
    });

    test('札の文字：編集画面は 4 つとも出す、一覧は不足・長すぎだけ', () {
      expect(SleepDurationRating.supplementary.editLabel, '補助（仮眠など）');
      expect(SleepDurationRating.short.editLabel, '不足');
      expect(SleepDurationRating.good.editLabel, '良好');
      expect(SleepDurationRating.tooLong.editLabel, '長すぎ（保存できません）');
      expect(SleepDurationRating.supplementary.listLabel, isNull);
      expect(SleepDurationRating.short.listLabel, '不足');
      expect(SleepDurationRating.good.listLabel, isNull);
      expect(SleepDurationRating.tooLong.listLabel, '長すぎ');
    });
  });

  test('一覧の日付：今年は年を省く・去年以前と来年は年つき・曜日つき', () {
    final now = DateTime(2026, 11, 17, 9);
    expect(formatSleepRecordListDate(DateTime(2026, 11, 11), now), '11月11日（水）');
    expect(formatSleepRecordListDate(DateTime(2026, 1, 1), now), '1月1日（木）');
    expect(formatSleepRecordListDate(DateTime(2025, 11, 11), now), '2025年11月11日（火）');
    expect(formatSleepRecordListDate(DateTime(2025, 12, 31), DateTime(2026, 1, 1)), '2025年12月31日（水）');
    expect(formatSleepRecordListDate(DateTime(2027, 1, 3), now), '2027年1月3日（日）');
  });

  test('N112：wakeUpTypeLabel（manual は手入力、空や知らない値は null）', () {
    expect(wakeUpTypeLabel('manual'), '手入力');
    expect(wakeUpTypeLabel(''), isNull);
    expect(wakeUpTypeLabel('alarm'), isNull);
  });
}
