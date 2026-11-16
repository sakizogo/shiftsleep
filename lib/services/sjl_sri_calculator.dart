import 'package:flutter/foundation.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/sleep_baseline.dart';  // N183：circularMeanOfMinutes
import 'package:shiftsleep/services/sleep_debt.dart';  // N198：recentSleepDebt
import 'package:shiftsleep/services/sleep_record_kind.dart';  // N184：isMainSleepRecord・recentDailySleepTotals

/// SJL（Social Jetlag / ソーシャル・ジェットラグ）と
/// SRI（Sleep Regularity Index / 睡眠規則正しさ指数）を計算するエンジン
///
/// Week 7 A 修正:
/// - メイン睡眠（primary）のみを使用して計算
/// - 昼寝（supplementary）や分割睡眠（split_segment）は除外
///
/// 参考: 神奈川県立保健福祉大学 機関リポジトリ
/// - SJL: 休日と平日の睡眠中点（中央時刻）の差
/// - SRI: 24時間を細かい時間単位に分割し、連続2日間の一致度を算出
class SJLSRICalculator {
  /// N197：SJL を計算するのに必要なメイン睡眠の件数（過去 7 日）。N196 A：SJL 専用（SRI は sriMinComparedMinutes）
  static const int minMainRecordsForSjl = 5;

  /// N196 A：SRI で見る期間（now − 7 日〜now）
  static const Duration sriWindow = Duration(days: 7);

  /// N196 A：SRI を計算するのに必要な、比べた時間（4 日分。ちょうどを含む）
  static const int sriMinComparedMinutes = 4 * 24 * 60;

  // ========================
  // SJL（社会的時差）計算
  // ========================

  /// SJL を計算（Week 7 A 版：メイン睡眠のみ）
  /// 
  /// Parameters:
  ///   - records: 過去7日間の睡眠記録（最低5日分必要）
  ///   - weekdayCount: 平日の日数（デフォルト: 5日 = 月～金）
  ///   - weekendCount: 休日の日数（デフォルト: 2日 = 土日）
  ///
  /// Returns:
  ///   平日と休日の睡眠中点の差（時間単位）
  ///   - 0 ～ 1時間  : 正常範囲
  ///   - 1 ～ 2時間  : やや乱れている
  ///   - 2時間以上   : 大きく乱れている
  ///   N183：計算できないときは null（記録がない・平日か休日が 0 件・中点がばらばらで円周平均が出せない）
  ///   中点は円周平均（circularMeanOfMinutes）、差は 0:00 をまたいで短いほう（最大 12 時間）
  static double? calculateSJL(
    List<SleepRecord> records, {
    int weekdayCount = 5,
    int weekendCount = 2,
  }) {
    if (records.isEmpty) return null;

    // ========== Week 7 A 修正: メイン睡眠のみをフィルタリング ==========
    // 補助睡眠（nap）や分割睡眠（split_segment）を除外
    final primaryRecords = _filterPrimaryRecords(records);

    if (primaryRecords.isEmpty) {
      print('[SJLSRICalculator] No primary sleep records found');
      return null;
    }
    print('[SJLSRICalculator] Filtered ${records.length} records to ${primaryRecords.length} primary records');
    // ====================================================================

    // 過去7日間のデータから平日・休日を分類
    final List<SleepRecord> weekdayRecords = [];
    final List<SleepRecord> weekendRecords = [];

    for (final record in primaryRecords) {
      final dayOfWeek = record.bedtime.weekday;
      // weekday: 1=Monday, 7=Sunday
      if (dayOfWeek >= 1 && dayOfWeek <= 5) {
        weekdayRecords.add(record);
      } else {
        weekendRecords.add(record);
      }
    }

    // 平日と休日のそれぞれで睡眠中点を計算
    final weekdayMidpoint = _calculateAverageSleepMidpoint(weekdayRecords);
    final weekendMidpoint = _calculateAverageSleepMidpoint(weekendRecords);

    // 睡眠中点の差（0:00 をまたいで短いほう）= SJL
    if (weekdayMidpoint == null || weekendMidpoint == null) {
      debugPrint('[SJLSRICalculator] N183：SJL を計算できません'
          '（平日 ${weekdayRecords.length} 件・休日 ${weekendRecords.length} 件。0 件か、中点がばらばら）');
      return null;
    }

    final sjl = circularMinuteDistance(weekdayMidpoint, weekendMidpoint) / 60;

    debugPrint('[SJLSRICalculator] SJL = $sjl h'
        '（平日 ${weekdayRecords.length} 件・中点 ${_formatMinuteOfDay(weekdayMidpoint)}、'
        '休日 ${weekendRecords.length} 件・中点 ${_formatMinuteOfDay(weekendMidpoint)}）');

    return sjl;
  }

