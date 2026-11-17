// N186：実行ヒント（actionTip）の出し方（actionTipView）と、無料・プレミアムでのアドバイスの絞り込み（filterAdviceByPlan）
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/sleep_advisory_service.dart';

SleepAdvice _advice(
  String title, {
  int priority = 1,
  bool isPremiumOnly = false,
  String? actionTip,
}) =>
    SleepAdvice(
      title: title,
      description: '$title の説明',
      category: 'sri',
      priority: priority,
      isPremiumOnly: isPremiumOnly,
      actionTip: actionTip,
    );

void main() {
  group('actionTipView', () {
    final withTip = _advice('ヒントあり', actionTip: 'ヒントの中身');
    final noTip = _advice('ヒントなし');

    test('actionTip がなければ、プレミアムでも無料でも出さない', () {
      for (final isPremium in [true, false]) {
        for (final promoVisible in [true, false]) {
          expect(
            actionTipView(noTip, isPremium: isPremium, promoVisible: promoVisible),
            ActionTipView.hidden,
            reason: 'isPremium=$isPremium, promoVisible=$promoVisible',
          );
        }
      }
    });

    test('プレミアムは、🔒 の案内の ON・OFF によらず中身を出す', () {
      expect(actionTipView(withTip, isPremium: true, promoVisible: true), ActionTipView.shown);
      expect(actionTipView(withTip, isPremium: true, promoVisible: false), ActionTipView.shown);
    });

    test('無料で 🔒 の案内が ON なら、案内だけ出す', () {
      expect(actionTipView(withTip, isPremium: false, promoVisible: true), ActionTipView.locked);
    });

    test('無料で 🔒 の案内が OFF なら、何も出さない', () {
      expect(actionTipView(withTip, isPremium: false, promoVisible: false), ActionTipView.hidden);
    });

    test('🔒 の案内の文言（💡 はつけない。🔒 のアイコンと重ねない）', () {
      expect(actionTipLockedLabel, '実行ヒント（プレミアム版で解放）');
    });
  });

  group('filterAdviceByPlan', () {
    test('無料は優先度 1 の最初の 1 件だけ', () {
      final advices = [
        _advice('A', priority: 1),
        _advice('B', priority: 1),
        _advice('C', priority: 2),
      ];
      final result = SleepAdvisoryService.filterAdviceByPlan(advices, isPremiumUser: false);
      expect(result.map((a) => a.title), ['A']);
    });

    test('無料は有料版限定（isPremiumOnly）のアドバイスを除く', () {
      final advices = [
        _advice('有料版限定', priority: 1, isPremiumOnly: true),
        _advice('ふつう', priority: 1),
      ];
      final result = SleepAdvisoryService.filterAdviceByPlan(advices, isPremiumUser: false);
      expect(result.map((a) => a.title), ['ふつう']);
    });

    test('N203：無料で優先度 1 がなければ、有料版限定でない中でいちばん上の 1 件', () {
      final advices = [
        _advice('有料版限定', priority: 2, isPremiumOnly: true),
        _advice('B', priority: 2),
        _advice('C', priority: 3),
      ];
      expect(SleepAdvisoryService.filterAdviceByPlan(advices, isPremiumUser: false).map((a) => a.title), ['B']);
    });

    test('N203：無料で優先度 1 が後ろにあっても、優先度 1 を選ぶ', () {
      final advices = [_advice('B', priority: 2), _advice('A', priority: 1)];
      expect(SleepAdvisoryService.filterAdviceByPlan(advices, isPremiumUser: false).map((a) => a.title), ['A']);
    });

    test('N203：無料で有料版限定しかなければ空', () {
      final advices = [_advice('有料版限定', priority: 2, isPremiumOnly: true)];
      expect(SleepAdvisoryService.filterAdviceByPlan(advices, isPremiumUser: false), isEmpty);
      expect(SleepAdvisoryService.filterAdviceByPlan(const [], isPremiumUser: false), isEmpty);
    });

    test('無料でも actionTip は残す（出し方は actionTipView で決める）', () {
      final advices = [_advice('A', actionTip: 'ヒントの中身')];
      final result = SleepAdvisoryService.filterAdviceByPlan(advices, isPremiumUser: false);
      expect(result.single.actionTip, 'ヒントの中身');
    });

    test('プレミアムは有料版限定も含めて、並びのまま最大 5 件', () {
      final advices = [
        for (var i = 1; i <= 6; i++) _advice('$i', priority: i <= 3 ? 1 : 2, isPremiumOnly: i == 2),
      ];
      final result = SleepAdvisoryService.filterAdviceByPlan(advices, isPremiumUser: true);
      expect(result.map((a) => a.title), ['1', '2', '3', '4', '5']);
    });
  });

  group('N203：emptyAdviceMessage', () {
    final a = _advice('A');
    final premiumOnly = _advice('有料版限定', isPremiumOnly: true);

    test('出すものがあれば null', () {
      expect(SleepAdvisoryService.emptyAdviceMessage(all: [a], displayed: [a]), isNull);
    });

    test('記録が足りず 1 件も作れないときは N197 の文', () {
      expect(SleepAdvisoryService.emptyAdviceMessage(all: const [], displayed: const []), adviceNotEnoughRecordsText);
      expect(adviceNotEnoughRecordsText, '睡眠の記録がたまると、改善アドバイスが表示されます');
    });

    test('作れたのに出せるものが 0 件なら「今は大きな改善点はありません」', () {
      expect(SleepAdvisoryService.emptyAdviceMessage(all: [premiumOnly], displayed: const []), adviceNothingToImproveText);
      expect(adviceNothingToImproveText, '今は大きな改善点はありません');
    });
  });

  test('N189：優先度の札の文字', () {
    expect([1, 2, 3].map(advicePriorityLabel), ['優先度 高', '優先度 中', '優先度 低']);
  });
}
