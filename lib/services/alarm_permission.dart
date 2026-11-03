// 「アラームとリマインダー」・通知の許可の案内（N128）
//
// Android 14 以降で新しく入れると SCHEDULE_EXACT_ALARM は最初「許可しない」になるため、
// 起動時にいきなり設定画面を開くのをやめ、説明のダイアログ（初回だけ）とバナーで案内する
// DB・アラーム・権限の呼び出しには依存しない（Android かどうかの判定も呼び出し元）

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
