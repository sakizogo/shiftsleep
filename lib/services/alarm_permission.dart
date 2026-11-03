// 「アラームとリマインダー」・通知の許可の案内（N128）
//
// Android 14 以降で新しく入れると SCHEDULE_EXACT_ALARM は最初「許可しない」になるため、
// 起動時にいきなり設定画面を開くのをやめ、説明のダイアログ（初回だけ）とバナーで案内する
// DB・アラーム・権限の呼び出しには依存しない（Android かどうかの判定も呼び出し元。alarm_reschedule.dart も純粋な関数だけ）
// N128 2/2：「許可なし → 許可あり」に変わったら出勤前アラームを登録し直す（判定と文言）
import 'package:flutter/material.dart';
import 'package:shiftsleep/services/alarm_reschedule.dart';

/// 説明のダイアログを出したかどうかの SharedPreferences のキー
const alarmPermissionIntroShownKey = 'alarm_permission_intro_shown';

/// 説明のダイアログの文言
const alarmPermissionIntroTitle = '⏰ アラームを使うための許可';
const alarmPermissionIntroBody =
    '出勤前アラーム・起床アラームを正確な時刻に鳴らすため、次の画面で「アラームとリマインダー」をオンにしてください。そのあと、通知の許可もお願いします。';
const alarmPermissionIntroSettingsLabel = '設定する';
const alarmPermissionIntroLaterLabel = 'あとで';

/// バナーの文言
const alarmPermissionBannerText = '⚠️ 「アラームとリマインダー」が許可されていないため、アラームが鳴りません';
const alarmPermissionBannerButtonLabel = '設定を開く';

/// 説明のダイアログを出すか
/// まだ一度も出していなくて、アラームとリマインダー・通知のどちらかが許可されていないときだけ
bool shouldShowAlarmPermissionIntro({
  required bool alreadyShown,
  required bool exactAlarmGranted,
  required bool notificationGranted,
}) {
  if (alreadyShown) return false;
  return !exactAlarmGranted || !notificationGranted;
}

/// バナーを出すか
/// アラームが ON で、アラームとリマインダーが許可されていないときだけ（OFF なら鳴らなくて当然なので出さない）
bool shouldShowAlarmPermissionBanner({
  required bool alarmEnabled,
  required bool exactAlarmGranted,
}) {
  return alarmEnabled && !exactAlarmGranted;
}

/// 前回確かめた「アラームとリマインダー」の許可の状態の SharedPreferences のキー（N128 2/2）
const exactAlarmGrantedLastKey = 'exact_alarm_granted_last';

/// 許可されたときの文言（N128 2/2）
const alarmPermissionGrantedText = '✅ アラームが使えるようになりました';
const alarmPermissionGrantedReadFailedText = '⚠️ 出勤前アラームを登録できませんでした。シフトを確定し直してください';

/// 出勤前アラームを登録し直すか（N128 2/2）
/// - previousGranted：前回の記録（null＝まだ記録がない。このバージョンで初めて動いた）
/// 前回が「許可なし」で今回が「許可あり」、かつアラームが ON のときだけ。記録がないときは登録し直さない
bool shouldReschedulePreAlarmsOnGrant({
  required bool? previousGranted,
  required bool exactAlarmGranted,
  required bool alarmEnabled,
}) {
  return previousGranted == false && exactAlarmGranted && alarmEnabled;
}

/// 許可されて登録し直したあとの SnackBar（N128 2/2）。順に出す（前を消さない）
/// 優先順：読めなかった → エラー（AlarmService.alarmErrorMessage の文言） → 0 件・分が 0 → 成功
/// - 読めなかった・エラーのときは、括弧なしの ✅ のあとにオレンジの 2 本目（件数は出さない）
/// - manualWakeNotRestored（睡眠中で手動起床が有効）なら、最後にオレンジで manualWakeNotRestoredText
List<({String text, Color? color})> alarmPermissionGrantedMessages({
  required int count,
  required String? errorMessage,
  required bool readFailed,
  required bool alarmDisabled,
  bool manualWakeNotRestored = false,
}) {
  const ({String text, Color? color}) granted = (text: alarmPermissionGrantedText, color: Colors.green);
  final List<({String text, Color? color})> messages;
  if (readFailed) {
    messages = [granted, (text: alarmPermissionGrantedReadFailedText, color: Colors.orange)];
  } else if (errorMessage != null) {
    messages = [granted, (text: errorMessage, color: Colors.orange)];
  } else if (alarmDisabled || count == 0) {
    messages = [granted];
  } else {
    messages = [(text: '$alarmPermissionGrantedText（出勤前アラーム $count件を登録しました）', color: Colors.green)];
  }
  return [
    ...messages,
    if (manualWakeNotRestored) (text: manualWakeNotRestoredText, color: Colors.orange),
  ];
}