  /// N183：時刻（0:00 からの分）どうしの差。0:00 をまたいで短いほう（0〜720）
  /// - 例：23:30 と 0:30 は 60 分（23 時間ではない）
  static int circularMinuteDistance(int a, int b) {
    const minutesPerDay = 24 * 60;
    final d = (a - b).abs() % minutesPerDay;
    return d <= minutesPerDay - d ? d : minutesPerDay - d;
  }

  static String _formatMinuteOfDay(int minutes) =>
      '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

  /// 単一記録の睡眠中点（中央時刻）を計算
  ///
  /// 例: 入眠 23:00, 起床 07:00 → 睡眠中点 03:00
  static DateTime? _getSleepMidpoint(SleepRecord record) {
    try {
      final bedtime = record.bedtime;
      final wakeTime = record.wakeTime;

      // 起床時刻が入眠時刻より前の場合（翌日のケース）を処理
      DateTime adjustedWakeTime = wakeTime;
      if (wakeTime.isBefore(bedtime)) {
        adjustedWakeTime = wakeTime.add(Duration(days: 1));
      }

      final midpoint = bedtime.add(
        adjustedWakeTime.difference(bedtime) ~/ 2,
      );

      return midpoint;
    } catch (e) {
      print('[Error] Failed to calculate sleep midpoint: $e');
      return null;
    }
  }

  /// 複数記録から平均的な睡眠中点を計算
  /// N183：時刻（0:00 からの分）の円周平均。記録がない・ばらばら（R が 0.1 未満）なら null
  static int? _calculateAverageSleepMidpoint(List<SleepRecord> records) {
    final midpoints = records
        .map(_getSleepMidpoint)
        .whereType<DateTime>()
        .map((time) => time.hour * 60 + time.minute);

    return circularMeanOfMinutes(midpoints)?.minuteOfDay;
  }

  // ========================
  // SRI（睡眠規則正しさ指数）計算
  // ========================

