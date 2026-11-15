import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/sjl_sri_calculator.dart';
import 'package:shiftsleep/services/sleep_advisory_service.dart';

// N183：SJL の中点を円周平均にし、差を 0:00 をまたいで短いほうにする
// 2026-11-02 は月曜（11/2〜11/6 が平日、11/7・11/8 が土日）。平日・休日は入眠の曜日で分ける

/// テスト用の睡眠記録（入眠 start から length 寝た記録）
SleepRecord rec(String id, DateTime start, {Duration length = const Duration(hours: 8)}) {
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
    durationMinutes: length.inMinutes,
    lastModifiedAt: start,
    canEditUntil: end.add(const Duration(days: 2)),
    createdAt: start,
    updatedAt: start,
  );
}

/// 2026 年 11 月の日時
DateTime t(int day, int hour, [int minute = 0]) => DateTime(2026, 11, day, hour, minute);

void main() {
  group('calculateSJL', () {
    test('調査の例 A：平日の中点 23:30・0:30・23:30・0:30・0:00、休日 0:00・1:00 → 0.5h', () {
      // 8 時間の睡眠なので、中点は入眠の 4 時間後
      final records = [
        rec('mon', t(2, 19, 30)), // 中点 23:30
        rec('tue', t(3, 20, 30)), // 中点 0:30
        rec('wed', t(4, 19, 30)), // 中点 23:30
        rec('thu', t(5, 20, 30)), // 中点 0:30
        rec('fri', t(6, 20, 0)), // 中点 0:00
        rec('sat', t(7, 20, 0)), // 中点 0:00
        rec('sun', t(8, 21, 0)), // 中点 1:00
      ];
      expect(SJLSRICalculator.calculateSJL(records), 0.5);
    });

    test('調査の例 B：平日の中点 23:30〜23:55（約 23:45）、休日 0:30・1:00 → 1.0h（23h にならない）', () {
      final records = [
        rec('mon', t(2, 19, 30)), // 中点 23:30
        rec('tue', t(3, 19, 40)), // 中点 23:40
        rec('wed', t(4, 19, 50)), // 中点 23:50
        rec('thu', t(5, 19, 50)), // 中点 23:50
        rec('fri', t(6, 19, 55)), // 中点 23:55
        rec('sat', t(7, 20, 30)), // 中点 0:30
        rec('sun', t(8, 21, 0)), // 中点 1:00
      ];
      expect(SJLSRICalculator.calculateSJL(records), 1.0);
    });

    test('0:00 をまたがない例：平日の中点 3:00、休日 4:00 → 1.0h', () {
      final records = [
        for (var day = 2; day <= 6; day++) rec('d$day', t(day, 23, 0)), // 中点 3:00
        rec('sat', t(7, 23, 30), length: const Duration(hours: 9)), // 中点 4:00
        rec('sun', t(8, 23, 30), length: const Duration(hours: 9)), // 中点 4:00
      ];
      expect(SJLSRICalculator.calculateSJL(records), 1.0);
    });

    test('休日が 0 件なら null', () {
      final records = [
        for (var day = 2; day <= 6; day++) rec('d$day', t(day, 23, 0)),
      ];
      expect(SJLSRICalculator.calculateSJL(records), isNull);
    });

    test('平日が 0 件なら null', () {
      final records = [
        rec('sat', t(7, 23, 0)),
        rec('sun', t(8, 23, 0)),
      ];
      expect(SJLSRICalculator.calculateSJL(records), isNull);
    });

    test('記録がなければ null', () {
      expect(SJLSRICalculator.calculateSJL(const []), isNull);
    });

    test('平日の中点がばらばら（0:00・6:00・12:00・18:00。R が 0.1 未満）なら null', () {
      final records = [
        rec('mon', t(2, 20, 0)), // 中点 0:00
        rec('tue', t(3, 2, 0)), // 中点 6:00
        rec('wed', t(4, 8, 0)), // 中点 12:00
        rec('thu', t(5, 14, 0)), // 中点 18:00
        rec('sat', t(7, 23, 0)),
        rec('sun', t(8, 23, 0)),
      ];
      expect(SJLSRICalculator.calculateSJL(records), isNull);
    });

    // N184：メインは長さで決める（昼寝・記録中は入れない）
    final exampleA = [
      rec('mon', t(2, 19, 30)),
      rec('tue', t(3, 20, 30)),
      rec('wed', t(4, 19, 30)),
      rec('thu', t(5, 20, 30)),
      rec('fri', t(6, 20, 0)),
      rec('sat', t(7, 20, 0)),
      rec('sun', t(8, 21, 0)),
    ];

    test('N184：昼寝（2 時間）を足しても SJL は変わらない', () {
      final records = [
        ...exampleA,
        rec('nap-sat', t(7, 13, 0), length: const Duration(hours: 2)),
        rec('nap-wed', t(4, 14, 0), length: const Duration(hours: 2)),
      ];
      expect(SJLSRICalculator.calculateSJL(records), 0.5);
    });

    test('N184：記録中の記録は SJL に入れない', () {
      final recording = rec('rec-sun', t(8, 3, 0), length: const Duration(hours: 28))
          .copyWith(durationMinutes: 0);
      expect(SJLSRICalculator.calculateSJL([...exampleA, recording]), 0.5);
    });
  });

  group('calculateSRI（N184）', () {
    final mains = [
      for (var day = 2; day <= 5; day++) rec('d$day', t(day, 23, 0)),
    ];

    test('毎日 23:00〜7:00 なら 100', () {
      expect(SJLSRICalculator.calculateSRI(mains), 100.0);
    });

    test('昼寝や記録中の記録をはさんでも変わらない', () {
      final records = [
        ...mains,
        rec('nap', t(3, 13, 0), length: const Duration(hours: 1)),
        rec('recording', t(5, 15, 0), length: const Duration(hours: 16)).copyWith(durationMinutes: 0),
      ];
      expect(SJLSRICalculator.calculateSRI(records), 100.0);
    });
  });

  group('circularMinuteDistance', () {
    test('0:00 をまたぐときは短いほう', () {
      expect(SJLSRICalculator.circularMinuteDistance(23 * 60 + 30, 30), 60);
      expect(SJLSRICalculator.circularMinuteDistance(30, 23 * 60 + 30), 60);
    });

    test('またがないとき・同じとき・ちょうど 12 時間', () {
      expect(SJLSRICalculator.circularMinuteDistance(3 * 60, 4 * 60), 60);
      expect(SJLSRICalculator.circularMinuteDistance(600, 600), 0);
      expect(SJLSRICalculator.circularMinuteDistance(0, 12 * 60), 12 * 60);
    });
  });

  group('generateAdvice の SJL', () {
    List<SleepAdvice> sjlAdvice(double? sjl) => SleepAdvisoryService.generateAdvice(
          sjl: sjl,
          sri: 90,
          sleepDebt: Duration.zero,
          last7DaysRecords: const [],
        ).where((a) => a.category == 'sjl').toList();

    test('null なら SJL のアドバイスを出さない', () {
      expect(sjlAdvice(null), isEmpty);
    });

    test('値があれば今までどおり（2 以上・1 以上は priority 1、1 未満は priority 3）', () {
      expect(sjlAdvice(2.0).single.priority, 1);
      expect(sjlAdvice(1.0).single.priority, 1);
      expect(sjlAdvice(0.5).single.priority, 3);
    });
  });

  group('分割睡眠のアドバイス（N184）', () {
    const title = '仮眠を上手に取り入れています';
    final mains = [
      for (var day = 2; day <= 6; day++) rec('m$day', t(day, 23, 0)),
    ];
    SleepAdvice? napAdvice(List<SleepRecord> records, {bool premium = true}) {
      final list = SleepAdvisoryService.generateAdvice(
        sjl: 0.5,
        sri: 90,
        sleepDebt: Duration.zero,
        last7DaysRecords: records,
        isPremiumUser: premium,
      ).where((a) => a.title == title);
      return list.isEmpty ? null : list.single;
    }

    SleepRecord nap(String id, int day, int hour) =>
        rec(id, t(day, hour), length: const Duration(minutes: 30));

    test('昼寝の日が 3 日あれば出る（日数を文に入れる）', () {
      final advice = napAdvice([...mains, nap('n1', 2, 13), nap('n2', 3, 13), nap('n3', 4, 13)]);
      expect(advice, isNotNull);
      expect(advice!.isPremiumOnly, isTrue);
      expect(advice.priority, 2);
      expect(advice.description, contains('7日間のうち 3日'));
    });

    test('2 日なら出ない（1 日に 2 回でも 1 日と数える）', () {
      expect(napAdvice([...mains, nap('n1', 2, 13), nap('n2', 2, 17), nap('n3', 3, 13)]), isNull);
    });

    test('記録中の記録は昼寝に数えない', () {
      final recording = nap('n3', 4, 13).copyWith(durationMinutes: 0);
      expect(napAdvice([...mains, nap('n1', 2, 13), nap('n2', 3, 13), recording]), isNull);
    });

    test('無料版では出ない', () {
      expect(
        napAdvice([...mains, nap('n1', 2, 13), nap('n2', 3, 13), nap('n3', 4, 13)], premium: false),
        isNull,
      );
    });
  });
}
