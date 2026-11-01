import 'package:shiftsleep/models/sleep_record.dart';

/// 睡眠を手で追加・修正するときの日時の決め方と保存前のチェック（N106・N107）
///
/// DB にも Flutter にも依存しない。今の時刻・既存の記録はすべて引数で受ける

/// 保存を止める理由
enum ManualSleepError {
  tooShort,  // 10 分以下
  tooLong,   // 20 時間を超える（N107）
  future,    // 起床が今より後
  overlap,   // ほかの記録と重なる
}

extension ManualSleepErrorMessage on ManualSleepError {
  String get message {
    switch (this) {
      case ManualSleepError.tooShort:
        return '⚠️ 10 分以下の睡眠は記録されません';
      case ManualSleepError.tooLong:
        return '⚠️ 20 時間を超える睡眠は記録できません';
      case ManualSleepError.future:
        return '⚠️ 未来の時刻は記録できません';
      case ManualSleepError.overlap:
        return '⚠️ ほかの睡眠記録と時間が重なっています';
    }
  }
}

class SleepRecordValidation {
  /// 入眠日を選べるのは今日から何日前までか
  static const int maxDaysBack = 30;

  /// これ以下の睡眠は記録しない（N35 で数えない長さと同じ）
  static const Duration minDurationExclusive = Duration(minutes: 10);

  /// これを超える睡眠は記録しない（N107。ちょうど 20:00 は記録できる）
  static const Duration maxSleepDuration = Duration(hours: 20);

  /// 入眠日として選べる最も古い日（今日の 30 日前の 0:00）
  static DateTime earliestBedDate(DateTime now) {
    return DateTime(now.year, now.month, now.day - maxDaysBack);
  }

  /// 入眠日として選べる最も新しい日（今日の 0:00）
  static DateTime latestBedDate(DateTime now) {
    return DateTime(now.year, now.month, now.day);
  }

  /// 入眠日が今日から 30 日前までに入っているか（時刻は見ない）
  static bool isBedDateInRange(DateTime bedDate, DateTime now) {
    final day = DateTime(bedDate.year, bedDate.month, bedDate.day);
    return !day.isBefore(earliestBedDate(now)) && !day.isAfter(latestBedDate(now));
  }

  /// スライダーの値を時・分の整数にする
  /// Slider は k / divisions * (max - min) を返すので、13 時なら 12.999999999999998 のような
  /// 値になることがある。toInt() で切り捨てると 1 つ下になるため、四捨五入する
  static int sliderValueToTimePart(double value, {required int max}) {
    return value.round().clamp(0, max);
  }

  /// 入眠日と入眠・起床の時刻から、入眠・起床の日時を決める
  /// 起床の時刻が入眠の時刻以下なら、起床日は入眠日の翌日
  static ({DateTime start, DateTime end}) resolveTimes({
    required DateTime bedDate,
    required int bedHour,
    required int bedMinute,
    required int wakeHour,
    required int wakeMinute,
  }) {
    final start = DateTime(bedDate.year, bedDate.month, bedDate.day, bedHour, bedMinute);
    final wakeNextDay = wakeHour * 60 + wakeMinute <= bedHour * 60 + bedMinute;
    final end = DateTime(
      bedDate.year,
      bedDate.month,
      bedDate.day + (wakeNextDay ? 1 : 0),
      wakeHour,
      wakeMinute,
    );
    return (start: start, end: end);
  }

  /// 既存の記録が実際に占める時間
  /// - 睡眠中の記録は DB の仮の終了時刻（翌日 7:00）ではなく「開始〜今」
  /// - 終了が開始より前の記録は、終了を +1 日として扱う（N35 と同じ）
  ///
  /// 睡眠中かどうかは N35 と同じく、記録 ID か開始時刻が一致するかで判断する。
  /// 睡眠中でなければ sleepingRecordId・sleepingStartTime は null を渡す
  static ({DateTime start, DateTime end}) occupiedRange(
    SleepRecord record, {
    required DateTime now,
    String? sleepingRecordId,
    DateTime? sleepingStartTime,
  }) {
    final start = record.sleepStartTime;
    final isSleeping = (sleepingRecordId != null && record.id == sleepingRecordId) ||
        (sleepingStartTime != null &&
            start.millisecondsSinceEpoch == sleepingStartTime.millisecondsSinceEpoch);
    if (isSleeping) {
      return (start: start, end: now);
    }

    var end = record.sleepEndTime;
    if (end.isBefore(start)) {
      end = end.add(const Duration(days: 1));
    }
    return (start: start, end: end);
  }

  /// 2 つの時間が重なるか（端がちょうど同じ時刻は重なりにしない）
  static bool overlaps(
    ({DateTime start, DateTime end}) a,
    ({DateTime start, DateTime end}) b,
  ) {
    return a.start.isBefore(b.end) && b.start.isBefore(a.end);
  }

  /// 保存前のチェック。問題なければ null
  /// 順番：10 分以下 → 20 時間超 → 未来 → 重なり
  ///
  /// excludeRecordId：重なり判定から外す記録の ID（修正のときの自分自身。N107）
  static ManualSleepError? validate({
    required DateTime start,
    required DateTime end,
    required DateTime now,
    required List<SleepRecord> existingRecords,
    String? sleepingRecordId,
    DateTime? sleepingStartTime,
    String? excludeRecordId,
  }) {
    if (end.difference(start) <= minDurationExclusive) {
      return ManualSleepError.tooShort;
    }

    // 分単位で判定する
    if (end.difference(start).inMinutes > maxSleepDuration.inMinutes) {
      return ManualSleepError.tooLong;
    }

    if (end.isAfter(now)) {
      return ManualSleepError.future;
    }

    final range = (start: start, end: end);
    for (final record in existingRecords) {
      if (excludeRecordId != null && record.id == excludeRecordId) continue;

      final occupied = occupiedRange(
        record,
        now: now,
        sleepingRecordId: sleepingRecordId,
        sleepingStartTime: sleepingStartTime,
      );
      if (overlaps(range, occupied)) {
        return ManualSleepError.overlap;
      }
    }

    return null;
  }
}
