import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/screens/home_screen.dart';
import 'package:shiftsleep/services/medical_consult_dismiss_store.dart';
import 'package:shiftsleep/services/sleep_debt.dart';

// N202：2 週続けて睡眠負債が要注意なら、医師への相談をすすめる（閉じたら 14 日出さない）

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

/// today は 11/20。今週は 11/14〜11/20、前の週は 11/7〜11/13
final now = t(20, 12);

/// 指定した日に 0:00 から length 寝た記録（起床の日付も同じ日）
List<SleepRecord> onDays(Iterable<int> days, Duration length) => [
      for (final day in days) rec('d$day', t(day, 0), length: length),
    ];

Duration h(int hours, [int minutes = 0]) => Duration(hours: hours, minutes: minutes);

/// 明るさの差（WCAG のコントラスト比）
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('shouldSuggestMedicalConsult', () {
    bool suggest(List<SleepRecord> records) => shouldSuggestMedicalConsult(records, now);

    test('2 週とも要注意（6h × 7 日ずつ）なら true', () {
      expect(suggest([...onDays([for (var d = 7; d <= 20; d++) d], h(6))]), isTrue);
    });

    test('各週 4 日ちょうどでも判定する・3 日の週があれば false', () {
      expect(suggest(onDays([7, 8, 9, 10, 14, 15, 16, 17], h(6))), isTrue);
      expect(suggest(onDays([7, 8, 9, 14, 15, 16, 17], h(6))), isFalse);
      expect(suggest(onDays([7, 8, 9, 10, 14, 15, 16], h(6))), isFalse);
    });

    test('片方の週が改善推奨（不足 59 分）なら false', () {
      expect(
        suggest([
          ...onDays([for (var d = 7; d <= 13; d++) d], h(6, 1)),
          ...onDays([for (var d = 14; d <= 20; d++) d], h(6)),
        ]),
        isFalse,
      );
      expect(
        suggest([
          ...onDays([for (var d = 7; d <= 13; d++) d], h(6)),
          ...onDays([for (var d = 14; d <= 20; d++) d], h(6, 30)),
        ]),
        isFalse,
      );
    });

    test('今週だけ要注意で、前の週に記録がなければ false', () {
      expect(suggest(onDays([for (var d = 14; d <= 20; d++) d], h(6))), isFalse);
    });

    test('14 日より前（11/6）の記録は前の週に入らない', () {
      expect(suggest(onDays([3, 4, 5, 6, 14, 15, 16, 17], h(6))), isFalse);
    });

    test('寝すぎた日の余りは 1 日 +1h まで（N198 の計算を使う）', () {
      // 前の週：12h × 1 日 ＋ 5h × 3 日 → 上限ありで (+1 −6) ÷ 4 = −1h15m（要注意）、上限なしなら (+5 −6) ÷ 4 = −15m
      final records = [
        ...onDays([7], h(12)),
        ...onDays([8, 9, 10], h(5)),
        ...onDays([14, 15, 16, 17], h(6)),
      ];
      expect(suggest(records), isTrue);
    });

    test('定数：2 週・各週 4 日', () {
      expect(medicalConsultWeeks, 2);
      expect(medicalConsultMinDaysPerWeek, 4);
    });
  });

  group('isMedicalConsultSnoozed', () {
    final dismissedAt = t(1, 9);

    test('閉じていなければ出す', () {
      expect(isMedicalConsultSnoozed(null, now), isFalse);
    });

    test('閉じてから 14 日たっていなければ出さない・ちょうど 14 日で出す', () {
      expect(isMedicalConsultSnoozed(dismissedAt, t(15, 8, 59)), isTrue);
      expect(isMedicalConsultSnoozed(dismissedAt, t(15, 9)), isFalse);
    });
  });

  group('MedicalConsultDismissStore', () {
    test('保存した日時を読める', () async {
      SharedPreferences.setMockInitialValues({});
      await MedicalConsultDismissStore.save(t(1, 9));
      expect(await MedicalConsultDismissStore.load(), t(1, 9));
    });

    test('保存がない・読めない値なら null', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await MedicalConsultDismissStore.load(), isNull);
      SharedPreferences.setMockInitialValues({medicalConsultDismissedAtKey: 'abc'});
      expect(await MedicalConsultDismissStore.load(), isNull);
    });
  });

  group('MedicalConsultCard', () {
    Future<void> pumpCard(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MedicalConsultCard())));
      await tester.pumpAndSettle();
    }

    testWidgets('閉じていなければ文言と「※」の一言を出す', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpCard(tester);
      expect(find.text(medicalConsultMessage), findsOneWidget);
      expect(find.text(medicalConsultDisclaimer), findsOneWidget);
      expect(find.text('閉じる'), findsOneWidget);
    });

    testWidgets('［閉じる］で消え、閉じた日時を保存する', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpCard(tester);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(find.text(medicalConsultMessage), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(medicalConsultDismissedAtKey), isNotNull);
    });

    testWidgets('3 日前に閉じていれば出さない', (tester) async {
      SharedPreferences.setMockInitialValues({
        medicalConsultDismissedAtKey: DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
      });
      await pumpCard(tester);
      expect(find.text(medicalConsultMessage), findsNothing);
    });

    testWidgets('15 日前に閉じていればまた出す', (tester) async {
      SharedPreferences.setMockInitialValues({
        medicalConsultDismissedAtKey: DateTime.now().subtract(const Duration(days: 15)).toIso8601String(),
      });
      await pumpCard(tester);
      expect(find.text(medicalConsultMessage), findsOneWidget);
    });
  });

  group('文言と色', () {
    test('文言（病名を出さない）', () {
      expect(
        medicalConsultMessage,
        'ここ 2 週間、睡眠が目安（1日7時間）より 1 日平均 1 時間以上少ない状態が続いています。'
        '眠気や体調の不調が続くときは、産業医やかかりつけの医師に相談してみるのもひとつの方法です。',
      );
      expect(medicalConsultDisclaimer, '※このアプリは病気の診断をするものではありません。');
      expect(medicalConsultMessage, isNot(contains('障害')));
    });

    test('文字と背景の明るさの差は 4.5:1 以上', () {
      for (final color in [medicalConsultText, medicalConsultSubText, medicalConsultAction]) {
        expect(contrast(color, medicalConsultBg), greaterThanOrEqualTo(4.5), reason: '$color');
      }
    });
  });
}
