import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/sleep_record.dart';
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

  test('formatSleepDuration', () {
    expect(formatSleepDuration(const Duration(hours: 7, minutes: 5)), '7h 5m');
    expect(formatSleepDuration(Duration.zero), '0h 0m');
  });
}
