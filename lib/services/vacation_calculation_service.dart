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