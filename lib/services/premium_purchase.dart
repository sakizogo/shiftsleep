// N138＋N139 2：購入・復元・商品の取得の結果の種類と、RevenueCat の例外の判定
//
// 画面はこの結果で SnackBar を出し分ける（キャンセル・処理中は何も出さない）
// 判定は純粋関数にしてテストする
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat の例外の種類
enum PremiumErrorKind { cancelled, network, pending, alreadyPurchased, inProgress, other }

/// RevenueCat の例外を種類に分ける
///
/// PurchasesErrorHelper.getErrorCode は code を数字として読むので、数字でない code（FormatException）も other にする
PremiumErrorKind classifyPremiumError(Object error) {
  if (error is! PlatformException) return PremiumErrorKind.other;
  final PurchasesErrorCode code;
  try {
    code = PurchasesErrorHelper.getErrorCode(error);
  } catch (_) {
    return PremiumErrorKind.other;
  }
  switch (code) {
    case PurchasesErrorCode.purchaseCancelledError:
      return PremiumErrorKind.cancelled;
    case PurchasesErrorCode.networkError:
    case PurchasesErrorCode.offlineConnectionError:
      return PremiumErrorKind.network;
    case PurchasesErrorCode.paymentPendingError:
      return PremiumErrorKind.pending;
    case PurchasesErrorCode.productAlreadyPurchasedError:
    case PurchasesErrorCode.receiptAlreadyInUseError:
      return PremiumErrorKind.alreadyPurchased;
    case PurchasesErrorCode.operationAlreadyInProgressError:
      return PremiumErrorKind.inProgress;
    default:
      return PremiumErrorKind.other;
  }
}

/// 購入の結果
enum PremiumPurchaseOutcome {
  /// プレミアムになった（✨）
  success,

  /// 購入は通ったが entitlement（ShiftSleep Pro）がない（❌）
  notEntitled,

  /// キャンセル（何も出さない）
  cancelled,

  /// 通信できなかった（⚠️ オレンジ）
  network,

  /// お支払いの確認待ち（ℹ️ 青。プレミアムにはしない）
  pending,

  /// 購入済みのエラーのあと復元しても entitlement がない（別のアカウントで購入済み）
  ownedByOtherAccount,

  /// 処理中（何も出さない）
  inProgress,

  /// RevenueCat を configure していない（D25 B：「準備中です」）
  notConfigured,

  /// そのほか（❌ 赤）
  failed,
}

/// 復元の結果
enum PremiumRestoreOutcome { restored, nothingToRestore, network, inProgress, notConfigured, failed }

/// 復元の例外の種類 → 復元の結果（E13 A：自動の復元が失敗したときも、これに従う）
PremiumRestoreOutcome restoreOutcomeForError(PremiumErrorKind kind) {
  switch (kind) {
    case PremiumErrorKind.network:
      return PremiumRestoreOutcome.network;
    case PremiumErrorKind.inProgress:
      return PremiumRestoreOutcome.inProgress;
    case PremiumErrorKind.cancelled:
    case PremiumErrorKind.pending:
    case PremiumErrorKind.alreadyPurchased:
    case PremiumErrorKind.other:
      return PremiumRestoreOutcome.failed;
  }
}

/// 商品の取得の結果
enum PremiumPlansOutcome { ready, empty, notConfigured, network, failed }

/// 商品の種類（D19 A'：月額・年額）
enum PremiumPlanKind { monthly, annual }

/// 画面に渡す商品（E10 B）
///
/// 値段はストアの値（D27）。トライアルの日数（D28・D29）は 4a で足す
class PremiumPlan {
  const PremiumPlan(this.kind, this.package);

  final PremiumPlanKind kind;

  /// 購入に使う（画面からは触らない）
  final Package package;

  /// ストアの値段の文字（例：¥980）
  String get priceString => package.storeProduct.priceString;
}
