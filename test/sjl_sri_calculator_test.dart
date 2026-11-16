import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/sjl_sri_calculator.dart';
import 'package:shiftsleep/services/sleep_advisory_service.dart';
import 'package:shiftsleep/services/sleep_debt.dart';

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

/// N198：不足のない睡眠負債（7 日・1 日平均 7h）
const noDebt = SleepDebtSummary(days: 7, averageSleep: Duration(hours: 7), rawTotal: Duration.zero, cappedTotal: Duration.zero);

/// N198：1 日平均 2h 不足の睡眠負債（要注意）
const shortDebt = SleepDebtSummary(days: 7, averageSleep: Duration(hours: 5), rawTotal: Duration(hours: -14), cappedTotal: Duration(hours: -14));

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

  group('calculateSRI（N196 A：すべての睡眠で 24 時間ごとに比べる）', () {
    // now は 11/21 0:00。期間は 11/14 0:00〜11/21 0:00 で、11/14〜11/19 の各分を 24 時間後と比べる（最大 6 日分＝8640 分）
    final now = t(21, 0);
    double? sri(List<SleepRecord> records, {DateTime? recordingStart}) =>
        SJLSRICalculator.calculateSRI(records, now: now, recordingStart: recordingStart);
    Duration h(int hours) => Duration(hours: hours);
    List<SleepRecord> daily(Iterable<int> days, int hour, Duration length, String prefix) => [
          for (final day in days) rec('$prefix$day', t(day, hour), length: length),
        ];
    final allDays = [for (var d = 14; d <= 20; d++) d];

    test('毎日 0:00〜8:00 なら 100', () {
      expect(sri(daily(allDays, 0, h(8), 'm')), 100.0);
    });

    test('昼寝をする日としない日があれば下がる（3 日だけ 13〜14 時 → 約 91.7）', () {
      final records = [...daily(allDays, 0, h(8), 'm'), ...daily([15, 17, 19], 13, h(1), 'n')];
      // 合わないのは 6 組 × 60 分 = 360 分。200 × 8280 ÷ 8640 − 100
      expect(sri(records), closeTo(91.67, 0.01));
    });

    test('毎日同じ時刻に分けて寝る人（9〜13 時＋20〜23 時）は 100（メインがなくても出す）', () {
      final records = [...daily(allDays, 9, h(4), 'a'), ...daily(allDays, 20, h(3), 'b')];
      expect(sri(records), 100.0);
    });

    test('日勤と夜勤が入れ替わる人（0〜7 時 × 3 日 → 9〜16 時 × 3 日 → 0〜8 時）は約 59.7', () {
      final records = [
        ...daily([14, 15, 16], 0, h(7), 'd'),
        ...daily([17, 18, 19], 9, h(7), 'n'),
        ...daily([20], 0, h(8), 'o'),
      ];
      // 入れ替わる 2 組だけ一致が 10/24・9/24。(4 + 19/24) ÷ 6 × 200 − 100
      expect(sri(records), closeTo(59.72, 0.01));
    });

    test('0:00 をまたぐ睡眠（23:00〜7:00）も日時で比べる。記録中なら期間をその開始までにする', () {
      final records = [
        ...daily([13, 14, 15, 16, 17, 18, 19], 23, h(8), 'm'),
        rec('recording', t(20, 23)).copyWith(durationMinutes: 0),
      ];
      expect(sri(records, recordingStart: t(20, 23)), 100.0);
      // 記録中を考えないと、11/20 23:00〜24:00 を「起きていた」と数えて 60 分合わない
      expect(sri(records), closeTo(200 * 8580 / 8640 - 100, 0.0001));
    });

    test('重なった記録は 1 回だけ「寝ている」と数える', () {
      final records = [...daily(allDays, 0, h(8), 'm'), rec('dup', t(16, 2), length: h(2))];
      expect(sri(records), 100.0);
    });

    test('記録のない日が関わる組は比べない（押し忘れの日を「起きていた」と数えない）', () {
      final records = daily(allDays.where((d) => d != 17), 0, h(8), 'm');
      expect(sri(records), 100.0);
    });

    test('途中で終わった記録（記録中）は睡眠にも記録のある日にも数えない', () {
      final records = [
        ...daily(allDays.where((d) => d != 17), 0, h(8), 'm'),
        rec('broken', t(17, 0)).copyWith(durationMinutes: 0),
      ];
      expect(sri(records), 100.0);
    });

    test('比べた時間が 4 日分（5760 分）ちょうどなら出す、5759 分なら null', () {
      final records = daily(allDays.where((d) => d != 17), 0, h(8), 'm');
      // 11/17 がないので 11/16→17・11/17→18 の 2 組を比べず、4 組＝5760 分
      expect(sri(records), isNotNull);
      // 記録中の開始を 11/20 23:59 にすると 1 分減って 5759 分
      expect(sri(records, recordingStart: t(20, 23, 59)), isNull);
    });

    test('記録のない日が 2 日あって 2 組しか比べられなければ null', () {
      expect(sri(daily(allDays.where((d) => d != 17 && d != 19), 0, h(8), 'm')), isNull);
    });

    test('記録がない・記録中だけなら null', () {
      expect(sri(const []), isNull);
      expect(sri(daily(allDays, 0, h(8), 'r').map((r) => r.copyWith(durationMinutes: 0)).toList()), isNull);
    });

    test('記録中の開始が期間より前なら null', () {
      expect(sri(daily(allDays, 0, h(8), 'm'), recordingStart: t(13, 0)), isNull);
    });

    test('昼寝だけでも毎日同じ時刻なら 100', () {
      expect(sri(daily(allDays, 13, h(1), 'n')), 100.0);
    });

    test('定数：期間 7 日・4 日分（5760 分）', () {
      expect(SJLSRICalculator.sriWindow, const Duration(days: 7));
      expect(SJLSRICalculator.sriMinComparedMinutes, 5760);
    });
  });

  test('N196 A：SJL のメインの件数の下限は 5（minMainRecordsForSjl）', () {
    expect(SJLSRICalculator.minMainRecordsForSjl, 5);
  });

  group('calculateSleepDebt（N184 2/2：1 日ごと。N198：1 日平均・7 日以上）', () {
    final now = t(20, 12);
    SleepDebtSummary? debt(List<SleepRecord> records) =>
        SJLSRICalculator.calculateSleepDebt(records, now: now);
    List<SleepRecord> days(int count, Duration length) => [
          for (var i = 0; i < count; i++) rec('d$i', t(10 + i, 0), length: length),
        ];

    test('6h の日が 7 日なら -1h／日', () {
      final d = debt(days(7, const Duration(hours: 6)))!;
      expect(d.days, 7);
      expect(d.dailyBalance, const Duration(hours: -1));
    });

    test('メイン 5h と昼寝 2h の日は 0（昼寝も 1 日の合計に入る）', () {
      final d = debt([
        ...days(6, const Duration(hours: 7)),
        rec('main', t(16, 0), length: const Duration(hours: 5)),
        rec('nap', t(16, 13), length: const Duration(hours: 2)),
      ])!;
      expect(d.days, 7);
      expect(d.dailyBalance, Duration.zero);
    });

    test('N197：記録がなければ null', () {
      expect(debt(const []), isNull);
    });

    test('N197：4 週間の外にしか記録がなければ null', () {
      expect(debt([rec('out', DateTime(2026, 10, 23, 0))]), isNull);
    });

    test('N197：記録中だけなら null', () {
      expect(debt([rec('recording', t(19, 23)).copyWith(durationMinutes: 0)]), isNull);
    });

    test('N198：記録のある日が 6 日なら null（昼寝だけの日も 1 日に数える）', () {
      expect(debt(days(6, const Duration(hours: 1))), isNull);
      expect(debt(days(7, const Duration(hours: 1))), isNotNull);
    });
  });

  group('generateAdvice の SRI・睡眠負債（N197）', () {
    List<SleepAdvice> advice({double? sri, SleepDebtSummary? sleepDebt, List<SleepRecord> records = const [], bool premium = false}) =>
        SleepAdvisoryService.generateAdvice(
          sjl: null,
          sri: sri,
          sleepDebt: sleepDebt,
          last7DaysRecords: records,
          isPremiumUser: premium,
        );

    test('sri が null なら SRI のアドバイスを出さない', () {
      expect(advice(sri: null, sleepDebt: noDebt).where((a) => a.category == 'sri'), isEmpty);
      expect(advice(sri: 30, sleepDebt: noDebt).where((a) => a.category == 'sri').single.priority, 1);
    });

    test('sleepDebt が null なら睡眠負債のアドバイスを出さない', () {
      expect(advice(sri: 90, sleepDebt: null).where((a) => a.category == 'debt'), isEmpty);
      expect(
        advice(sri: 90, sleepDebt: shortDebt).where((a) => a.category == 'debt').single.priority,
        1,
      );
    });

    test('すべて null ならアドバイスは 0 件', () {
      expect(advice(), isEmpty);
    });

    test('分割睡眠のアドバイスは sleepDebt が null でも出る', () {
      final records = [
        for (var day = 2; day <= 4; day++) rec('n$day', t(day, 13, 0), length: const Duration(minutes: 30)),
      ];
      final titles = advice(records: records, premium: true).map((a) => a.title);
      expect(titles, contains('仮眠を上手に取り入れています'));
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

  group('generateAdvice の SRI（N196 A 2/2：シフト勤務に合う言い方）', () {
    SleepAdvice sriAdvice(double sri) => SleepAdvisoryService.generateAdvice(
          sjl: null,
          sri: sri,
          sleepDebt: null,
          last7DaysRecords: const [],
        ).where((a) => a.category == 'sri').single;

    test('40 未満：priority 1・actionTip あり', () {
      final advice = sriAdvice(39.9);
      expect(advice.title, '睡眠の時間帯が日ごとに大きく変わっています');
      expect(advice.priority, 1);
      expect(advice.actionTip, '同じ勤務が続く日は寝る時間帯をそろえ、勤務が切り替わる前後は、無理のない範囲で数時間ずつずらしてみてください');
    });

    test('40〜60：priority 2・actionTip あり（40 ちょうどを含む）', () {
      for (final sri in [40.0, 59.9]) {
        final advice = sriAdvice(sri);
        expect(advice.title, '睡眠の時間帯をもう少しそろえてみましょう');
        expect(advice.priority, 2);
        expect(advice.actionTip, '勤務が変わっても、毎回同じ数時間（例：4 時間ほど）は眠っている時間帯を作ってみてください');
      }
    });

    test('60〜80：priority 2・actionTip なし（60 ちょうどを含む）', () {
      for (final sri in [60.0, 79.9]) {
        final advice = sriAdvice(sri);
        expect(advice.title, '睡眠の時間帯はおおむねそろっています');
        expect(advice.priority, 2);
        expect(advice.actionTip, isNull);
      }
    });

    test('80 以上：priority 3・actionTip なし', () {
      final advice = sriAdvice(80.0);
      expect(advice.title, '睡眠の時間帯がよくそろっています');
      expect(advice.priority, 3);
      expect(advice.actionTip, isNull);
    });

    test('「毎日 ±○分」「毎日同じ時刻」「完璧」などの言い方をしない', () {
      for (final sri in [-20.0, 30.0, 50.0, 70.0, 90.0]) {
        final advice = sriAdvice(sri);
        final text = '${advice.title}${advice.description}${advice.actionTip ?? ''}';
        expect(text, isNot(contains('±')));
        expect(text, isNot(contains('毎日同じ時刻')));
        expect(text, isNot(contains('完璧')));
        expect(text, isNot(contains('素晴らしい')));
      }
    });
  });

  group('generateAdvice の SJL', () {
    List<SleepAdvice> sjlAdvice(double? sjl) => SleepAdvisoryService.generateAdvice(
          sjl: sjl,
          sri: 90,
          sleepDebt: noDebt,
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
        sleepDebt: noDebt,
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
