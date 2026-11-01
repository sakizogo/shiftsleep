// パターンを使っているシフトの日付を「今日以降」と「過去」に分ける（N104）
//
// DB にも Flutter にも依存しない。shift_date（YYYY-MM-DD）と今日の日付の文字列で比べる
// 今日は「今日以降」に含める（出勤前アラームに関わるため）

/// 今日の日付を shift_date と同じ形（YYYY-MM-DD）にする（時刻は捨てる）
String dateKeyOf(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// dates：shift_date の一覧（並びは問わない）
/// firstFutureDate：今日以降でいちばん早い日（なければ null）
({int futureCount, String? firstFutureDate, int pastCount}) classifyPatternUsage(
    List<String> dates, DateTime today) {
  final todayKey = dateKeyOf(today);
  var futureCount = 0;
  var pastCount = 0;
  String? firstFutureDate;

  for (final date in dates) {
    if (date.compareTo(todayKey) >= 0) {
      futureCount++;
      if (firstFutureDate == null || date.compareTo(firstFutureDate) < 0) {
        firstFutureDate = date;
      }
    } else {
      pastCount++;
    }
  }

  return (futureCount: futureCount, firstFutureDate: firstFutureDate, pastCount: pastCount);
}
