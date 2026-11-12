// N147：設定画面の「この設定を毎日使用する」のあとに出す SnackBar（DB にも画面にも依存しない）
//
// 睡眠中に ON にしたときは起床アラームを登録し直すので、その結果も知らせる
// 失敗があるときはオレンジの ⚠️ だけを出し、「✅ 毎晩…」は出さない（N22 と同じ）
// 例外の中身は文言に入れない（ログに出す）
import 'package:flutter/material.dart';
import 'package:shiftsleep/services/wake_alarm_choice.dart';

/// 毎日の設定を保存できなかったとき（setDaily が例外）
const dailyWakeSaveFailedText = '⚠️ 毎日の設定を保存できませんでした。表示を確かめて、もう一度お試しください';

/// 毎日の設定は保存できたが、睡眠中の起床アラームの登録が例外で止まったとき
const dailyWakeAlarmFailedText =
    '⚠️ 毎日の設定は保存しましたが、今夜の起床アラームを設定できませんでした。'
    'もう一度チェックし直すか、「変更」で起床時刻を選び直してください';

/// 保存したあと表示を読み直せなかったとき（N154）
const dailyWakeReloadFailedText = '⚠️ 毎日の設定は保存しましたが、表示を読み直せませんでした。画面を開き直してください';

/// 「毎日」チェックのあとに順に出す SnackBar（color が null なら既定の色）
/// - enabled：ON にしたか
/// - timeText：毎日使う時刻（"07:00"）
/// - saveFailed：setDaily が例外を投げた
/// - reloadFailed：保存したあと表示を読み直せなかった
/// - alarmResult：睡眠中に ON にして登録した結果（それ以外は null）
/// - alarmError：睡眠中に ON にして、登録が例外で止まった
List<({String text, Color? color, int seconds})> dailyWakeToggleMessages({
  required bool enabled,
  required String timeText,
  required bool saveFailed,
  required bool reloadFailed,
  WakeAlarmRegistrationResult? alarmResult,
  bool alarmError = false,
}) {
  ({String text, Color? color, int seconds}) warning(String text) =>
      (text: text, color: Colors.orange, seconds: 6);

  if (saveFailed) return [warning(dailyWakeSaveFailedText)];

  final reloadWarning = reloadFailed ? warning(dailyWakeReloadFailedText) : null;
  if (alarmError) {
    return [
      if (reloadWarning != null) reloadWarning,
      warning(dailyWakeAlarmFailedText),
    ];
  }

  final alarmMessages = alarmResult == null ? const <({String text, Color? color})>[] : wakeAlarmMessages(alarmResult);
  final alarmWarnings = alarmMessages.where((message) => message.color != null);
  if (alarmWarnings.isNotEmpty) {
    return [
      if (reloadWarning != null) reloadWarning,
      for (final message in alarmWarnings) warning(message.text),
    ];
  }

  final savedText = enabled
      ? '✅ 毎晩 $timeText に起こします（出勤前アラームの方が早い日はそちらを優先）'
      : '⬜ 「変更」で選んだ夜だけこの時刻を使います';
  return [
    reloadWarning ?? (text: savedText, color: null, seconds: 2),
    for (final message in alarmMessages) (text: message.text, color: null, seconds: 6),
  ];
}
