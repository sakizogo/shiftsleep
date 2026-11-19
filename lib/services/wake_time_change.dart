// N166：設定画面で起床時刻を［変更］したあとの判定と SnackBar（DB にも画面にも依存しない）
//
// 今夜だけの予約（ManualWakeService.save）を保存できなかったら、元の時刻に戻して DB の保存へは進まない
// 予約は保存できて「毎日」の書き込み（setDaily）だけ失敗したら、DB の保存は続け、✅ のあとに ⚠️ を出す
// 例外の中身は文言に入れない（ログに出す）
import 'package:flutter/material.dart';

/// 今夜だけの予約を保存できなかったとき（save が例外）
const wakeTimeSaveFailedText = '⚠️ 起床時刻を保存できませんでした。もう一度お試しください';

/// 予約は保存できたが、「毎日」の設定を保存できなかったとき（setDaily が例外）
const wakeTimeDailySaveFailedText =
    '⚠️ 今夜の起床時刻は保存しましたが、『毎日』の設定を保存できませんでした。チェックの表示を確かめてください';

/// 予約を保存できたときだけ、設定の保存（_saveSettings）へ進む
bool shouldSaveSettingsAfterWakeTimeChange({required bool saveFailed}) => !saveFailed;

/// ［変更］のあとに出す ⚠️（失敗がなければ空）
/// - saveFailed：save が例外を投げた（このときは setDaily を呼ばないので、dailyFailed は見ない）
/// - dailyFailed：setDaily が例外を投げた（_saveSettings の ✅ のあとに出す）
List<({String text, Color? color, int seconds})> wakeTimeChangeMessages({
  required bool saveFailed,
  required bool dailyFailed,
}) {
  ({String text, Color? color, int seconds}) warning(String text) =>
      (text: text, color: Colors.orange, seconds: 6);

  if (saveFailed) return [warning(wakeTimeSaveFailedText)];
  if (dailyFailed) return [warning(wakeTimeDailySaveFailedText)];
  return const [];
}

/// N195：起きているときに起床時刻を変えて保存したときの知らせ（起床アラームは「今から寝る」で登録される）
const awakeNoAlarmText = '⚠️ 起きているあいだは、起床アラームは登録されません。『今から寝る』を押すと登録されます';

/// N195：保存で起床時刻が変わったか
/// - before：保存の直前に読み直した値（行がなければ画面の元の値）。after：保存する値（"HH:mm"）
/// - "7:00" と "07:00" は同じとみなす。読めない値は「変わった」とみなす
/// - chosen：［変更］で時刻を選んで確定した（同じ時刻でも今夜の予約を作り直すので「変わった」とみなす。D11）
bool wakeTimeChangedOnSave({required String before, required String after, required bool chosen}) {
  if (chosen) return true;
  final beforeMinutes = _minutesOfDay(before);
  final afterMinutes = _minutesOfDay(after);
  if (beforeMinutes == null || afterMinutes == null) return true;
  return beforeMinutes != afterMinutes;
}

/// "H:mm" / "HH:mm" を 0:00 からの分にする（読めなければ null）
int? _minutesOfDay(String time) {
  final parts = time.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

/// N195：「起きているあいだは…」を出すか（起床時刻が変わった・アラームが ON・起きている、のすべてを満たすとき）
bool shouldShowAwakeNoAlarmNotice({
  required bool wakeTimeChanged,
  required bool alarmEnabled,
  required bool sleepingNow,
}) =>
    wakeTimeChanged && alarmEnabled && !sleepingNow;
