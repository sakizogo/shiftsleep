// 期間指定（範囲指定タブ）の登録が途中で失敗したときの文言（N93）
//
// 失敗した日で止め、それまでの日は残す（N68 で同じ日は上書きなので、同じ期間を登録し直せば続きが入る）
// DB・画面には依存しない。日付は M/d で出す（年・時刻は出さない）

/// 日付を M/d にする（例：11/6）
String _monthDay(DateTime date) => '${date.month}/${date.day}';

/// 期間指定で失敗したときの SnackBar の文言
/// - lastSucceeded が null（1 日目で失敗・何も登録していない）→ ❌
/// - lastSucceeded が開始日と同じ日（2 日目で失敗）→ ⚠️「11/1 は登録しました。…」
/// - それ以外 → ⚠️「11/1〜11/5 は登録しました。…」
String rangeApplyFailureMessage(
  DateTime start,
  DateTime? lastSucceeded,
  DateTime failed,
  Object error,
) {
  if (lastSucceeded == null) {
    return '❌ 期間指定に失敗しました: $error';
  }
  final isSameDay = start.year == lastSucceeded.year &&
      start.month == lastSucceeded.month &&
      start.day == lastSucceeded.day;
  final registered = isSameDay
      ? _monthDay(start)
      : '${_monthDay(start)}〜${_monthDay(lastSucceeded)}';
  return '⚠️ $registered は登録しました。${_monthDay(failed)} で失敗したため、以降は登録していません: $error';
}
