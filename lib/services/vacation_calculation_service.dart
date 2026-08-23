import 'package:shiftsleep/models/vacation_model.dart';

/// 有給付与スケジュールの自動計算サービス
/// 
/// 入社日から、6ヶ月ごとの付与日と付与日数を自動計算します
class VacationCalculationService {
  
  /// 入社日から、今日までの全ての付与スケジュールを計算
  /// 
  /// 例：
  /// ```
  /// final hiredDate = DateTime(2020, 4, 1);  // 2020年4月1日
  /// final accruals = VacationCalculationService.calculateAccrualSchedule(hiredDate);
  /// // → 2020年10月1日、2021年4月1日、2021年10月1日、... の付与を自動計算
  /// ```
  static List<AccrualScheduleItem> calculateAccrualSchedule(DateTime hiredDate) {
    final schedule = <AccrualScheduleItem>[];
    
    // 初回付与日：入社日の6ヶ月後（180日後）
    var currentAccrualDate = hiredDate.add(const Duration(days: 180));
    
    // 現在までの全ての付与を追加
    while (currentAccrualDate.isBefore(DateTime.now()) || 
           currentAccrualDate.isAtSameMomentAs(DateTime.now())) {
      
      // この付与タイミングでの日数を計算
      final daysGranted = _calculateDaysAtAccrual(hiredDate, currentAccrualDate);
      
      // 失効日を計算（付与から2年後）
      final expiryDate = currentAccrualDate.add(const Duration(days: 730));
      
      schedule.add(
        AccrualScheduleItem(
          accrualDate: currentAccrualDate,
          daysGranted: daysGranted,
          expiryDate: expiryDate,
          yearsAtAccrual: _yearsAtAccrual(hiredDate, currentAccrualDate),
        ),
      );
      
      // 次の付与日（6ヶ月後）を計算
      currentAccrualDate = currentAccrualDate.add(const Duration(days: 180));
    }
    
    return schedule;
  }

  /// 初回付与日を計算
  /// 
  /// 入社日の6ヶ月後（180日後）が初回付与日になります
  static DateTime calculateFirstAccrualDate(DateTime hiredDate) {
    return hiredDate.add(const Duration(days: 180));
  }

  /// 入社日から特定日時点での勤続年数を計算
  static int _yearsAtAccrual(DateTime hiredDate, DateTime accrualDate) {
    return accrualDate.year - hiredDate.year;
  }

  /// 付与タイミングでの日数を計算
  /// 
  /// 日本の法定有給休暇：
  /// - 0～6年未満：10日
  /// - 6～12年未満：11日
  /// - 12年以上：20日
  static int _calculateDaysAtAccrual(DateTime hiredDate, DateTime accrualDate) {
    final yearsAtAccrual = _yearsAtAccrual(hiredDate, accrualDate);
    
    if (yearsAtAccrual < 6) return 10;
    if (yearsAtAccrual < 12) return 11;
    return 20;
  }

  /// 入社日から指定日時点での付与日数を計算（日本法律ベース・Week 13追加）
  /// 
  /// 6ヶ月後から最初の付与があり、その後の勤続年数に応じて増加します
  /// ユーザーの会社独自ルールに対応するため、手入力で修正可能な設計です
  /// 
  /// 付与スケジュール：
  /// - 入社6ヶ月後（1年目）： 10日
  /// - 入社1年6ヶ月後（2年目）： 11日
  /// - 入社2年6ヶ月後（3年目）： 12日
  /// - 入社3年6ヶ月後（4年目）： 14日
  /// - 入社4年6ヶ月後（5年目）： 16日
  /// - 入社5年6ヶ月後（6年目）： 18日
  /// - 入社6年6ヶ月以上（7年目以降）： 20日（MAX）
  static int calculateAccrualDaysFromHireDate(DateTime hiredDate, [DateTime? referenceDate]) {
    final checkDate = referenceDate ?? DateTime.now();
    
    // 入社からの月数を計算
    final monthsElapsed = _calculateMonthsElapsed(hiredDate, checkDate);
    
    // 最初の付与は6ヶ月後から
    if (monthsElapsed < 6) {
      return 0; // まだ有休なし
    }
    
    // 勤続月数に基づいて付与日数を決定
    if (monthsElapsed < 18) return 10;    // 6ヶ月～1年5ヶ月：10日
    if (monthsElapsed < 30) return 11;    // 1年6ヶ月～2年5ヶ月：11日
    if (monthsElapsed < 42) return 12;    // 2年6ヶ月～3年5ヶ月：12日
    if (monthsElapsed < 54) return 14;    // 3年6ヶ月～4年5ヶ月：14日
    if (monthsElapsed < 66) return 16;    // 4年6ヶ月～5年5ヶ月：16日
    if (monthsElapsed < 78) return 18;    // 5年6ヶ月～6年5ヶ月：18日
    return 20; // 6年6ヶ月以上：20日（MAX）
  }

  /// 入社からの月数を計算
  static int _calculateMonthsElapsed(DateTime hiredDate, DateTime checkDate) {
    int months = (checkDate.year - hiredDate.year) * 12;
    months += (checkDate.month - hiredDate.month);
    return months;
  }

