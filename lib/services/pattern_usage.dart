import 'package:shiftsleep/models/shift_pattern_model.dart';

// パターンを使っているシフトの日付を「今日以降」と「過去」に分ける（N104）
// シフトの pattern_id からパターンを決める（見つからなければ「削除済み」。N104）
//
// DB には依存しない。shift_date（YYYY-MM-DD）と今日の日付の文字列で比べる
// 今日は「今日以降」に含める（出勤前アラームに関わるため）

/// N15 の古い休日 ID（DB の既定の行）。shifts に入っていたら、今までどおり休日として扱う
const String legacyDayOffPatternId = 'default_off_day';

/// シフトの pattern_id からパターンを決める
/// - pattern_id が null・古い休日 ID → 休日（dayOffPattern。今までの orElse と同じ）
/// - patterns（既定パターンを含む）に見つかる → そのパターン
/// - 見つからない → 「削除済み」の仮パターン（id は元の pattern_id のまま）
ShiftPatternModel resolvePatternForShift(
  String? patternId,
  List<ShiftPatternModel> patterns,
  ShiftPatternModel dayOffPattern,
) {
  if (patternId == null || patternId == legacyDayOffPatternId) return dayOffPattern;
  for (final pattern in patterns) {
    if (pattern.id == patternId) return pattern;
  }
  return ShiftPatternModel.deleted(patternId);
}

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
