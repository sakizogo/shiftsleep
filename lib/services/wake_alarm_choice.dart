// 睡眠に入るとき・睡眠中に設定を変えたときに、どの起床アラームを登録するか（N4・N118・N19）
//
// 手動起床のほうが早ければ、保険として出勤前アラーム（pre）も登録する（2 本）
// pre のほうが早い（同時刻を含む）ときは pre だけ
// シフトを読めなかったときは「pre なし」として渡す（手動起床で鳴らす）
// N118 2b：設定を読めなかったときは既定値で判定し、手動起床があれば必ず main も登録する
// DB・アラームには依存しない
import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/next_shift.dart';

/// 登録するアラーム
enum WakeAlarmPlan {
  none,
  mainOnly,
  preOnly,
  mainAndPre;

  bool get includesMain => this == mainOnly || this == mainAndPre;
  bool get includesPre => this == preOnly || this == mainAndPre;
}

/// 今日の欄の pre が鳴る時刻（N180 3/3：shiftStartDateTime の開始−分数。0:00〜4:59 開始は翌日に始まる）
/// 分数 0 以下・シフトなし（pattern が null）・出勤以外・出勤時刻なし・すでに過ぎた時刻 → null
DateTime? todayPreAlarmAt({
  required DateTime now,
  required int minutesBefore,
  required ShiftPatternModel? pattern,
}) {
  if (minutesBefore <= 0 || pattern == null) return null;
  final startTime = pattern.startTime;
  // ✅ N14: 出勤（work）以外のパターン（休日・有休・半休）では pre を登録しない
  if (startTime == null || pattern.patternType != ShiftType.work) return null;

  final alarmAt = shiftStartDateTime(now, startTime).subtract(Duration(minutes: minutesBefore));
  return alarmAt.isAfter(now) ? alarmAt : null;
}

/// N118 2b：今日の欄の出勤時刻（まだ先のときだけ。N180 3/3：shiftStartDateTime。0:00〜4:59 開始は翌日）
/// 出勤（work）以外・出勤時刻なし・シフトなし（pattern が null）・出勤時刻ちょうど／過ぎている → null
/// pre の時刻が過ぎているかどうかは見ない
DateTime? todayWorkStartAt({
  required DateTime now,
  required ShiftPatternModel? pattern,
}) {
  final startTime = pattern?.startTime;
  if (pattern == null || startTime == null || pattern.patternType != ShiftType.work) return null;
  final startAt = shiftStartDateTime(now, startTime);
  return startAt.isAfter(now) ? startAt : null;
}

/// 手動起床と今日の pre から、登録するアラームを決める（shiftPreAlarmAt はまだ先の pre だけを渡す）
/// keepMain：手動起床が pre より遅くても main を残す（N118 2b：設定を読めず既定値で判定したとき）
WakeAlarmPlan planWakeAlarms({
  required DateTime? manualWakeAt,
  required DateTime? shiftPreAlarmAt,
  bool keepMain = false,
}) {
  if (manualWakeAt == null) {
    return shiftPreAlarmAt == null ? WakeAlarmPlan.none : WakeAlarmPlan.preOnly;
  }
  if (shiftPreAlarmAt == null) return WakeAlarmPlan.mainOnly;
  return keepMain || manualWakeAt.isBefore(shiftPreAlarmAt) ? WakeAlarmPlan.mainAndPre : WakeAlarmPlan.preOnly;
}

/// 登録の結果
class WakeAlarmRegistrationResult {
  const WakeAlarmRegistrationResult({
    required this.now,
    required this.plan,
    this.manualWakeAt,
    this.preAlarmAt,
    this.minutesBefore = 0,
    this.mainError,
    this.preError,
    this.shiftsReadFailed = false,
    this.alarmDisabled = false,
    this.settingsReadFailed = false,
    this.patternMissing = false,
    this.todayWorkStartAt,
  });

  final DateTime now;
  final WakeAlarmPlan plan;
  final DateTime? manualWakeAt;  // 有効な手動起床（登録しなくても入れる）
  final DateTime? preAlarmAt;  // まだ先の今日の pre（登録しなくても入れる）
  final int minutesBefore;  // 出勤の何分前か（pre の時刻に足すと出勤時刻）
  final String? mainError;  // main を登録できなかったときの文言
  final String? preError;  // pre を登録できなかったときの文言
  final bool shiftsReadFailed;  // 今日のシフト・パターンを読めなかった
  final bool alarmDisabled;  // アラームが OFF なので何もしなかった
  final bool settingsReadFailed;  // N118 2b：設定を読めず、既定値で判定した
  final bool patternMissing;  // N118 2b：今日のシフトの行はあるのに、パターンが見つからない（削除済み）
  final DateTime? todayWorkStartAt;  // N118 2b：今日の出勤時刻（まだ先のときだけ）
}

/// 登録の結果から出す SnackBar（color が null なら ⏰ の案内、オレンジなら ⚠️）
/// 失敗があるときは ⚠️ だけを出し、「鳴ります」は出さない
/// N118 2b：設定を読めなかったときの ⚠️ は先頭に出す
List<({String text, Color? color})> wakeAlarmMessages(WakeAlarmRegistrationResult result) {
  if (result.alarmDisabled) return const [];

  final settingsWarning = _settingsFallbackWarning(result);
  return [
    if (settingsWarning != null) (text: settingsWarning, color: Colors.orange),
    ..._coreMessages(result),
  ];
}

