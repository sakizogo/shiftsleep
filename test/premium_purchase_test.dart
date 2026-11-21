// N138＋N139 2：RevenueCat の例外の判定（classifyPremiumError）と、復元の結果（restoreOutcomeForError）
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shiftsleep/services/premium_purchase.dart';

/// RevenueCat と同じ形の例外（code は PurchasesErrorCode の番号）
PlatformException _error(PurchasesErrorCode code) => PlatformException(code: '${code.index}');

void main() {
  group('classifyPremiumError', () {
    test('キャンセル → cancelled', () {
      expect(classifyPremiumError(_error(PurchasesErrorCode.purchaseCancelledError)), PremiumErrorKind.cancelled);
    });

    test('ネットワーク → network', () {
      expect(classifyPremiumError(_error(PurchasesErrorCode.networkError)), PremiumErrorKind.network);
    });

    test('オフライン → network', () {
      expect(classifyPremiumError(_error(PurchasesErrorCode.offlineConnectionError)), PremiumErrorKind.network);
    });

    test('保留中 → pending', () {
      expect(classifyPremiumError(_error(PurchasesErrorCode.paymentPendingError)), PremiumErrorKind.pending);
    });

    test('購入済み → alreadyPurchased', () {
      expect(classifyPremiumError(_error(PurchasesErrorCode.productAlreadyPurchasedError)),
          PremiumErrorKind.alreadyPurchased);
    });

    test('レシートが使用済み → alreadyPurchased', () {
      expect(classifyPremiumError(_error(PurchasesErrorCode.receiptAlreadyInUseError)),
          PremiumErrorKind.alreadyPurchased);
    });

    test('処理中 → inProgress', () {
      expect(classifyPremiumError(_error(PurchasesErrorCode.operationAlreadyInProgressError)),
          PremiumErrorKind.inProgress);
    });

    test('ストアの問題など、そのほか → other', () {
      expect(classifyPremiumError(_error(PurchasesErrorCode.storeProblemError)), PremiumErrorKind.other);
    });

    test('code が数字でない → other（例外にならない）', () {
      expect(classifyPremiumError(PlatformException(code: 'unexpected')), PremiumErrorKind.other);
    });

    test('PlatformException 以外 → other', () {
      expect(classifyPremiumError(Exception('db')), PremiumErrorKind.other);
    });
  });

  test('restoreOutcomeForError：network・inProgress はそのまま、それ以外は failed', () {
    expect(restoreOutcomeForError(PremiumErrorKind.network), PremiumRestoreOutcome.network);
    expect(restoreOutcomeForError(PremiumErrorKind.inProgress), PremiumRestoreOutcome.inProgress);
    for (final kind in [
      PremiumErrorKind.cancelled,
      PremiumErrorKind.pending,
      PremiumErrorKind.alreadyPurchased,
      PremiumErrorKind.other,
    ]) {
      expect(restoreOutcomeForError(kind), PremiumRestoreOutcome.failed, reason: kind.name);
    }
  });

  group('4a：premiumTrialOf（トライアルの取り出し）', () {
    test('defaultOption.freePhase が P2W → 14 日間（Play）', () {
      final trial = premiumTrialOf(_product(defaultOption: _optionWithFreePhase(PeriodUnit.week, 2)))!;
      expect(trial.label, '14 日間');
      expect(trial.source, PremiumTrialSource.defaultOptionFreePhase);
    });

    test('defaultOption.freePhase が P14D → 14 日間', () {
      expect(premiumTrialOf(_product(defaultOption: _optionWithFreePhase(PeriodUnit.day, 14)))!.label, '14 日間');
    });

    test('freePhase がなく、0 円の introductoryPrice が P2W → 14 日間（Test Store などの予備）', () {
      final trial = premiumTrialOf(_product(introductoryPrice: _intro(0, PeriodUnit.week, 2)))!;
      expect(trial.label, '14 日間');
      expect(trial.source, PremiumTrialSource.introductoryPrice);
    });

    test('introductoryPrice が割引（0 円でない）→ トライアルなし', () {
      expect(premiumTrialOf(_product(introductoryPrice: _intro(1.99, PeriodUnit.month, 1))), isNull);
    });

    test('freePhase も introductoryPrice もない（受けられない人）→ トライアルなし', () {
      expect(premiumTrialOf(_product(defaultOption: _optionWithFreePhase(null, 0))), isNull);
      expect(premiumTrialOf(_product()), isNull);
    });

    test('E30 A：月は「1 か月」、年は「1 年」、単位がわからないときは null', () {
      expect(premiumTrialPeriodLabel(PeriodUnit.month, 1), '1 か月');
      expect(premiumTrialPeriodLabel(PeriodUnit.year, 1), '1 年');
      expect(premiumTrialPeriodLabel(PeriodUnit.unknown, 3), isNull);
      expect(premiumTrialPeriodLabel(PeriodUnit.day, 0), isNull);
    });
  });

  group('4a：annualSavingsPercent（年額のお得の率）', () {
    test('Test Store：US\$6.99 と US\$69.99 → 16', () {
      expect(annualSavingsPercent(_product(price: 6.99), _product(price: 69.99)), 16);
    });

    test('Play：¥980 と ¥9,800 → 16', () {
      expect(
        annualSavingsPercent(_product(price: 980, currency: 'JPY'), _product(price: 9800, currency: 'JPY')),
        16,
      );
    });

    test('ちょうど 20% は 19 にならない', () {
      expect(annualSavingsPercent(_product(price: 10), _product(price: 96)), 20);
    });

    test('通貨が違う・0% 以下・月額が 0 → null', () {
      expect(annualSavingsPercent(_product(price: 6.99), _product(price: 9800, currency: 'JPY')), isNull);
      expect(annualSavingsPercent(_product(price: 6.99), _product(price: 83.88)), isNull);
      expect(annualSavingsPercent(_product(price: 0), _product(price: 69.99)), isNull);
    });
  });

  test('4a：PremiumPlan の periodLabel は 月・年', () {
    expect(PremiumPlan(PremiumPlanKind.monthly, _package(_product())).periodLabel, '月');
    expect(PremiumPlan(PremiumPlanKind.annual, _package(_product())).periodLabel, '年');
  });
}

StoreProduct _product({
  double price = 6.99,
  String currency = 'USD',
  SubscriptionOption? defaultOption,
  IntroductoryPrice? introductoryPrice,
}) =>
    StoreProduct('id', '', '', price, '$price', currency,
        defaultOption: defaultOption, introductoryPrice: introductoryPrice);

Package _package(StoreProduct product) =>
    Package(r'$rc_monthly', PackageType.monthly, product, const PresentedOfferingContext('default', null, null));

IntroductoryPrice _intro(double price, PeriodUnit unit, int units) =>
    IntroductoryPrice(price, '$price', 'P$units', 1, unit, units);

/// unit が null なら freePhase なし
SubscriptionOption _optionWithFreePhase(PeriodUnit? unit, int value) {
  final free = unit == null
      ? null
      : PricingPhase(Period(unit, value, 'P$value'), RecurrenceMode.nonRecurring, 1, const Price('Free', 0, 'USD'),
          OfferPaymentMode.freeTrial);
  return SubscriptionOption('base:trial', 'id:base', 'id', const [], const [], false, null, false, null, free, null,
      null, null);
}