  /// 付与日を計算（カスタマイズ可能）
  /// 
  /// デフォルトは"10/01"（10月1日）ですが、
  /// 会社によって異なるため、app_settings から取得した値を使用します
  static DateTime calculateAccrualDateForYear(int year, String accrualDateStr) {
    // accrualDateStr = "10/01" 形式
    final parts = accrualDateStr.split('/');
    final month = int.parse(parts[0]);
    final day = int.parse(parts[1]);
    return DateTime(year, month, day);
  }

  /// 消滅日時を計算（付与日の前年同日 23:59）
  /// 
  /// 例）2025年10月1日付与分 → 2026年9月30日 23:59に消滅
  static DateTime calculateExpirationDate(DateTime accrualDate, {int yearsToExpire = 2}) {
    // 付与日から指定年数後のその前日 23:59
    final expiryDate = accrualDate.add(Duration(days: 365 * yearsToExpire - 1));
    return DateTime(expiryDate.year, expiryDate.month, expiryDate.day, 23, 59, 59);
  }

  /// 付与日数が増える「3年ごと」のマイルストーン日を計算
  /// 
  /// 6年目と12年目の付与日数が増える日を予測
  static Future<List<AccrualMilestone>> calculateMilestones(DateTime hiredDate) async {
    final milestones = <AccrualMilestone>[];
    
    // 6年目のマイルストーン
    final sixYearLater = hiredDate.add(const Duration(days: 2190)); // 6年 ≈ 2190日
    if (sixYearLater.isBefore(DateTime.now())) {
      milestones.add(
        AccrualMilestone(
          date: sixYearLater,
          description: '6年以上の勤続 → 付与日数が10日 → 11日に増える',
          increasedDays: 1,
        ),
      );
    }
    
    // 12年目のマイルストーン
    final twelveYearLater = hiredDate.add(const Duration(days: 4380)); // 12年 ≈ 4380日
    if (twelveYearLater.isBefore(DateTime.now())) {
      milestones.add(
        AccrualMilestone(
          date: twelveYearLater,
          description: '12年以上の勤続 → 付与日数が11日 → 20日に増える',
          increasedDays: 9,
        ),
      );
    }
    
    return milestones;
  }

  /// 指定月での付与がいくつあるかをカウント
  /// 
  /// 例：2024年10月の付与が何件あるか？
  static int countAccrualsInMonth(DateTime hiredDate, int year, int month) {
    final schedule = calculateAccrualSchedule(hiredDate);
    
    return schedule.where((item) {
      return item.accrualDate.year == year && item.accrualDate.month == month;
    }).length;
  }

  /// 次の付与日を計算
  /// 
  /// 現在から見て、次に付与される日付を返す
  static DateTime? getNextAccrualDate(DateTime hiredDate) {
    final now = DateTime.now();
    final schedule = calculateAccrualSchedule(hiredDate);
    
    // 今日より後の最初の付与日を検索
    try {
      return schedule.firstWhere((item) => item.accrualDate.isAfter(now)).accrualDate;
    } catch (e) {
      // 今後の付与がない場合
      return null;
    }
  }

  /// 次の付与まであと何日か
  static int? getDaysUntilNextAccrual(DateTime hiredDate) {
    final nextAccrual = getNextAccrualDate(hiredDate);
    if (nextAccrual == null) return null;
    
    return nextAccrual.difference(DateTime.now()).inDays;
  }

  /// 残り有給の概算を計算（付与スケジュールのみで使用日数は考慮しない）
  /// 
  /// UI で「あと〇〇日ぐらい有給があります」という表示用
  static int calculateEstimatedRemainingDays(DateTime hiredDate) {
    final schedule = calculateAccrualSchedule(hiredDate);
    final now = DateTime.now();
    
    // 現在より後の全付与を合計
    return schedule.fold<int>(0, (sum, item) {
      // 失効していない付与のみをカウント
      if (now.isBefore(item.expiryDate)) {
        return sum + item.daysGranted;
      }
      return sum;
    });
  }
}

/// 付与スケジュール項目
class AccrualScheduleItem {
  final DateTime accrualDate;   // 付与日
  final int daysGranted;        // 付与日数
  final DateTime expiryDate;    // 失効日
  final int yearsAtAccrual;     // 付与時の勤続年数

  AccrualScheduleItem({
    required this.accrualDate,
    required this.daysGranted,
    required this.expiryDate,
    required this.yearsAtAccrual,
  });

  /// 人間が読める形式での説明文
  String get description {
    final dateStr = '${accrualDate.year}年${accrualDate.month}月${accrualDate.day}日';
    return '$dateStr に $daysGranted 日付与（勤続${yearsAtAccrual}年）';
  }

  /// 失効日の人間が読める形式
  String get expiryDateFormatted {
    return '${expiryDate.year}年${expiryDate.month}月${expiryDate.day}日';
  }

  /// 既に失効しているか判定
  bool get isExpired {
    return DateTime.now().isAfter(expiryDate);
  }

  /// 失効予定か判定（あと30日以内）
  bool get isExpiringSoon {
    final thirtyDaysLater = DateTime.now().add(const Duration(days: 30));
    return !isExpired && DateTime.now().isBefore(expiryDate) && expiryDate.isBefore(thirtyDaysLater);
  }
}

/// 勤続年数のマイルストーン
class AccrualMilestone {
  final DateTime date;
  final String description;
  final int increasedDays;

  AccrualMilestone({
    required this.date,
    required this.description,
    required this.increasedDays,
  });
}