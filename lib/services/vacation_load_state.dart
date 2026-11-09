// N118 3/4 3b：有給設定画面で有給設定を読み込めなかったときの扱い
// N118 3/4 3c＋3d：有給使用画面・有給の統計カードも同じ VacationLoadState を使う
//
// 読み込めるまで（最初の読み込み中・失敗中）は、画面の値を変える・保存する・自動生成する・自動計算に戻す操作を
// 押せなくする。空の入力欄のまま保存して、DB の持ち越し・入社日などを上書きしないため
// 一部だけ読めなかったときも、全体を「読み込めなかった」として扱う（読めた値だけを出さない）
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/services/vacation_allocation.dart';

/// 有給設定画面・有給使用画面・有給の統計カードの読み込みの状態
/// - loading：最初の読み込み中（保存などのあとの読み直しでは戻さない）
/// - failed：読み込みに失敗した（画面は全体を ❌ と［再読み込み］、カードは「—」と［再読み込み］にする）
/// - loaded：読み込めた（行がなかったときも含む）
enum VacationLoadState { loading, failed, loaded }

/// 画面の値を変える・保存する・自動生成する・自動計算に戻す操作を押せるか
/// （［設定を保存］・［付与スケジュールを自動生成］・［自動計算に戻す］・入社日と初回付与日の選択・入力欄）
bool canEditVacationSettings(VacationLoadState state) =>
    state == VacationLoadState.loaded;

/// ［再読み込み］を押せるか（再読み込み中は押せない）
bool canReloadVacationSettings({required bool reloading}) => !reloading;

/// 読み込めなかったときの画面の 1 行目
const vacationSettingsLoadFailedTitle = '❌ 有給設定を読み込めませんでした';

/// 読み込めなかったときの画面の本文
const vacationSettingsLoadFailedBody =
    '保存されている入社日・持ち越し・初回付与日などを確かめられないため、'
    '読み込めるまで設定の変更・保存・自動生成はできません。［再読み込み］を押してください';

/// 再読み込みの結果の知らせ（color が null なら既定の色）
({String text, Color? color}) vacationSettingsReloadMessage({required bool succeeded}) {
  if (succeeded) {
    return (text: '✅ 有給設定を読み込みました', color: null);
  }
  return (
    text: '⚠️ まだ有給設定を読み込めません。しばらくしてからもう一度お試しください',
    color: Colors.orange,
  );
}

// ========== N118 3/4 3c：有給使用画面 ==========

/// ［使用記録を追加］を出すか・記録の追加と削除・使用日の選択を押せるか（読み込めたときだけ）
bool canAddVacationUsage(VacationLoadState state) => state == VacationLoadState.loaded;

/// 有給使用画面を読み込めなかったときの 1 行目
const vacationUsageLoadFailedTitle = '❌ 有給使用記録を読み込めませんでした';

/// 有給使用画面を読み込めなかったときの本文
const vacationUsageLoadFailedBody =
    '残日数・使用履歴を確かめられないため、読み込めるまで使用記録の追加・削除はできません。'
    '［再読み込み］を押してください';

/// 有給使用画面の再読み込みの結果の知らせ（color が null なら既定の色）
({String text, Color? color}) vacationUsageReloadMessage({required bool succeeded}) {
  if (succeeded) {
    return (text: '✅ 有給使用記録を読み込みました', color: null);
  }
  return (
    text: '⚠️ まだ有給使用記録を読み込めません。しばらくしてからもう一度お試しください',
    color: Colors.orange,
  );
}

// ========== N118 3/4 3d：有給の統計カード ==========

/// 統計カードを読み込めなかったときの文言（カードの中に［再読み込み］と一緒に出す）
const vacationStatsLoadFailedText = '❌ 有給の統計を読み込めませんでした';

/// 統計カードの日数の表示。読めなかった（null）なら「—」。0 は「0.0日」（失敗と 0 日を分ける）
String vacationStatsDaysText(double? days) =>
    days == null ? '—' : '${days.toStringAsFixed(1)}日';

/// 内訳の行・消滅予定のカードを出すか（読み込めたときだけ。D4：失敗中は出さない）
bool showVacationStatsDetails(VacationLoadState state) => state == VacationLoadState.loaded;

/// 読んだ値から入力欄に入れる値を作る
/// - hiredDate・annualDaysText：vacation_settings の行があるときだけ。行がなければ null（欄はそのまま）
/// - carriedOverText：行がなくても入れる（P8：空のまま保存して持ち越しを 0 にしない）
///   0 以下か、対象の付与が失効していれば ''（N80：画面を開いただけでは DB に書かない）
/// - carriedOverBaseDate：対象の付与があって有効なあいだだけ（説明に添える）
/// - firstAccrualDateText：行がなくても入れる（P8）。未登録なら null（欄はそのまま）
({
  DateTime? hiredDate,
  String? annualDaysText,
  String carriedOverText,
  DateTime? carriedOverBaseDate,
  String? firstAccrualDateText,
}) vacationFormValues({
  required VacationSettings? settings,
  required double carriedOverDays,
  required CarryOver? carryOver,
  required bool hasCarryOverTarget,
  required bool carryOverExpired,
  required DateTime? firstAccrualDate,
}) {
  return (
    hiredDate: settings?.hiredDate,
    annualDaysText: settings?.annualDays.toString(),
    carriedOverText:
        carriedOverDays > 0 && !carryOverExpired ? carriedOverDays.toStringAsFixed(0) : '',
    carriedOverBaseDate:
        carryOver != null && hasCarryOverTarget && !carryOverExpired ? carryOver.baseDate : null,
    firstAccrualDateText:
        firstAccrualDate == null ? null : DateFormat('yyyy年M月d日').format(firstAccrualDate),
  );
}
