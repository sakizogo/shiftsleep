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
}
