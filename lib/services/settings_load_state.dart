// N118 2/4 2c：設定画面で設定を読み込めなかったときの扱い
//
// 読み込めるまで（最初の読み込み中・失敗中）は、画面の値を変える・保存する操作を押せなくする。
// 画面に出ている既定値（30 分・07:00・'default' など）で DB を上書きしないため
// アラーム全体の ON/OFF は DB を読み直すので、失敗中も押せる
import 'package:flutter/material.dart';

/// 画面の値を変える・保存する操作を押せるか
/// （［設定を保存］・起床時刻の［変更］・出勤前アラームのプルダウン・promo のスイッチ・
///   アラーム音のプルダウンと［アラーム音を保存］・毎日のチェック）
/// - loaded：設定の読み込みに成功したか（行がなかったときも成功。読み込み中・失敗中は false）
/// - alarmBusy：アラームの処理中（N123〜N125 の _isAlarmBusy）
bool canEditSettings({required bool loaded, required bool alarmBusy}) => loaded && !alarmBusy;

/// アラーム全体の ON/OFF スイッチを押せるか（読み込みの成否は見ない）
bool canToggleAlarm({required bool alarmBusy}) => !alarmBusy;

/// ［再読み込み］を押せるか（再読み込み中は押せない）
bool canReloadSettings({required bool reloading}) => !reloading;

/// 読み込めなかったときのバナーの 1 行目
const settingsLoadFailedTitle = '⚠️ 設定を読み込めませんでした';

/// 読み込めなかったときのバナーの 2 行目
const settingsLoadFailedBody =
    'いまは既定の値（起床 7:00・出勤前 30 分前など）を表示しています。'
    '読み込めるまで、設定の変更と保存はできません（アラームの ON/OFF は使えます）';

/// 再読み込みの結果の知らせ（color が null なら既定の色）
({String text, Color? color}) settingsReloadMessage({required bool succeeded}) {
  if (succeeded) {
    return (text: '✅ 設定を読み込みました', color: null);
  }
  return (
    text: '⚠️ まだ設定を読み込めません。しばらくしてからもう一度お試しください',
    color: Colors.orange,
  );
}
