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

/// 部分の名前（N118 4/4：loadFailureMessage・loadBatchNotice で共用）
String loadPartName(ShiftLoadPart part) {
  switch (part) {
    case ShiftLoadPart.shifts:
      return 'シフト';
    case ShiftLoadPart.patterns:
      return 'パターン';
    case ShiftLoadPart.vacation:
      return '有休';
  }
}

/// 読み込みに失敗した直後の文言（単独で読んだとき）
String loadFailureMessage(ShiftLoadPart part, Object error) {
  return '❌ ${loadPartName(part)}の読み込みに失敗しました: $error';
}

/// N118 4/4：まとめて読んだあとに出す 1 つの知らせ。出すものがなければ null
/// - 1 つずつ出すと、あとの SnackBar が前の SnackBar を消すため、失敗した部分と衝突の知らせを 1 つにまとめる
/// - failed：失敗した部分（シフト・パターン・有休の順に並べ直す）
/// - eventsFailed：イベントの読み込みに失敗したか（最後に並べる。登録・保存は止めないので failed には入れない）
/// - mergeNotice：draftMergeNotice の文言（なければ null）
/// - エラーの中身は入れない（ログに出す）
/// - イベントだけの失敗ではバナーも［再読み込み］も出ないので、［再読み込み］の文は入れない
/// - 失敗があれば赤（isError）。表示時間は衝突の知らせがあれば 6 秒、なければ 4 秒
({String text, bool isError, int seconds})? loadBatchNotice(
  Set<ShiftLoadPart> failed, {
  bool eventsFailed = false,
  String? mergeNotice,
}) {
  final names = [
    for (final part in ShiftLoadPart.values)
      if (failed.contains(part)) loadPartName(part),
    if (eventsFailed) 'イベント',
  ];
  if (names.isEmpty) {
    return mergeNotice == null ? null : (text: mergeNotice, isError: false, seconds: 6);
  }
  final reload = failed.isEmpty ? '' : '。［再読み込み］を押してください';
  final failure = '❌ ${names.join('・')}を読み込めませんでした$reload';
  return (
    text: mergeNotice == null ? failure : '$failure\n$mergeNotice',
    isError: true,
    seconds: mergeNotice == null ? 4 : 6,
  );
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