/// N118 2b：設定を読めなかったときの ⚠️（出さないなら null）
/// - 1 本でも登録できた → 既定値で登録した
/// - 1 本も登録しない（none）で今日の出勤がまだ先 → 既定値の pre はもう過ぎている
/// - それ以外（登録の失敗・シフトなし）→ 出さない
String? _settingsFallbackWarning(WakeAlarmRegistrationResult result) {
  if (!result.settingsReadFailed) return null;
  final minutes = result.minutesBefore;
  final plan = result.plan;
  final registered = (plan.includesMain && result.mainError == null) ||
      (plan.includesPre && result.preError == null);
  if (registered) {
    return '⚠️ 設定を読めなかったため、既定値（出勤 $minutes 分前・デフォルト音）で登録しました';
  }
  final startAt = result.todayWorkStartAt;
  if (plan == WakeAlarmPlan.none && startAt != null) {
    final start = '${startAt.hour}:${startAt.minute.toString().padLeft(2, '0')}';
    return '⚠️ 設定を読めなかったため、既定値（出勤 $minutes 分前）で確かめましたが、'
        '今日の出勤（$start）の $minutes 分前はもう過ぎています。アラームは登録されていません';
  }
  return null;
}

List<({String text, Color? color})> _coreMessages(WakeAlarmRegistrationResult result) {
  ({String text, Color? color}) warning(String text) => (text: text, color: Colors.orange);
  ({String text, Color? color}) info(String text) => (text: text, color: null);
  String hm(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  final mainError = result.mainError;
  final preError = result.preError;
  final mainAt = result.manualWakeAt;
  final preAt = result.preAlarmAt;

  if (mainError != null && preError != null) {
    return {mainError, preError}.map(warning).toList();
  }
  if (result.plan == WakeAlarmPlan.mainAndPre) {
    if (preError != null) {
      return [warning('⚠️ 出勤前アラームを登録できませんでした。起床アラーム ${hm(mainAt!)} は登録済みです')];
    }
    if (mainError != null) {
      return [warning('⚠️ 起床アラームを登録できませんでした。出勤前アラーム ${hm(preAt!)} は登録済みです')];
    }
  }
  if (mainError != null) return [warning(mainError)];
  if (preError != null) return [warning(preError)];

  if (result.shiftsReadFailed) {
    return [
      warning(result.plan.includesMain
          ? '⚠️ シフトを読めなかったため、出勤前アラームを登録できませんでした。手動の起床アラームは登録済みです'
          : '⚠️ シフトを読めなかったため、出勤前アラームを登録できませんでした'),
    ];
  }

  // N118 2b：削除済みのパターンでは pre を登録しない（N104 と同じ）ことを知らせる
  if (result.patternMissing) {
    return [
      warning(result.plan.includesMain
          ? '⚠️ 今日のシフトのパターンが削除されているため、出勤前アラームは登録しません。起床アラームは登録済みです'
          : '⚠️ 今日のシフトのパターンが削除されているため、出勤前アラームは登録しません'),
    ];
  }

  switch (result.plan) {
    case WakeAlarmPlan.none:
      return const [];
    case WakeAlarmPlan.preOnly:
      if (mainAt == null) return [info('⏰ 出勤前アラーム ${hm(preAt!)} に鳴ります')];
      // 手動起床が pre より遅い（同時刻を含む）ので、鳴る時刻が変わる理由を知らせる
      final minutes = result.minutesBefore;
      final startAt = preAt!.add(Duration(minutes: minutes));
      return [
        info(mainAt.isBefore(startAt)
            ? '⏰ 設定した起床時刻 ${hm(mainAt)} は出勤前アラーム（$minutes分前）より遅いため、${hm(preAt)} に鳴ります'
            : '⏰ 設定した起床時刻 ${hm(mainAt)} は出社予定時刻（${hm(startAt)}）より遅いため、出勤前アラーム（$minutes分前）の ${hm(preAt)} に鳴ります'),
      ];
    case WakeAlarmPlan.mainAndPre:
      return [info('⏰ 起床アラーム ${hm(mainAt!)} と出勤前アラーム ${hm(preAt!)} に鳴ります')];
    case WakeAlarmPlan.mainOnly:
      // ✅ N18: 起床時刻が今と同じ時・分のため翌日になったことを知らせる（普通の翌日起床では出さない）
      return _isSameMinuteTomorrow(mainAt!, result.now)
          ? [info('⏰ 起床時刻 ${hm(mainAt)} は今と同じ時刻のため、明日 ${hm(mainAt)} に設定しました')]
          : const [];
  }
}

bool _isSameMinuteTomorrow(DateTime target, DateTime now) {
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  return target.hour == now.hour &&
      target.minute == now.minute &&
      target.year == tomorrow.year &&
      target.month == tomorrow.month &&
      target.day == tomorrow.day;
}
