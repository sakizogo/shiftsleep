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
    );
  }
}