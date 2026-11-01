// シフト管理の読み込み（N118）
//
// 読み込みに失敗した部分を覚え、失敗しているあいだは登録・保存を止める
// 空の _shiftMap のまま「シフトを確定」すると、ほかの日のシフトが全部消えるため
// DB・画面には依存しない
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/services/pattern_usage.dart';

/// 読み込みが失敗しうる部分（イベントは表示だけなので入れない）
enum ShiftLoadPart { shifts, patterns, vacation }

/// 止めたときの文言。失敗している部分がなければ null（止めない）
String? loadBlockMessage(Set<ShiftLoadPart> failed) {
  if (failed.isEmpty) return null;
  return '⚠️ シフトを読み込めていないため登録・保存できません。［再読み込み］を押してください';
}

/// 読み込みに失敗した直後の文言
String loadFailureMessage(ShiftLoadPart part, Object error) {
  final String name;
  switch (part) {
    case ShiftLoadPart.shifts:
      name = 'シフト';
    case ShiftLoadPart.patterns:
      name = 'パターン';
    case ShiftLoadPart.vacation:
      name = '有休';
  }
  return '❌ $nameの読み込みに失敗しました: $error';
}

/// shifts の行（shift_date・pattern_id）を、日付（時刻なし）→ パターンの Map にする
/// - パターンは resolvePatternForShift で決める（見つからなければ「削除済み」。N104）
/// - shift_date が読めない行があれば例外（読み込みの失敗として扱い、今の表示を残す）
Map<DateTime, ShiftPatternModel> shiftMapFromRows(
  List<Map<String, dynamic>> rows,
  List<ShiftPatternModel> patterns,
  ShiftPatternModel dayOffPattern,
) {
  final map = <DateTime, ShiftPatternModel>{};
  for (final row in rows) {
    final date = DateTime.parse(row['shift_date'] as String);
    final normalized = DateTime(date.year, date.month, date.day);
    map[normalized] = resolvePatternForShift(row['pattern_id'] as String?, patterns, dayOffPattern);
  }
  return map;
}
