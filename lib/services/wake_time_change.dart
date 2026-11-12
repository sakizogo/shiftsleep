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
