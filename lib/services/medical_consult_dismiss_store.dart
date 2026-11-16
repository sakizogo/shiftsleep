// N202：医師への相談のすすめを［閉じる］で閉じた日時の保存（SharedPreferences）
// - 閉じてから 14 日間は出さない。14 日たって条件を満たしていればまた出す
// - 読めない・書けないときは debugPrint だけ（読めなければ閉じていない扱いで出す）
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 閉じた日時（ISO8601）のキー
const String medicalConsultDismissedAtKey = 'shiftsleep_medical_consult_dismissed_at';

/// 閉じてから出さない期間
const Duration medicalConsultHideFor = Duration(days: 14);

/// 閉じてから 14 日たっていないか（ちょうど 14 日たったら出す）
bool isMedicalConsultSnoozed(DateTime? dismissedAt, DateTime now) =>
    dismissedAt != null && now.isBefore(dismissedAt.add(medicalConsultHideFor));

class MedicalConsultDismissStore {
  /// 閉じた日時（保存がない・読めないときは null）
  static Future<DateTime?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(medicalConsultDismissedAtKey);
      return saved == null ? null : DateTime.tryParse(saved);
    } catch (e) {
      debugPrint('❌ [MedicalConsult] 閉じた日時を読めませんでした: $e');
      return null;
    }
  }

  /// 閉じた日時を保存する
  static Future<void> save(DateTime dismissedAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(medicalConsultDismissedAtKey, dismissedAt.toIso8601String());
      debugPrint('[MedicalConsult] 閉じた日時を保存: $dismissedAt');
    } catch (e) {
      debugPrint('❌ [MedicalConsult] 閉じた日時を保存できませんでした: $e');
    }
  }
}
