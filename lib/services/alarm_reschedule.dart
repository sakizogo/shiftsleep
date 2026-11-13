// 設定でアラームを ON に戻したときの、出勤前アラーム（pre）の登録し直し（N123）
//
// H4 の OFF は登録済みの main / pre をすべて取り消すため、ON に戻したら DB のシフトから pre を登録し直す
// 登録する日は確定（N117）と同じ confirmAlarmPlan で決め、すでに過ぎた pre は除く（件数に入れないため）
// N124：アラーム音を保存したときも、同じ処理で pre を新しい音で登録し直す（文言は soundSaveMessages）
// N125：設定の保存で分数が変わったら、pre を取り消して新しい分数で登録し直す（文言は settingsSaveMessages）
// DB・アラームには依存しない
import 'package:flutter/material.dart';
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/confirm_alarm_plan.dart';
import 'package:shiftsleep/services/shift_load.dart';

/// 登録し直す pre の日・開始時刻・実際の開始日時・鳴る時刻
/// - rows は shifts の行（shift_date・pattern_id）。パターンは shiftMapFromRows で決める
/// - 出勤（work）で開始時刻がある、昨日〜rangeEnd の日（confirmAlarmPlan の schedule と同じ。N180 3/3 で昨日から）
/// - startAt は勤務が実際に始まる日時（shiftStartDateTime。0:00〜4:59 開始は登録した日の翌日。N180 3/3）
/// - preAt（startAt−minutesBefore）が now より後の日だけ
/// - minutesBefore が 0 以下（無効）なら空
/// - shift_date が読めない行があれば例外（shiftMapFromRows。読み込みの失敗として扱う）
List<({DateTime date, TimeOfDay startTime, DateTime startAt, DateTime preAt})> preAlarmRescheduleTargets(
  List<Map<String, dynamic>> rows,
  List<ShiftPatternModel> patterns,
  ShiftPatternModel dayOffPattern,
  int minutesBefore,
  DateTime now,
  DateTime rangeEnd,
) {
  final map = shiftMapFromRows(rows, patterns, dayOffPattern);
  if (minutesBefore <= 0) return [];
  final plan = confirmAlarmPlan(const [], map, DateTime(now.year, now.month, now.day - 1), rangeEnd);
  final targets = <({DateTime date, TimeOfDay startTime, DateTime startAt, DateTime preAt})>[];
  for (final shift in plan.schedule) {
    final preAt = shift.startAt.subtract(Duration(minutes: minutesBefore));
    if (preAt.isAfter(now)) {
      targets.add((date: shift.date, startTime: shift.startTime, startAt: shift.startAt, preAt: preAt));
    }
  }
  return targets;
}

/// 各件の scheduleAlarmForShift の戻り値（null=成功）から、成功件数と知らせるエラーコードを決める
/// エラーコードは EXACT_ALARM_DENIED を優先し、なければ最後のエラー（確定と同じ）
({int count, String? errorCode}) summarizeRescheduleResults(List<String?> codes) {
  var count = 0;
  String? errorCode;
  for (final code in codes) {
    if (code == null) {
      count++;
    } else if (errorCode != 'EXACT_ALARM_DENIED') {
      errorCode = code;
    }
  }
  return (count: count, errorCode: errorCode);
}

/// 登録し直したあとの SnackBar の文言と色（color が null なら既定の色）
/// 優先順：読めなかった → 分が 0 → エラー（AlarmService.alarmErrorMessage の文言） → 0 件 → 成功
/// - readFailed：設定・シフト・パターン・行の変換のどれかが読めなかった（スイッチは ON のまま）
/// - errorMessage：エラーのときの文言（件数は出さない）
({String text, Color? color}) rescheduleMessage({
  required int count,
  required String? errorMessage,
  required bool readFailed,
  required bool alarmDisabled,
}) {
  if (readFailed) {
    return (
      text: '⚠️ 出勤前アラームを登録し直せませんでした。もう一度 OFF → ON にするか、シフトを確定し直してください',
      color: Colors.orange,
    );
  }
  if (alarmDisabled) {
    return (text: 'ℹ️ 出勤前アラームは無効（0分）のため登録しません', color: null);
  }
  if (errorMessage != null) {
    return (text: errorMessage, color: Colors.orange);
  }
  if (count == 0) {
    return (text: 'ℹ️ 登録し直す出勤日はありません', color: null);
  }
  return (text: '✅ 出勤前アラームを $count件 登録し直しました', color: Colors.green);
}

/// 睡眠中で手動起床が有効なときに、起床アラーム（main）は戻らないことを知らせる文言
/// N123（ON に戻したとき）と N128（「アラームとリマインダー」が許可されたとき）で使う
const manualWakeNotRestoredText = '⚠️ 起床アラームは戻りません。『起きる』→『今から寝る』をやり直してください';

/// アラーム音を保存できたときの文言（N124。アラームが OFF のときもこれだけを出す）
const soundSavedText = '✅ アラーム音と音量を保存しました';

