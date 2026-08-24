import 'package:uuid/uuid.dart';

class VacationSettings {
  final String userId;
  final DateTime hiredDate;      // 入社日
  final int annualDays;          // デフォルト付与日数（使用していない、後方互換性のため）
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

class VacationAccrual {
  final String id;
  final String userId;
  final DateTime accrualDate;    // 付与日（例：2024-10-01）
  final double daysGranted;      // ✅ Week 14 修正：int → double（0.5日対応）
  final DateTime expiryDate;     // 失効日（付与から2年後）
  final String? notes;           // 備考（例：「初回付与」「昇進による追加」）
  final DateTime createdAt;
  final DateTime updatedAt;

  VacationAccrual({
    required this.id,
    required this.userId,
    required this.accrualDate,
    required this.daysGranted,   // ✅ 型が double に変わった
    required this.expiryDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 新規作成用ファクトリ（失効日は自動計算）
  factory VacationAccrual.create({
    required String userId,
    required DateTime accrualDate,
    required double daysGranted,  // ✅ 型が double に変わった
    String? notes,
  }) {
    final now = DateTime.now();
    // 付与日から2年後が失効日
    final expiryDate = accrualDate.add(Duration(days: 730));
    
    return VacationAccrual(
      id: const Uuid().v4(),
      userId: userId,
      accrualDate: accrualDate,
      daysGranted: daysGranted,
      expiryDate: expiryDate,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// この付与がまだ有効か（失効前）を判定
  bool get isValid {
    return DateTime.now().isBefore(expiryDate);
  }

  /// 失効まであと何日か
  int get daysUntilExpiry {
    final diff = expiryDate.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }

  /// 失効日を日本語フォーマットで取得（例：「2026年9月30日」）
  String get expiryDateFormatted {
    return '${expiryDate.year}年${expiryDate.month}月${expiryDate.day}日';
  }

  /// JSON 変換
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'accrual_date': accrualDate.toIso8601String(),
      'days_granted': daysGranted,  // ✅ double 型のまま保存（DBはREAL型）
      'expiry_date': expiryDate.toIso8601String(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory VacationAccrual.fromMap(Map<String, dynamic> map) {
    return VacationAccrual(
      id: map['id'],
      userId: map['user_id'],
      accrualDate: DateTime.parse(map['accrual_date']),
      daysGranted: (map['days_granted'] as num).toDouble(),  // ✅ DB値を double に変換
      expiryDate: DateTime.parse(map['expiry_date']),
      notes: map['notes'],
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
  final DateTime updatedAt;

  VacationUsage({
    required this.id,
    required this.userId,
    required this.usageDate,
    required this.daysUsed,
    this.reason,
    required this.createdAt,
    required this.updatedAt,
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
      'updated_at': updatedAt.toIso8601String(),
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
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  /// 新規作成用ファクトリ
  factory VacationUsage.create({
    required String userId,
    required DateTime usageDate,
    required double daysUsed,
    String? reason,
  }) {
    final now = DateTime.now();
    return VacationUsage(
      id: const Uuid().v4(),
      userId: userId,
      usageDate: usageDate,
      daysUsed: daysUsed,
      reason: reason,
      createdAt: now,
      updatedAt: now,
    );
  }
}