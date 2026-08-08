class CalendarEvent {
  final String id;
  final String userId;
  final String eventDate;      // "2026-08-06" 形式（ISO 8601日付のみ）
  final String eventType;      // "salary"(給料日), "bonus"(ボーナス), "trip"(慰安旅行) など
  final String eventEmoji;     // "💰", "🎁", "✈️" など
  final String? eventName;     // "給料日", "夏季ボーナス" など（オプション）
  final String? notes;         // "〇〇銀行に振込予定" など（オプション）
  final String createdAt;      // ISO 8601形式
  final String updatedAt;      // ISO 8601形式

  CalendarEvent({
    required this.id,
    required this.userId,
    required this.eventDate,
    required this.eventType,
    required this.eventEmoji,
    this.eventName,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// DBから取得したMapから変換
  factory CalendarEvent.fromMap(Map<String, dynamic> map) {
    return CalendarEvent(
      id: map['id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      eventDate: map['event_date'] as String,
      eventType: map['event_type'] as String,
      eventEmoji: map['event_emoji'] as String,
      eventName: map['event_name'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  /// Map に変換
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'event_date': eventDate,
      'event_type': eventType,
      'event_emoji': eventEmoji,
      'event_name': eventName,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  @override
  String toString() {
    return 'CalendarEvent(eventDate: $eventDate, eventType: $eventType, emoji: $eventEmoji)';
  }
}