  /// SRI を計算（N196 A：昼寝も含めたすべての睡眠で、24 時間ごとに比べる）
  ///
  /// - 期間は now − 7 日〜now。記録中の睡眠があれば（recordingStart）、その開始までにする
  /// - 1 分ごとに「寝ている／起きている」を決め、時刻 t と t + 24 時間を比べる
  /// - 寝ているかは、記録中・途中で終わった記録を除くすべての睡眠の実際の日時で決める（0:00 をまたいでもよい。重なりは 1 回）
  /// - 記録のない日（起床の日付に記録がない暦日）が関わる組は比べない（押し忘れの日を「起きていた」と数えない）
  /// - 比べた時間が sriMinComparedMinutes（4 日分）未満なら null
  ///
  /// Returns:
  ///   -100 ～ 100 の SRI スコア（200 × 一致した分 ÷ 比べた分 − 100）
  ///   - 100に近い: 毎日同じ時刻に規則正しく寝起き
  ///   - 0近辺: 不規則（時刻がバラバラ）
  ///   - マイナス: 大きく乱れている
  static double? calculateSRI(
    List<SleepRecord> records, {
    DateTime? now,
    DateTime? recordingStart,
  }) {
    const minutesPerDay = 24 * 60;
    final windowEndNow = now ?? DateTime.now();
    final windowStart = windowEndNow.subtract(sriWindow);
    var windowEnd = windowEndNow;
    if (recordingStart != null && recordingStart.isBefore(windowEnd)) {
      windowEnd = recordingStart.isBefore(windowStart) ? windowStart : recordingStart;
    }
    final length = windowEnd.difference(windowStart).inMinutes;

    final finished = records.where((r) => !isUnfinishedSleepRecord(r)).toList();
    final recordedDays = finished.map(sleepRecordWakeDay).toSet();

    // 1 分ごとの「寝ている」
    final asleep = List<bool>.filled(length < 0 ? 0 : length, false);
    for (final record in finished) {
      final from = record.sleepStartTime.difference(windowStart).inMinutes;
      final to = sleepRecordEnd(record).difference(windowStart).inMinutes;
      for (var i = from < 0 ? 0 : from; i < to && i < asleep.length; i++) {
        asleep[i] = true;
      }
    }

    // 1 分ごとの「記録のある日か」
    final valid = List<bool>.generate(asleep.length, (i) {
      final time = windowStart.add(Duration(minutes: i));
      return recordedDays.contains(DateTime(time.year, time.month, time.day));
    });

    var compared = 0;
    var matched = 0;
    for (var i = 0; i + minutesPerDay < asleep.length; i++) {
      if (!valid[i] || !valid[i + minutesPerDay]) continue;
      compared++;
      if (asleep[i] == asleep[i + minutesPerDay]) matched++;
    }

    if (compared < sriMinComparedMinutes) {
      debugPrint('[SJLSRICalculator] N196 A：SRI を計算できません'
          '（比べた時間 $compared 分。$sriMinComparedMinutes 分以上が必要）');
      return null;
    }

    final sri = 200 * matched / compared - 100;
    debugPrint('[SJLSRICalculator] SRI = ${sri.toStringAsFixed(1)}（比べた $compared 分・一致 $matched 分）');
    return sri.clamp(-100.0, 100.0);
  }

  // ========================
  // 睡眠負債計算
  // ========================

  /// 睡眠負債を計算（目標睡眠時間との差分）
  ///
  /// N184 2/2：1 日ごと（起床の日付）に「その日の合計 − 目標」を出し、直近 4 週間ぶん足す
  /// - その日の合計はメイン＋昼寝（記録中は除く）
  /// - 記録のない日は数えない
  /// N198：寝すぎた日の余りは 1 日 +1 時間まで。1 日平均の差で評価する（sleep_debt.dart の recentSleepDebt）
  ///
  /// Parameters:
  ///   - records: 睡眠記録（直近 4 週間＝today − 27 〜 today の日だけ使う）
  ///   - now: 今の時刻（省略すると DateTime.now()）
  ///
  /// Returns:
  ///   N198：記録のある日が 7 日未満なら null（計算できない）
  static SleepDebtSummary? calculateSleepDebt(
    List<SleepRecord> records, {
    DateTime? now,
  }) {
    return recentSleepDebt(records, now ?? DateTime.now());
  }

  // ========== Week 7 A 追加: メイン睡眠のみをフィルタリングするメソッド ==========
  /// 睡眠記録からメイン睡眠（primary）のみを抽出
  /// 
  /// 補助睡眠（supplementary）や分割睡眠（split_segment）は除外
  /// 
  /// Returns:
  ///   N184：長さが 5 時間以上の記録リスト（SleepRole は見ない。記録中は除く）
  static List<SleepRecord> _filterPrimaryRecords(List<SleepRecord> records) {
    return records
        .where(isMainSleepRecord)
        .toList();
  }
  // ========================================================================

  /// 過去7日間のデータを取得（テスト用）
  static List<SleepRecord> getLast7DaysData(List<SleepRecord> allRecords) {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(Duration(days: 7));

    return allRecords
        .where((record) => record.bedtime.isAfter(sevenDaysAgo))
        .toList();
  }
}