/// アラーム音を保存して pre を登録し直したあとの SnackBar（N124）。順に出す（前を消さない）
/// 優先順：読めなかった → エラー（AlarmService.alarmErrorMessage の文言） → 0 件・分が 0 → 成功
/// - 読めなかった・エラーのときは、括弧なしの ✅ のあとにオレンジの 2 本目（件数は出さない）
List<({String text, Color? color})> soundSaveMessages({
  required int count,
  required String? errorMessage,
  required bool readFailed,
  required bool alarmDisabled,
}) {
  const ({String text, Color? color}) soundSaved = (text: soundSavedText, color: null);
  if (readFailed) {
    return [
      soundSaved,
      (
        text: '⚠️ 出勤前アラームに反映できませんでした。もう一度保存するか、シフトを確定し直してください',
        color: Colors.orange,
      ),
    ];
  }
  if (errorMessage != null) {
    return [soundSaved, (text: errorMessage, color: Colors.orange)];
  }
  if (alarmDisabled || count == 0) {
    return [soundSaved];
  }
  return [(text: '$soundSavedText（出勤前アラーム $count件に反映）', color: null)];
}

/// 設定の保存で DB に書く設定（N125）
/// 元（読み直した設定）に、画面の分数・起床時刻・案内表示だけを入れる
/// 音・premium・id・createdAt は元のまま（音は「アラーム音の保存」ボタンだけで保存する）
AppSettings settingsToSave(
  AppSettings base, {
  required int alarmTimeBeforeShift,
  required String wakeUpTime,
  required bool advicePromoVisible,
}) {
  return base.copyWith(
    alarmTimeBeforeShift: alarmTimeBeforeShift,
    wakeUpTime: wakeUpTime,
    advicePromoVisible: advicePromoVisible,
  );
}

/// 設定の保存で分数が変わったときに pre に行うこと（N125）
enum PreMinutesAction {
  none,  // 分数が同じ（pre には何もしない）
  cancelAndReschedule,  // 取り消して新しい分数で登録し直す
  cancelOnly,  // 0（無効）にしたので取り消すだけ
}

/// 前の分数（DB。行がなければ 30）と新しい分数から、pre に行うことを決める（N125）
PreMinutesAction preMinutesAction(int oldMinutes, int newMinutes) {
  if (oldMinutes == newMinutes) return PreMinutesAction.none;
  return newMinutes > 0 ? PreMinutesAction.cancelAndReschedule : PreMinutesAction.cancelOnly;
}

/// 分数が変わったときに pre を取り消す日（N125）
/// - rows は shifts の行（shift_date）。today〜rangeEnd（両方含む）の日だけ、日付だけ・重複なし・日付順
///   （N180 3/3：呼び出し元は today に「昨日」を渡す）
/// - shift_date が読めない行があれば例外（読み込みの失敗として扱い、何も取り消さない。
///   飛ばすと、取り消したあとの登録し直しが同じ行で失敗し「取り消したのに登録できなかった」になるため）
List<DateTime> preAlarmCancelDates(
  List<Map<String, dynamic>> rows,
  DateTime today,
  DateTime rangeEnd,
) {
  final first = DateTime(today.year, today.month, today.day);
  final last = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
  final dates = <DateTime>{};
  for (final row in rows) {
    final parsed = DateTime.parse(row['shift_date'] as String);
    final date = DateTime(parsed.year, parsed.month, parsed.day);
    if (!date.isBefore(first) && !date.isAfter(last)) dates.add(date);
  }
  return dates.toList()..sort();
}

/// 分数を新しい分数に合わせられなかったときの文言（N125）
const preMinutesFailedText = '⚠️ 出勤前アラームを新しい分数に合わせられませんでした。もう一度保存するか、シフトを確定し直してください';

/// 設定を保存したあとの SnackBar（N125）。順に出す（前を消さない）
/// - savedText：今の成功の文言（緑）。mainAlarmError（睡眠中の main の登録に失敗）があれば、成功の文言の代わりにそれ（オレンジ）
/// - pre：none（分数が同じ・OFF）なら今の文言のまま
///   読めなかった → 括弧なしのあとに preMinutesFailedText（オレンジ）
///   エラー（AlarmService.alarmErrorMessage の文言）→ 括弧なしのあとにその文言（オレンジ）
///   取り消しのみ → 「（出勤前アラームを取り消しました）」／登録し直し n 件 → 「（出勤前アラーム n件を登録し直しました）」／0 件 → 括弧なし
/// - main の失敗のときは成功の文言を出さないので、括弧もつけない（pre の ⚠️ は続けて出す）
List<({String text, Color? color})> settingsSaveMessages({
  required String savedText,
  required String? mainAlarmError,
  required PreMinutesAction preAction,
  int preCount = 0,
  String? preErrorMessage,
  bool preReadFailed = false,
}) {
  var suffix = '';
  ({String text, Color? color})? preWarning;
  if (preAction != PreMinutesAction.none) {
    if (preReadFailed) {
      preWarning = (text: preMinutesFailedText, color: Colors.orange);
    } else if (preErrorMessage != null) {
      preWarning = (text: preErrorMessage, color: Colors.orange);
    } else if (preAction == PreMinutesAction.cancelOnly) {
      suffix = '（出勤前アラームを取り消しました）';
    } else if (preCount > 0) {
      suffix = '（出勤前アラーム $preCount件を登録し直しました）';
    }
  }
  return [
    if (mainAlarmError != null)
      (text: mainAlarmError, color: Colors.orange)
    else
      (text: '$savedText$suffix', color: Colors.green),
    if (preWarning != null) preWarning,
  ];
}
