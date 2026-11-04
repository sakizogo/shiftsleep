// 鳴っているアラームをホーム画面から止める（N129 2/2）
//
// 通知の許可がないと通知の「停止」が見えず、睡眠中でないときはアプリから止める手段がなかったため、
// 音が鳴っている間は全タブの上に［止める］を出す
// DB・アラーム・権限の呼び出しには依存しない（alarm_permission.dart と同じく純粋な関数と文言だけ）

/// 鳴っていることを知らせるバナーの文言
const stopAlarmBannerText = '🔔 アラームが鳴っています';
const stopAlarmButtonLabel = '止める';
const stopAlarmFailedText = '⚠️ アラームを止められませんでした。もう一度お試しください';

/// ［止める］を出すか
/// 鳴っていて、睡眠中でないときだけ（睡眠中は「起きる」で止める。音だけ止めると起床が記録されないため）
bool shouldShowStopAlarmButton({
  required bool isRinging,
  required bool isSleeping,
}) {
  return isRinging && !isSleeping;
}
