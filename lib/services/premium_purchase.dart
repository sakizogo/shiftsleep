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

/// 2b：RevenueCat に確かめた結果（「確かめられた」と「確かめられなかった」を分ける）
enum PremiumVerification {
  /// 確かめられた：プレミアム
  premium,

  /// 確かめられた：無料
  free,

  /// 確かめられなかった（オフラインなど）。キャッシュも DB も変えない
  unavailable,

  /// RevenueCat を configure していない（RevenueCat を呼ばない）
  notConfigured,
}

/// 2b：Provider の refreshPremiumStatus の結果
enum PremiumRefreshOutcome {
  /// 本当の値と違ったので setPremiumStatus で更新した
  updated,

  /// 本当の値と同じだった（何もしない）
  unchanged,

  /// 確かめられなかった（値を変えない）
  unavailable,

  /// configure していない（値を変えない）
  notConfigured,

  /// 確かめなかった（15 分以内・確かめている途中・購入や復元の途中）
  skipped,
}

/// 商品の種類（D19 A'：月額・年額）
enum PremiumPlanKind { monthly, annual }

/// 画面に渡す商品（E10 B）
///
/// 値段はストアの値（D27）。トライアルの日数（D28・D29）もストアの情報から出す（4a）
class PremiumPlan {
  const PremiumPlan(this.kind, this.package);

  final PremiumPlanKind kind;

  /// 購入に使う（画面からは触らない）
  final Package package;

  /// ストアの値段の文字（例：¥980）
  String get priceString => package.storeProduct.priceString;

  /// 期間の文字（「月」「年」）。値段のあとに「／月」のように付ける
  String get periodLabel => switch (kind) {
        PremiumPlanKind.monthly => '月',
        PremiumPlanKind.annual => '年',
      };

  /// 無料トライアル（受けられないとき・ないときは null）
  PremiumTrial? get trial => premiumTrialOf(package.storeProduct);
}

/// 4a：トライアルの情報をどの欄から取ったか（logcat で確かめる）
enum PremiumTrialSource {
  /// StoreProduct.defaultOption.freePhase（Google Play）
  defaultOptionFreePhase,

  /// StoreProduct.introductoryPrice の 0 円のもの（Test Store などの予備）
  introductoryPrice,
}

/// 4a：無料トライアル（D28・D29：日数はストアの情報から出す）
class PremiumTrial {
  const PremiumTrial({required this.label, required this.source});

  /// 期間の文字（E30 A：日と週は日数で「14 日間」、月は「1 か月」、年は「1 年」）
  final String label;

  final PremiumTrialSource source;
}

/// 4a：トライアルの期間の文字（E30 A）。単位がわからないときは null
String? premiumTrialPeriodLabel(PeriodUnit unit, int value) {
  if (value <= 0) return null;
  switch (unit) {
    case PeriodUnit.day:
      return '$value 日間';
    case PeriodUnit.week:
      return '${value * 7} 日間';
    case PeriodUnit.month:
      return '$value か月';
    case PeriodUnit.year:
      return '$value 年';
    case PeriodUnit.unknown:
      return null;
  }
}

/// 4a：StoreProduct から無料トライアルを取り出す
///
/// - Google Play：defaultOption.freePhase。Play はその人が受けられるオファーだけを返すので、受けた人では null になる
/// - 予備：introductoryPrice の 0 円のもの（割引の値段はトライアルとして扱わない）
/// - checkTrialOrIntroductoryPriceEligibility は Android ではいつも unknown なので使わない
PremiumTrial? premiumTrialOf(StoreProduct product) {
  final freePhase = product.defaultOption?.freePhase;
  final freePeriod = freePhase?.billingPeriod;
  if (freePhase != null && freePeriod != null) {
    final label = premiumTrialPeriodLabel(freePeriod.unit, freePeriod.value * (freePhase.billingCycleCount ?? 1));
    return label == null ? null : PremiumTrial(label: label, source: PremiumTrialSource.defaultOptionFreePhase);
  }
  final intro = product.introductoryPrice;
  if (intro != null && intro.price == 0) {
    final cycles = intro.cycles < 1 ? 1 : intro.cycles;
    final label = premiumTrialPeriodLabel(intro.periodUnit, intro.periodNumberOfUnits * cycles);
    return label == null ? null : PremiumTrial(label: label, source: PremiumTrialSource.introductoryPrice);
  }
  return null;
}

/// 4a：年額が月額の 12 か月ぶんより何 % 安いか（E29 A：小数は切り捨て）
/// 通貨が違うとき・月額が 0 以下のとき・0% 以下のときは null（バッジを出さない）
int? annualSavingsPercent(StoreProduct monthly, StoreProduct annual) {
  if (monthly.currencyCode != annual.currencyCode) return null;
  if (monthly.price <= 0) return null;
  // 割り算の端数で 20% が 19% にならないよう、少しだけ足してから切り捨てる
  final percent = ((1 - annual.price / (monthly.price * 12)) * 100 + 1e-9).floor();
  return percent > 0 ? percent : null;
}
