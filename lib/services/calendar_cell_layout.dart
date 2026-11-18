// N51 F（L2）：シフト管理のカレンダーの、文字の倍率に合わせた高さ
import 'dart:math' as math;

/// マスの中の文字の倍率の上限（D2：これより大きくしない。見出しと曜日には上限をつけない）
const double calendarCellMaxTextScale = 1.3;

/// 1 週の行の高さ。1.0 倍以下は今までどおり 75
///
/// マスの中は、大きくならない部分（上の余白 3・間 2・シフト名の枠 20・有休の枠 16 の計 41）と、
/// 文字の行（日付・イベント。1.0 倍で 34）でできている。文字の行だけ倍率（上限 1.3）で伸ばす
double calendarRowHeight(double textScale) {
  final scale = textScale.clamp(1.0, calendarCellMaxTextScale).toDouble();
  return (41 + 34 * scale).ceilToDouble();
}

/// 曜日の行の高さ。1.0 倍以下は table_calendar の既定の 16。上限はつけない
double calendarDaysOfWeekHeight(double textScale) {
  final scale = math.max(textScale, 1.0);
  return (16 + 18 * (scale - 1)).ceilToDouble();
}
