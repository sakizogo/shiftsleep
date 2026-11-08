// N118 3/4 3b：有給設定画面で有給設定を読み込めなかったときの扱い
//
// 読み込めるまで（最初の読み込み中・失敗中）は、画面の値を変える・保存する・自動生成する・自動計算に戻す操作を
// 押せなくする。空の入力欄のまま保存して、DB の持ち越し・入社日などを上書きしないため
// 一部だけ読めなかったときも、全体を「読み込めなかった」として扱う（読めた値だけを出さない）
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/services/vacation_allocation.dart';

/// 有給設定画面の読み込みの状態
/// - loading：最初の読み込み中（保存などのあとの読み直しでは戻さない）
/// - failed：読み込みに失敗した（画面全体を ❌ と［再読み込み］にする）
/// - loaded：読み込めた（行がなかったときも含む）
enum VacationSettingsLoadState { loading, failed, loaded }

/// 画面の値を変える・保存する・自動生成する・自動計算に戻す操作を押せるか
/// （［設定を保存］・［付与スケジュールを自動生成］・［自動計算に戻す］・入社日と初回付与日の選択・入力欄）
bool canEditVacationSettings(VacationSettingsLoadState state) =>
    state == VacationSettingsLoadState.loaded;

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
