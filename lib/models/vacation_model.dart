import 'package:uuid/uuid.dart';

class VacationSettings {
  final String userId;
  final DateTime hiredDate;      // 入社日
  final int annualDays;          // 今年の付与日数
  final bool manualOverride;     // 手入力フラグ
  final DateTime? lastCalculationDate;  // 最後に自動計算した日
  final DateTime createdAt;
  final DateTime updatedAt;

  VacationSettings({
    required this.userId,
    required this.hiredDate,
    required this.annualDays,
    this.manualOverride = false,
    this.lastCalculationDate,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 入社日から自動計算した付与日数を返す
  /// 0～6年未満：10日
  /// 6～12年未満：11日
  /// 12年以上：20日
  static int calculateAnnualDays(DateTime hiredDate) {
    final yearsWorked = DateTime.now().year - hiredDate.year;
    
    if (yearsWorked < 6) return 10;
    if (yearsWorked < 12) return 11;
    return 20;
  }

  /// JSON 変換
  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'hired_date': hiredDate.toIso8601String(),
      'annual_days': annualDays,
      'manual_override': manualOverride ? 1 : 0,
      'last_calculation_date': lastCalculationDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory VacationSettings.fromMap(Map<String, dynamic> map) {
    return VacationSettings(
      userId: map['user_id'],
      hiredDate: DateTime.parse(map['hired_date']),
      annualDays: map['annual_days'],
      manualOverride: map['manual_override'] == 1,
      lastCalculationDate: map['last_calculation_date'] != null
          ? DateTime.parse(map['last_calculation_date'])
          : null,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }
}

class VacationUsage {
  final String id;
  final String userId;
  final DateTime usageDate;      // 使用日
  final double daysUsed;         // 使用日数（0.5 = 半日）
  final String? reason;          // 使用理由
  final DateTime createdAt;

  VacationUsage({
    required this.id,
    required this.userId,
    required this.usageDate,
    required this.daysUsed,
    this.reason,
    required this.createdAt,
  });

  /// JSON 変換
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'usage_date': usageDate.toIso8601String(),
      'days_used': daysUsed,
      'reason': reason,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory VacationUsage.fromMap(Map<String, dynamic> map) {
    return VacationUsage(
      id: map['id'],
      userId: map['user_id'],
      usageDate: DateTime.parse(map['usage_date']),
      daysUsed: (map['days_used'] as num).toDouble(),
      reason: map['reason'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  /// 新規作成用ファクトリ
  factory VacationUsage.create({
    required String userId,
    required DateTime usageDate,
    required double daysUsed,
    String? reason,
  }) {
    return VacationUsage(
      id: const Uuid().v4(),
      userId: userId,
      usageDate: usageDate,
      daysUsed: daysUsed,
      reason: reason,
      createdAt: DateTime.now(),
    );
  }
}