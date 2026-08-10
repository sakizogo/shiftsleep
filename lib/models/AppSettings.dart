/// lib/models/AppSettings.dart
/// アプリ全体設定を管理するモデル
/// - アラーム時間カスタマイズ（30〜180分、15分刻み）
/// - その他ユーザー設定

class AppSettings {
  final int id;                           // 通常は1（単一設定）
  final String userId;                    // ユーザーID
  final int alarmTimeBeforeShift;         // 出勤前何分にアラーム（30〜180分）
  final DateTime createdAt;
  final DateTime updatedAt;

  AppSettings({
    required this.id,
    required this.userId,
    this.alarmTimeBeforeShift = 30,       // デフォルト：30分前
    required this.createdAt,
    required this.updatedAt,
  });

  /// DBから取得したMapをAppSettingsに変換
  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      id: map['id'] as int,
      userId: map['user_id'] as String,
      alarmTimeBeforeShift: map['alarm_time_before_shift'] as int? ?? 30,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// AppSettingsをMapに変換（DB保存用）
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'alarm_time_before_shift': alarmTimeBeforeShift,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// AppSettingsをコピーして部分更新（新しいインスタンスを生成）
  AppSettings copyWith({
    int? id,
    String? userId,
    int? alarmTimeBeforeShift,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppSettings(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      alarmTimeBeforeShift: alarmTimeBeforeShift ?? this.alarmTimeBeforeShift,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => '''
AppSettings(
  id: $id,
  userId: $userId,
  alarmTimeBeforeShift: ${alarmTimeBeforeShift}分前,
  createdAt: $createdAt,
  updatedAt: $updatedAt
)
''';
}