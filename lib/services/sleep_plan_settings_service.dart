// 睡眠の目安の任意の設定（A-4 1/3）：通勤（片道）・身支度・パターンごとのいつもの残業
//
// SharedPreferences に分の数で保存する（D74）。どれも任意で、未設定なら今までと同じ目安になる
// - 選べる値は D76 のものだけ。読めない・壊れた・選べない値は未設定にして、debugPrint にだけ出す
// - 残業はパターンの ID → 分の JSON。消えたパターンの分は、読み込み側（SleepPlanLoader）で外す
// - 保存できなかったときは例外を外に出す（呼び出し側は「⚠️ 保存できませんでした」だけを出し、$e は入れない）
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// D76：通勤（片道）で選べる分（10〜120 分、10 分刻み）
final List<int> commuteMinuteChoices = [for (var m = 10; m <= 120; m += 10) m];

/// D76：身支度で選べる分（10〜90 分、10 分刻み）
final List<int> prepMinuteChoices = [for (var m = 10; m <= 90; m += 10) m];

/// D76：いつもの残業で選べる分（30 分〜4 時間、30 分刻み）
final List<int> overtimeMinuteChoices = [for (var m = 30; m <= 240; m += 30) m];

/// 読み込んだ設定（未設定は null・空の Map）
class SleepPlanSettings {
  /// 通勤（片道。行き・帰りの両方に使う。D75）
  final Duration? commute;

  /// 身支度
  final Duration? prep;

  /// パターンの ID → いつもの残業（残業なしのパターンは入らない）
  final Map<String, Duration> overtimeByPattern;

  const SleepPlanSettings({this.commute, this.prep, this.overtimeByPattern = const {}});

  /// 何も設定していない
  static const SleepPlanSettings none = SleepPlanSettings();
}

class SleepPlanSettingsService {
  /// 保存のキー
  static const String commuteKey = 'shiftsleep_commute_minutes';
  static const String prepKey = 'shiftsleep_prep_minutes';
  static const String overtimeKey = 'shiftsleep_overtime_minutes';

  /// 設定を読む。読めないものは未設定
  static Future<SleepPlanSettings> load() async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('❌ [SleepPlanSettings] 通勤・身支度・残業の設定を読めなかったため、未設定にします: $e');
      return SleepPlanSettings.none;
    }
    return SleepPlanSettings(
      commute: _readMinutes(prefs, commuteKey, commuteMinuteChoices),
      prep: _readMinutes(prefs, prepKey, prepMinuteChoices),
      overtimeByPattern: _readOvertime(prefs),
    );
  }

  static Duration? _readMinutes(SharedPreferences prefs, String key, List<int> choices) {
    try {
      final value = prefs.get(key);
      if (value == null) return null;
      if (value is int && choices.contains(value)) return Duration(minutes: value);
      debugPrint('⚠️ [SleepPlanSettings] $key が選べない値のため未設定にします: $value');
      return null;
    } catch (e) {
      debugPrint('❌ [SleepPlanSettings] $key を読めなかったため未設定にします: $e');
      return null;
    }
  }

  static Map<String, Duration> _readOvertime(SharedPreferences prefs) {
    try {
      final value = prefs.get(overtimeKey);
      if (value == null) return const {};
      final decoded = value is String ? jsonDecode(value) : null;
      if (decoded is! Map) {
        debugPrint('⚠️ [SleepPlanSettings] 残業の設定が壊れているため未設定にします: $value');
        return const {};
      }
      final result = <String, Duration>{};
      for (final entry in decoded.entries) {
        final minutes = entry.value;
        if (entry.key is String && minutes is int && overtimeMinuteChoices.contains(minutes)) {
          result[entry.key as String] = Duration(minutes: minutes);
        } else {
          debugPrint('⚠️ [SleepPlanSettings] 残業の設定の選べない値を外します: ${entry.key} → $minutes');
        }
      }
      return result;
    } catch (e) {
      debugPrint('❌ [SleepPlanSettings] 残業の設定を読めなかったため未設定にします: $e');
      return const {};
    }
  }

  /// 通勤を保存する（null で未設定に戻す）。選べない値・保存できなければ例外
  static Future<void> saveCommute(Duration? commute) =>
      _saveMinutes(commuteKey, commute, commuteMinuteChoices);

  /// 身支度を保存する（null で未設定に戻す）。選べない値・保存できなければ例外
  static Future<void> savePrep(Duration? prep) => _saveMinutes(prepKey, prep, prepMinuteChoices);

  static Future<void> _saveMinutes(String key, Duration? value, List<int> choices) async {
    if (value != null && !choices.contains(value.inMinutes)) {
      throw ArgumentError.value(value, key, '選べない値です');
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = value == null ? await prefs.remove(key) : await prefs.setInt(key, value.inMinutes);
    if (!saved) throw StateError('$key を保存できませんでした');
  }

  /// パターンのいつもの残業を保存する（null で残業なしに戻す）。選べない値・保存できなければ例外
  /// - ほかのパターンの残業は、読めたものだけを残す（壊れていた分は消える）
  static Future<void> saveOvertime(String patternId, Duration? overtime) async {
    if (overtime != null && !overtimeMinuteChoices.contains(overtime.inMinutes)) {
      throw ArgumentError.value(overtime, overtimeKey, '選べない値です');
    }
    final prefs = await SharedPreferences.getInstance();
    final map = {
      for (final entry in _readOvertime(prefs).entries) entry.key: entry.value.inMinutes,
    };
    if (overtime == null) {
      map.remove(patternId);
    } else {
      map[patternId] = overtime.inMinutes;
    }
    final saved = map.isEmpty ? await prefs.remove(overtimeKey) : await prefs.setString(overtimeKey, jsonEncode(map));
    if (!saved) throw StateError('$overtimeKey を保存できませんでした');
  }
}
