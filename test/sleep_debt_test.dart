import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/sleep_advisory_service.dart';
import 'package:shiftsleep/services/sleep_debt.dart';

// N198：睡眠負債を 1 日平均の不足で判定する（余りは 1 日 +1 時間まで・記録のある日が 7 日以上）

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

final now = t(20, 12);

/// 11/10 から 1 日 1 件ずつ、0:00 に寝た記録（起床の日付も同じ日）
List<SleepRecord> daily(List<Duration> lengths) => [
      for (var i = 0; i < lengths.length; i++) rec('d$i', t(10 + i, 0), length: lengths[i]),
    ];

List<SleepRecord> sevenDays(Duration length) => daily(List.filled(7, length));

SleepDebtSummary? debt(List<SleepRecord> records) => recentSleepDebt(records, now);

Duration h(int hours, [int minutes = 0]) => Duration(hours: hours, minutes: minutes);

void main() {
  group('recentSleepDebt：1 日平均の差と上限', () {
    test('8h × 7 日 → +1h／日（上限ちょうどは差し引く。※は出さない）', () {
      final d = debt(sevenDays(h(8)))!;
      expect(d.days, 7);
      expect(d.dailyBalance, h(1));
      expect(d.rawTotal, h(7));
      expect(d.cappedTotal, h(7));
      expect(d.level, SleepDebtLevel.enough);
      expect(d.showsSurplusCapNote, isFalse);
    });

    test('9h × 7 日 → 余りは 1 日 +1h まで（+1h／日。※を出す）', () {
      final d = debt(sevenDays(h(9)))!;
      expect(d.rawTotal, h(14));
      expect(d.cappedTotal, h(7));
      expect(d.dailyBalance, h(1));
      expect(d.rawDailyBalance, h(2));
      expect(d.showsSurplusCapNote, isTrue);
    });

    test('10h × 1 日 ＋ 6h × 6 日 → 上限なしなら少し不足、上限ありなら改善推奨（※を出す）', () {
      final d = debt(daily([h(10), ...List.filled(6, h(6))]))!;
      expect(d.rawTotal, h(-3));
      expect(d.cappedTotal, h(-5));
      expect(formatDailySleepDebt(d.dailyBalance), '-0h 42m／日');
      expect(formatDailySleepDebt(d.rawDailyBalance), '-0h 25m／日');
      expect(d.level, SleepDebtLevel.improve);
      expect(d.showsSurplusCapNote, isTrue);
    });

    test('寝すぎた日がなければ ※ は出さない（6h × 7 日）', () {
      expect(debt(sevenDays(h(6)))!.showsSurplusCapNote, isFalse);
    });

    test('昼寝だけの日も数える（1h の日 ＋ 7h × 6 日 → -51m／日・改善推奨）', () {
      final d = debt(daily([h(1), ...List.filled(6, h(7))]))!;
      expect(d.cappedTotal, h(-6));
      expect(formatDailySleepDebt(d.dailyBalance), '-0h 51m／日');
      expect(d.level, SleepDebtLevel.improve);
    });

    test('1 日に 2 件あれば足してから 7h を引く（3h30m ＋ 3h30m の日は 0）', () {
      final records = [
        ...daily(List.filled(6, h(7))),
        rec('a', t(16, 0), length: h(3, 30)),
        rec('b', t(16, 12), length: h(3, 30)),
      ];
      final d = debt(records)!;
      expect(d.days, 7);
      expect(d.dailyBalance, Duration.zero);
      expect(formatDailySleepDebt(d.dailyBalance), '+0h 00m／日');
    });
  });

  group('recentSleepDebt：計算できないとき', () {
    test('記録のある日が 6 日なら null、7 日なら値を出す', () {
      expect(debt(daily(List.filled(6, h(6)))), isNull);
      expect(debt(sevenDays(h(6))), isNotNull);
    });

    test('記録がなければ null', () {
      expect(debt(const []), isNull);
    });

    test('記録中の日は数えない（6 日 ＋ 記録中 → null）', () {
      final records = [
        ...daily(List.filled(6, h(7))),
        rec('recording', t(19, 23)).copyWith(durationMinutes: 0),
      ];
      expect(debt(records), isNull);
    });

    test('直近 4 週間（today − 27 〜 today）の外の日は数えない', () {
      final records = [
        ...daily(List.filled(6, h(7))),
        rec('out', DateTime(2026, 10, 23, 0), length: h(7)), // today − 28
      ];
      expect(debt(records), isNull);
      final inside = [
        ...daily(List.filled(6, h(7))),
        rec('in', DateTime(2026, 10, 24, 0), length: h(7)), // today − 27
      ];
      expect(debt(inside)!.days, 7);
    });
  });

  group('評価の段階（1 日平均の不足）', () {
    test('30 分ちょうどは改善推奨、29 分は少し不足', () {
      expect(debt(sevenDays(h(6, 30)))!.level, SleepDebtLevel.improve);
      expect(debt(sevenDays(h(6, 31)))!.level, SleepDebtLevel.slight);
    });

    test('60 分ちょうどは要注意、59 分は改善推奨', () {
      expect(debt(sevenDays(h(6)))!.level, SleepDebtLevel.alert);
      expect(debt(sevenDays(h(6, 1)))!.level, SleepDebtLevel.improve);
    });

    test('不足がなければ十分', () {
      expect(debt(sevenDays(h(7)))!.level, SleepDebtLevel.enough);
    });

    test('評価の文言', () {
      expect(sleepDebtEvaluationText(SleepDebtLevel.notJudgeable), '判定できません');
      expect(sleepDebtEvaluationText(SleepDebtLevel.enough), '十分睡眠が取れています');
      expect(sleepDebtEvaluationText(SleepDebtLevel.slight), '少し不足（30分未満）');
      expect(sleepDebtEvaluationText(SleepDebtLevel.improve), '改善推奨（1日平均30分以上の不足）');
      expect(sleepDebtEvaluationText(SleepDebtLevel.alert), '要注意（1日平均60分以上の不足）');
    });

    test('大きい数字の表示（N199：-1h 05m／日・+0h 40m／日・-2h 24m／日）', () {
      expect(formatDailySleepDebt(const Duration(minutes: -65)), '-1h 05m／日');
      expect(formatDailySleepDebt(const Duration(minutes: -144)), '-2h 24m／日');
      expect(formatDailySleepDebt(const Duration(minutes: 40)), '+0h 40m／日');
    });

    test('国の目安：1 日平均 6h ちょうどは出さない、5h59m は出す', () {
      expect(debt(sevenDays(h(6)))!.belowNationalGuide, isFalse);
      expect(debt(sevenDays(h(5, 59)))!.belowNationalGuide, isTrue);
    });
  });

  group('睡眠負債のアドバイス', () {
    SleepAdvice? debtAdvice(SleepDebtSummary? summary) {
      final list = SleepAdvisoryService.generateAdvice(
        sjl: null,
        sri: null,
        sleepDebt: summary,
        last7DaysRecords: const [],
      ).where((a) => a.category == 'debt');
      return list.isEmpty ? null : list.single;
    }

    test('要注意：priority 1・不足の時間を文に入れる・actionTip は寝方を決めつけない文', () {
      final advice = debtAdvice(debt(sevenDays(h(6))))!;
      expect(advice.priority, 1);
      expect(advice.description, contains('平均 1h 00m 少なく'));
      expect(advice.description, isNot(contains('国の睡眠ガイド')));  // 6h ちょうどは出さない
      expect(
        advice.actionTip,
        '夜勤の前に仮眠を取る、勤務明けにまとまって眠れる時間を作るなど、勤務に合わせて眠る時間を確保してみてください',
      );
    });

    test('要注意で 1 日平均が 6h 未満なら国の目安の一言を入れる', () {
      final advice = debtAdvice(debt(sevenDays(h(5, 59))))!;
      expect(
        advice.description,
        endsWith('直近4週間の1日平均は5h 59mで、国の睡眠ガイドが目安とする「6時間以上」より短めです。'
            '必要な睡眠時間には個人差があります。眠りたくても眠れない日が続くときは、無理をせず休める時間を少しずつ確保してみてください。'),
      );
    });

    test('改善推奨は priority 1、少し不足・十分は priority 3 で actionTip なし', () {
      expect(debtAdvice(debt(sevenDays(h(6, 30))))!.priority, 1);
      final slight = debtAdvice(debt(sevenDays(h(6, 31))))!;
      expect(slight.priority, 3);
      expect(slight.actionTip, isNull);
      final enough = debtAdvice(debt(sevenDays(h(7))))!;
      expect(enough.priority, 3);
      expect(enough.actionTip, isNull);
    });

    test('シフト勤務に合わない言い方（週末・勤務中の昼寝）を使わない', () {
      for (final length in [h(5), h(6, 30), h(6, 50), h(8)]) {
        final advice = debtAdvice(debt(sevenDays(length)))!;
        final text = '${advice.title}${advice.description}${advice.actionTip ?? ''}';
        expect(text, isNot(contains('週末')));
        expect(text, isNot(contains('勤務中')));
        expect(text, isNot(contains('解消')));
      }
    });

    test('計算できなければ出さない', () {
      expect(debtAdvice(null), isNull);
    });

    test('無料版でも要注意は出る（priority 1）', () {
      final all = SleepAdvisoryService.generateAdvice(
        sjl: null,
        sri: null,
        sleepDebt: debt(sevenDays(h(6))),
        last7DaysRecords: const [],
      );
      final shown = SleepAdvisoryService.filterAdviceByPlan(all, isPremiumUser: false);
      expect(shown.single.title, '睡眠不足が続いています');
    });
  });
}
