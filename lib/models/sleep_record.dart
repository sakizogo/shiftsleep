// ========== Week 7 A 追加: SleepRole enum ==========
/// 睡眠の質的役割を定義
/// 
/// 時間帯ベースではなく、睡眠の「役割」で分類
/// これにより、シフトワーカー（特に夜勤者）にも対応
enum SleepRole {
  primary,        // メイン睡眠（5時間以上の長時間睡眠）
  supplementary,  // 補助睡眠（30分～5時間の昼寝など）
  split_segment   // 分割睡眠の一部（30分未満）
}

extension SleepRoleExtension on SleepRole {
  String get displayName {
    switch (this) {
      case SleepRole.primary:
        return 'メイン睡眠';
      case SleepRole.supplementary:
        return '補助睡眠';
      case SleepRole.split_segment:
        return '分割睡眠';
    }
  }

  String get jsonValue {
    switch (this) {
      case SleepRole.primary:
        return 'primary';
      case SleepRole.supplementary:
        return 'supplementary';
      case SleepRole.split_segment:
        return 'split_segment';
    }
  }

  static SleepRole fromString(String value) {
    switch (value) {
      case 'primary':
        return SleepRole.primary;
      case 'supplementary':
        return SleepRole.supplementary;
      case 'split_segment':
        return SleepRole.split_segment;
      default:
        return SleepRole.primary; // デフォルト
    }
  }
}
// ================================================

class SleepRecord {
  final String id;
  final String userId;
  final DateTime sleepDate;
  final DateTime sleepStartTime;
  final bool sleepStartAuto;
  final DateTime sleepEndTime;
  final bool sleepEndAuto;
  final String wakeUpType; // 'alarm_dismiss', 'early_wake_up', 'manual'
  final int durationMinutes;
  final int modifiedCount;
  final DateTime lastModifiedAt;
  final DateTime canEditUntil;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SleepRole sleepRole;  // ========== Week 7 A 追加 ==========

  SleepRecord({
    required this.id,
    required this.userId,
    required this.sleepDate,
    required this.sleepStartTime,
    required this.sleepStartAuto,
    required this.sleepEndTime,
    required this.sleepEndAuto,
    required this.wakeUpType,
    required this.durationMinutes,
    this.modifiedCount = 0,
    required this.lastModifiedAt,
    required this.canEditUntil,
    required this.createdAt,
    required this.updatedAt,
    this.sleepRole = SleepRole.primary,  // ========== Week 7 A デフォルト値 ==========
  });

  // Convert to JSON (for database storage)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'sleep_date': sleepDate.toIso8601String(),
      'sleep_start_time': sleepStartTime.toIso8601String(),
      'sleep_start_auto': sleepStartAuto ? 1 : 0,
      'sleep_end_time': sleepEndTime.toIso8601String(),
      'sleep_end_auto': sleepEndAuto ? 1 : 0,
      'wake_up_type': wakeUpType,
      'duration_minutes': durationMinutes,
      'modified_count': modifiedCount,
      'last_modified_at': lastModifiedAt.toIso8601String(),
      'can_edit_until': canEditUntil.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sleep_role': sleepRole.jsonValue,  // ========== Week 7 A 追加 ==========
    };
  }

  // Convert from JSON (from database)
  factory SleepRecord.fromJson(Map<String, dynamic> json) {
    return SleepRecord(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      sleepDate: DateTime.parse(json['sleep_date'] as String),
      sleepStartTime: DateTime.parse(json['sleep_start_time'] as String),
      sleepStartAuto: (json['sleep_start_auto'] as int) == 1,
      sleepEndTime: DateTime.parse(json['sleep_end_time'] as String),
      sleepEndAuto: (json['sleep_end_auto'] as int) == 1,
      wakeUpType: json['wake_up_type'] as String,
      durationMinutes: json['duration_minutes'] as int,
      modifiedCount: json['modified_count'] as int? ?? 0,
      lastModifiedAt: DateTime.parse(json['last_modified_at'] as String),
      canEditUntil: DateTime.parse(json['can_edit_until'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      sleepRole: SleepRoleExtension.fromString(json['sleep_role'] as String? ?? 'primary'),  // ========== Week 7 A 追加 ==========
    );
  }

  // Copy with (for updates)
  SleepRecord copyWith({
    String? id,
    String? userId,
    DateTime? sleepDate,
    DateTime? sleepStartTime,
    bool? sleepStartAuto,
    DateTime? sleepEndTime,
    bool? sleepEndAuto,
    String? wakeUpType,
    int? durationMinutes,
    int? modifiedCount,
    DateTime? lastModifiedAt,
    DateTime? canEditUntil,
    DateTime? createdAt,
    DateTime? updatedAt,
    SleepRole? sleepRole,  // ========== Week 7 A 追加 ==========
  }) {
    return SleepRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      sleepDate: sleepDate ?? this.sleepDate,
      sleepStartTime: sleepStartTime ?? this.sleepStartTime,
      sleepStartAuto: sleepStartAuto ?? this.sleepStartAuto,
      sleepEndTime: sleepEndTime ?? this.sleepEndTime,
      sleepEndAuto: sleepEndAuto ?? this.sleepEndAuto,
      wakeUpType: wakeUpType ?? this.wakeUpType,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      modifiedCount: modifiedCount ?? this.modifiedCount,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      canEditUntil: canEditUntil ?? this.canEditUntil,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sleepRole: sleepRole ?? this.sleepRole,  // ========== Week 7 A 追加 ==========
    );
  }

  // ========================
  // 互換性用 getter
  // ========================

  /// bedtime の互換性 getter（sleepStartTime のエイリアス）
  DateTime get bedtime => sleepStartTime;

  /// wakeTime の互換性 getter（sleepEndTime のエイリアス）
  DateTime get wakeTime => sleepEndTime;

  /// fromMap メソッド（fromJson のエイリアス）
  static SleepRecord fromMap(Map<String, dynamic> map) {
    return SleepRecord.fromJson(map);
  }

  /// toMap メソッド（toJson のエイリアス）
  Map<String, dynamic> toMap() {
    return toJson();
  }

  // ========== Week 7 A 追加: sleepRole 自動判定メソッド ==========
  /// 睡眠時間（durationMinutes）から sleepRole を自動判定
  /// 
  /// ロジック:
  /// - 5時間以上: primary（メイン睡眠）
  /// - 30分～5時間: supplementary（補助睡眠）
  /// - 30分未満: split_segment（分割睡眠）
  static SleepRole determineSleepRole(int durationMinutes) {
    if (durationMinutes >= 300) {  // 5時間以上
      return SleepRole.primary;
    } else if (durationMinutes >= 30) {  // 30分～5時間
      return SleepRole.supplementary;
    } else {
      return SleepRole.split_segment;  // 30分未満
    }
  }
  // ========================================================================
}