import 'package:shiftsleep/repositories/vacation_repository.dart';

/// N165 2b：有給設定の保存で付与を合わせ直すときの判定と文言（DB にも画面にも依存しない）

/// 保存しようとしている初回付与日が、保存済みの値から変わったか（年・月・日で比べる）
/// - 入力欄が空（input が null）なら false
/// - 保存済みが null なら true（［⚡ 付与スケジュールを自動生成］が保存していない日付で付与を作っていることがあるため）
/// - それ以外は、年・月・日が違えば true
bool isFirstAccrualDateChanged({required DateTime? saved, required DateTime? input}) {
  if (input == null) return false;
  if (saved == null) return true;
  return !(saved.year == input.year && saved.month == input.month && saved.day == input.day);
}

/// 日付の表示（例：2025年10月2日）
String accrualDateText(DateTime date) => '${date.year}年${date.month}月${date.day}日';

/// 日数の表示（例：10.0日。ほかの有休の画面と同じく小数 1 桁）
String accrualDaysText(double days) => '${days.toStringAsFixed(1)}日';

/// どの付与にも入らなくなる使用のうち、新しい初回付与日より前の使用のほかの分（0 以下なら 0）
double extraUnallocatedDays(AccrualSyncImpact impact) {
  final extra = (impact.unallocatedAfter - impact.unallocatedBefore) - impact.usagesBeforeFirstDays;
  return extra > 0 ? extra : 0.0;
}

/// 知らせる ⚠️ の行（なければ空）
/// - 持ち越しの対象の付与がなくなる
/// - 新しい初回付与日より前の使用（件数・日数）。ほかにも入らなくなる分があれば「ほかに◯日」
/// - 初回付与日より前の使用がなくても、どの付与にも入らない使用が増えるなら、その日数
List<String> accrualSyncWarningLines({
  required AccrualSyncImpact impact,
  required DateTime firstAccrualDate,
  required int carriedOverDays,
}) {
  final lines = <String>[];
  if (impact.carryOverTargetLost) {
    lines.add('⚠️ 持ち越し $carriedOverDays 日の対象の付与がなくなり、残りに数えられなくなります');
  }
  final extra = extraUnallocatedDays(impact);
  if (impact.usagesBeforeFirstCount > 0) {
    lines.add('⚠️ ${accrualDateText(firstAccrualDate)}より前の有休 ${impact.usagesBeforeFirstCount} 件'
        '（${accrualDaysText(impact.usagesBeforeFirstDays)}）が、どの付与にも入らなくなります'
        '${extra > 0 ? '（ほかに ${accrualDaysText(extra)}）' : ''}');
  } else if (extra > 0) {
    lines.add('⚠️ 有休 ${accrualDaysText(extra)}分が、どの付与にも入らなくなります');
  }
  return lines;
}

/// 確認ダイアログを出すか（消す付与・足す付与・⚠️ のどれかがあれば出す）
bool accrualSyncNeedsConfirmation({
  required AccrualSyncPlan plan,
  required AccrualSyncImpact impact,
  required DateTime firstAccrualDate,
  required int carriedOverDays,
}) {
  return plan.toDelete.isNotEmpty ||
      plan.toAdd.isNotEmpty ||
      accrualSyncWarningLines(
        impact: impact,
        firstAccrualDate: firstAccrualDate,
        carriedOverDays: carriedOverDays,
      ).isNotEmpty;
}

/// ダイアログの 1 行目（保存済みが null なら「未設定」）
String firstAccrualDateChangeText({required DateTime? saved, required DateTime input}) =>
    '初回付与日を ${saved == null ? '未設定' : accrualDateText(saved)} → ${accrualDateText(input)} に変えます。';

/// ダイアログの題
const accrualSyncDialogTitle = '付与スケジュールの合わせ直し';

/// ダイアログの、使用の記録についての説明
const accrualSyncUsageNote = 'ℹ️ 使用の記録は消えません。残っている付与に割り当て直されます。';

/// ダイアログのボタン
const accrualSyncCancelLabel = 'キャンセル';
const accrualSyncConfirmLabel = '保存して付与を合わせ直す';

/// キャンセルしたときの SnackBar
const vacationSettingsNotSavedMessage = 'ℹ️ 保存しませんでした';

/// 保存できたときの SnackBar（合わせ直したら、実際の件数を添える）
String vacationSettingsSavedMessage(({int deletedCount, int addedCount})? synced) {
  const base = '✅ 有給設定を保存しました';
  if (synced == null) return base;
  if (synced.deletedCount == 0 && synced.addedCount == 0) return '$base（付与は変わりませんでした）';
  return '$base\n🗑️ 付与を ${synced.deletedCount} 件消し、➕ ${synced.addedCount} 件足しました';
}
