// ホームの睡眠プランのカードのための読み込み（A-3 1/3）
//
// 勤務（今日−2〜今日+6）・パターン・設定（出勤前の分数）・寝方のタイプを読む（D56）
// - 勤務・パターンが読めない：shifts を null にする（カードは目安を出さず ⚠️ と［再読み込み］。D62）
// - 設定が読めない：30 分で計算し、settingsFailed を立てる（カードは ⚠️ を 1 行。D61）。行がないときは 30 分（失敗ではない）
// - 寝方のタイプ：SleepStylePreferenceService（読めなければ auto。画面には出さない）
// - A-4 1/3：通勤・身支度・パターンごとのいつもの残業（SleepPlanSettingsService。読めなければ未設定。消えたパターンの残業は外す）
// - A-4 1/3（D83）：ベースライン用の勤務は今日−29〜今日+6 で別に読む（読めなければ目安用の一覧を使う）
// 睡眠記録は SleepProvider.last30DaysRecords を使うので、ここでは読まない（D55）
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/services/next_shift.dart';
import 'package:shiftsleep/services/pre_alarm_reschedule_service.dart';
import 'package:shiftsleep/services/shift_load.dart';
import 'package:shiftsleep/services/sleep_plan.dart';
import 'package:shiftsleep/services/sleep_plan_settings_service.dart';
import 'package:shiftsleep/services/sleep_style_preference_service.dart';

/// 出勤前の分数の既定（設定の行がない・読めないとき。AppSettings の既定と同じ）
const int defaultAlarmMinutesBefore = 30;

/// 読み込んだもの
class SleepPlanInputs {
  /// 勤務（workShiftsFromMap の結果）。読めなかったら null
  final List<WorkShift>? shifts;

  /// 出勤前の分数（読めなかった・行がないときは 30）
  final int alarmMinutesBefore;

  /// 設定を読めなかった（30 分で計算している）
  final bool settingsFailed;

  /// 寝方のタイプの設定
  final SleepStylePreference preference;

  /// D83：ベースライン用の勤務（今日−29〜今日+6）。null なら shifts を使う
  final List<WorkShift>? baselineShifts;

  /// A-4 1/3：通勤（片道）・身支度（未設定は null）
  final Duration? commute;
  final Duration? prep;

  /// A-4 1/3：パターンの ID → いつもの残業（今あるパターンの分だけ）
  final Map<String, Duration> overtimeByPattern;

  const SleepPlanInputs({
    required this.shifts,
    required this.alarmMinutesBefore,
    required this.settingsFailed,
    required this.preference,
    this.baselineShifts,
    this.commute,
    this.prep,
    this.overtimeByPattern = const {},
  });

  /// 勤務・パターンを読めなかった
  bool get shiftsFailed => shifts == null;

  /// 目安の計算に渡す設定
  SleepPlanOptions get planOptions => SleepPlanOptions(
        alarmMinutesBefore: alarmMinutesBefore,
        commute: commute,
        prep: prep,
        overtimeByPattern: overtimeByPattern,
      );

  /// 寝方のタイプだけを変えたもの（カードのシートで選んだとき）
  SleepPlanInputs withPreference(SleepStylePreference preference) => SleepPlanInputs(
        shifts: shifts,
        alarmMinutesBefore: alarmMinutesBefore,
        settingsFailed: settingsFailed,
        preference: preference,
        baselineShifts: baselineShifts,
        commute: commute,
        prep: prep,
        overtimeByPattern: overtimeByPattern,
      );
}

/// 勤務・パターン・設定・寝方のタイプを読む
class SleepPlanLoader {
  SleepPlanLoader({
    ShiftRepository? shiftRepository,
    Future<SleepStylePreference> Function()? loadPreference,
    Future<SleepPlanSettings> Function()? loadPlanSettings,
  })  : _shiftRepository = shiftRepository ?? ShiftRepository(),
        _loadPreference = loadPreference ?? SleepStylePreferenceService.load,
        _loadPlanSettings = loadPlanSettings ?? SleepPlanSettingsService.load;

