// 寝方のタイプの設定の保存（A-2 4/4・D9）
//
// SharedPreferences に enum の名前（auto／immediate／lastMinute）で保存する（D47）
// 読めなかったとき（例外・値がない・知らない値）は auto にして、debugPrint にだけ出す（D48）
// 保存できなかったときは例外を外に出す（呼び出し側は「⚠️ 保存できませんでした」だけを出し、$e は入れない）
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/services/sleep_plan.dart';

class SleepStylePreferenceService {
  /// 保存のキー
  static const String key = 'shiftsleep_sleep_style_preference';

  /// 設定を読む。読めなければ auto
  static Future<SleepStylePreference> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(key);
      if (value == null) return SleepStylePreference.auto;
      for (final preference in SleepStylePreference.values) {
        if (preference.name == value) return preference;
      }
      debugPrint('⚠️ [SleepStylePreference] 知らない値のため auto にします: $value');
      return SleepStylePreference.auto;
    } catch (e) {
      debugPrint('❌ [SleepStylePreference] 寝方のタイプの設定を読めなかったため auto にします: $e');
      return SleepStylePreference.auto;
    }
  }

  /// 設定を保存する。保存できなければ例外
  static Future<void> save(SleepStylePreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(key, preference.name);
    if (!saved) {
      throw StateError('寝方のタイプの設定を保存できませんでした（${preference.name}）');
    }
  }
}
