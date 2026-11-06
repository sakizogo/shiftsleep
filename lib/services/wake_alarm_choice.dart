// 睡眠に入るとき・睡眠中に設定を変えたときに、どの起床アラームを登録するか（N4・N118・N19）
//
// 手動起床のほうが早ければ、保険として出勤前アラーム（pre）も登録する（2 本）
// pre のほうが早い（同時刻を含む）ときは pre だけ
// シフトを読めなかったときは「pre なし」として渡す（手動起床で鳴らす）
// DB・アラームには依存しない
import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';

/// 登録するアラーム
enum WakeAlarmPlan {
  none,
  mainOnly,
  preOnly,
  mainAndPre;

  bool get includesMain => this == mainOnly || this == mainAndPre;
  bool get includesPre => this == preOnly || this == mainAndPre;
}

/// 今日の pre が鳴る時刻
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

  final alarmAt = DateTime(now.year, now.month, now.day, startTime.hour, startTime.minute)
      .subtract(Duration(minutes: minutesBefore));
  return alarmAt.isAfter(now) ? alarmAt : null;
}

/// 手動起床と今日の pre から、登録するアラームを決める（shiftPreAlarmAt はまだ先の pre だけを渡す）
WakeAlarmPlan planWakeAlarms({
  required DateTime? manualWakeAt,
  required DateTime? shiftPreAlarmAt,
}) {
  if (manualWakeAt == null) {
    return shiftPreAlarmAt == null ? WakeAlarmPlan.none : WakeAlarmPlan.preOnly;
  }
  if (shiftPreAlarmAt == null) return WakeAlarmPlan.mainOnly;
  return manualWakeAt.isBefore(shiftPreAlarmAt) ? WakeAlarmPlan.mainAndPre : WakeAlarmPlan.preOnly;
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
}

/// 登録の結果から出す SnackBar（color が null なら ⏰ の案内、オレンジなら ⚠️）
/// 失敗があるときは ⚠️ だけを出し、「鳴ります」は出さない
List<({String text, Color? color})> wakeAlarmMessages(WakeAlarmRegistrationResult result) {
  if (result.alarmDisabled) return const [];

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
