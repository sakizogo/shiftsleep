import 'package:flutter/foundation.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/services/sleep_baseline.dart';  // N183：circularMeanOfMinutes

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

  /// SRI を計算（Week 7 A 版：メイン睡眠のみ）
  ///
  /// 24時間を1時間単位（24区間）に分割し、
  /// 連続する2日間ペアで睡眠/覚醒の一致度を計算
  ///
  /// Parameters:
  ///   - records: 過去7日間の睡眠記録（最低2日分必要）
  ///   - hourIntervals: 時間単位（デフォルト: 1時間）
  ///
  /// Returns:
  ///   -100 ～ 100 の SRI スコア
  ///   - 100に近い: 毎日同じ時刻に規則正しく寝起き
  ///   - 0近辺: 不規則（時刻がバラバラ）
  ///   - マイナス: 大きく乱れている
  static double calculateSRI(
    List<SleepRecord> records, {
    int hourIntervals = 1,
  }) {
    if (records.length < 2) return 0.0;

    // ========== Week 7 A 修正: メイン睡眠のみをフィルタリング ==========
    final primaryRecords = _filterPrimaryRecords(records);
    
    if (primaryRecords.length < 2) {
      print('[SJLSRICalculator] Not enough primary sleep records for SRI calculation');
      return 0.0;
    }
    print('[SJLSRICalculator] Filtered ${records.length} records to ${primaryRecords.length} primary records for SRI');
    // ====================================================================

    // 日付でソート（古い順）
    final sortedRecords = List<SleepRecord>.from(primaryRecords)
      ..sort((a, b) => a.bedtime.compareTo(b.bedtime));

    // 連続する2日間ペアを作成
    final List<double> pairScores = [];

    for (int i = 0; i < sortedRecords.length - 1; i++) {
      final record1 = sortedRecords[i];
      final record2 = sortedRecords[i + 1];

      final pairScore = _calculatePairConsistency(record1, record2);
      pairScores.add(pairScore);

      print('[SRI] Pair ($i → ${i + 1}): ${pairScore.toStringAsFixed(1)}%');
    }

    if (pairScores.isEmpty) return 0.0;

    // 全ペアの平均スコア
    final sri = pairScores.fold(0.0, (a, b) => a + b) / pairScores.length;

    // -100 ～ 100 の範囲に正規化
    final normalizedSRI = (sri * 2) - 100;

    print('[SJLSRICalculator] SRI = ${normalizedSRI.toStringAsFixed(1)}');

    return normalizedSRI.clamp(-100.0, 100.0);
  }

  /// 2日間ペアの一致度を計算（0～100%）
  ///
  /// 24時間を1時間単位に分割し、各時間帯で
  /// 「両方睡眠」または「両方覚醒」の状態にある確率を算出
  static double _calculatePairConsistency(
    SleepRecord record1,
    SleepRecord record2,
  ) {
    int consistentHours = 0;
    const totalHours = 24;

    for (int hour = 0; hour < totalHours; hour++) {
      final time = DateTime(2000, 1, 1, hour, 0);

      final isSleeping1 = _isSleepingAtTime(record1, time);
      final isSleeping2 = _isSleepingAtTime(record2, time);

      // 両方睡眠 または 両方覚醒 → 一致
      if (isSleeping1 == isSleeping2) {
        consistentHours++;
      }
    }

    return (consistentHours / totalHours) * 100.0;
  }

  /// 特定の時刻に睡眠状態にあるかを判定
  ///
  /// record: 睡眠記録
  /// time: 判定対象の時刻（hour:minute）
  static bool _isSleepingAtTime(SleepRecord record, DateTime time) {
    final bedtimeOfDay = Duration(hours: record.bedtime.hour, minutes: record.bedtime.minute);
    final wakeTimeOfDay = Duration(hours: record.wakeTime.hour, minutes: record.wakeTime.minute);
    final checkTimeOfDay = Duration(hours: time.hour, minutes: time.minute);

    // 睡眠が翌日にまたがるケース（例: 23:00 ～ 07:00）
    if (wakeTimeOfDay < bedtimeOfDay) {
      // 入眠～深夜0:00 または 0:00～起床時刻
      return checkTimeOfDay >= bedtimeOfDay || checkTimeOfDay < wakeTimeOfDay;
    } else {
      // 同日内の睡眠
      return checkTimeOfDay >= bedtimeOfDay && checkTimeOfDay < wakeTimeOfDay;
    }
  }

  // ========================
  // 睡眠負債計算
  // ========================

  /// 睡眠負債を計算（目標睡眠時間との差分）
  ///
  /// Week 7 A 修正: メイン睡眠のみを対象
  ///
  /// Parameters:
  ///   - records: 過去30日間の睡眠記録
  ///   - targetDailyHours: 目標睡眠時間（デフォルト: 7時間）
  ///
  /// Returns:
  ///   累積睡眠不足（Duration）
  ///   負の値 = 不足、正の値 = 余剰
  static Duration calculateSleepDebt(
    List<SleepRecord> records, {
    double targetDailyHours = 7.0,
  }) {
    if (records.isEmpty) return Duration.zero;

    // ========== Week 7 A 修正: メイン睡眠のみをフィルタリング ==========
    final primaryRecords = _filterPrimaryRecords(records);
    
    if (primaryRecords.isEmpty) {
      return Duration.zero;
    }
    // ====================================================================

    int totalDebtMinutes = 0;

    for (final record in primaryRecords) {
      final sleepDuration = record.wakeTime.difference(record.bedtime);
      
      // 翌日にまたがる場合の処理
      if (sleepDuration.isNegative) {
        totalDebtMinutes += (sleepDuration.inMinutes + 24 * 60);
      } else {
        totalDebtMinutes += sleepDuration.inMinutes;
      }
    }

    final targetTotalMinutes = (targetDailyHours * 60 * primaryRecords.length).toInt();
    final debtMinutes = totalDebtMinutes - targetTotalMinutes;

    return Duration(minutes: debtMinutes);
  }

  // ========== Week 7 A 追加: メイン睡眠のみをフィルタリングするメソッド ==========
  /// 睡眠記録からメイン睡眠（primary）のみを抽出
  /// 
  /// 補助睡眠（supplementary）や分割睡眠（split_segment）は除外
  /// 
  /// Returns:
  ///   SleepRole が 'primary' の記録リスト
  static List<SleepRecord> _filterPrimaryRecords(List<SleepRecord> records) {
    return records
        .where((record) => record.sleepRole == SleepRole.primary)
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