  final ShiftRepository _shiftRepository;
  final Future<SleepStylePreference> Function() _loadPreference;
  final Future<SleepPlanSettings> Function() _loadPlanSettings;

  static const String _userId = 'test_user';

  /// 勤務を読む範囲の始まり（今日−2。0:00〜4:59 開始の勤務は前日の欄に登録するため、前の勤務の欄は 1 日前になる）
  static DateTime rangeStart(DateTime now) => DateTime(now.year, now.month, now.day - 2);

  /// 勤務を読む範囲の終わり（今日+6。3 日分に 5 日先まで要り、5 日目の 0:00 開始は 6 日目の欄に入るため）
  static DateTime rangeEnd(DateTime now) => DateTime(now.year, now.month, now.day + 6);

  /// D83：ベースライン用の勤務を読む範囲の始まり（今日−29。28 日分の記録の勤務明けを拾うため。終わりは rangeEnd）
  static DateTime baselineRangeStart(DateTime now) => DateTime(now.year, now.month, now.day - 29);

  Future<SleepPlanInputs> load(DateTime now) async {
    // D83：ベースライン用（広い範囲）。読めなければ目安用の一覧を使う（目安は出せるので失敗とはしない）
    List<WorkShift>? baselineShifts;
    try {
      final rows = await _shiftRepository.getShiftsForDateRange(baselineRangeStart(now), rangeEnd(now));
      final patterns = await _shiftRepository.getAllPatterns();
      baselineShifts = workShiftsFromMap(shiftMapFromRows(rows, patterns, PreAlarmRescheduleService.dayOffPattern));
    } catch (e) {
      debugPrint('❌ [SleepPlanLoader] ベースライン用のシフトを読めなかったため、目安用の範囲で数えます: $e');
    }

    List<WorkShift>? shifts;
    Set<String> patternIds = const {};
    try {
      final rows = await _shiftRepository.getShiftsForDateRange(rangeStart(now), rangeEnd(now));
      final patterns = await _shiftRepository.getAllPatterns();
      final map = shiftMapFromRows(rows, patterns, PreAlarmRescheduleService.dayOffPattern);
      shifts = workShiftsFromMap(map);
      patternIds = {for (final pattern in patterns) pattern.id};
    } catch (e) {
      debugPrint('❌ [SleepPlanLoader] シフト・パターンを読めませんでした: $e');
      shifts = null;
    }

    var alarmMinutesBefore = defaultAlarmMinutesBefore;
    var settingsFailed = false;
    try {
      final settings = await _shiftRepository.getAppSettings(_userId);
      alarmMinutesBefore = settings?.alarmTimeBeforeShift ?? defaultAlarmMinutesBefore;
    } catch (e) {
      debugPrint('❌ [SleepPlanLoader] 設定を読めなかったため、出勤 $defaultAlarmMinutesBefore 分前で計算します: $e');
      settingsFailed = true;
    }

    final preference = await _loadPreference();

    // A-4 1/3：任意の設定（サービスは例外を出さないが、差し替えたものが出しても未設定にする）
    var planSettings = SleepPlanSettings.none;
    try {
      planSettings = await _loadPlanSettings();
    } catch (e) {
      debugPrint('❌ [SleepPlanLoader] 通勤・身支度・残業の設定を読めなかったため、未設定で計算します: $e');
    }
    // 消えたパターンの残業は外す
    final overtimeByPattern = {
      for (final entry in planSettings.overtimeByPattern.entries)
        if (patternIds.contains(entry.key)) entry.key: entry.value,
    };

    return SleepPlanInputs(
      shifts: shifts,
      alarmMinutesBefore: alarmMinutesBefore,
      settingsFailed: settingsFailed,
      preference: preference,
      baselineShifts: shifts == null ? null : baselineShifts,
      commute: planSettings.commute,
      prep: planSettings.prep,
      overtimeByPattern: overtimeByPattern,
    );
  }
}
