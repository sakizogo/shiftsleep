/// カレンダーと日付選択の範囲（N67）
/// 始まりは 2024-01-01、終わりは「今年＋2 年」の 12/31（毎年自動で延びる）
class CalendarRange {
  /// TableCalendar の firstDay・lastDay 用（table_calendar は UTC の日付で扱う）
  static DateTime get firstDayUtc => DateTime.utc(2024, 1, 1);
  static DateTime get lastDayUtc => DateTime.utc(DateTime.now().year + 2, 12, 31);

  /// showDatePicker とデータの読み込み用（ローカルの日付）
  static DateTime get firstDate => DateTime(2024, 1, 1);
  static DateTime get lastDate => DateTime(DateTime.now().year + 2, 12, 31);

  /// 日付を範囲の中に収める（showDatePicker の initialDate 用）
  static DateTime clamp(DateTime date) {
    if (date.isBefore(firstDate)) return firstDate;
    if (date.isAfter(lastDate)) return lastDate;
    return date;
  }
}