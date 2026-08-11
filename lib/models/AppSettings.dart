/// lib/models/AppSettings.dart
/// アプリ全体設定を管理するモデル
/// - アラーム時間カスタマイズ（30〜180分、15分刻み）
/// - その他ユーザー設定

class AppSettings {
  final int id;
  final String userId;
  final int alarmTimeBeforeShift;
  final String wakeUpTime;  // "07:00" 形式で保存
  final DateTime createdAt;
  final DateTime updatedAt;

  AppSettings({
    required this.id,
    required this.userId,
    this.alarmTimeBeforeShift = 30,
    this.wakeUpTime = '07:00',  // デフォルト：07:00
    required this.createdAt,
    required this.updatedAt,
  });

  /// DBから取得したMapをAppSettingsに変換
  factory AppSettings.fromMap(Map<String, dynamic> map) {
    try {
      // id がない場合は 1 をデフォルトとする
      final id = map['id'] != null 
          ? (map['id'] is int ? map['id'] as int : int.parse(map['id'].toString()))
          : 1;
      
      final userId = map['user_id'] as String? ?? 'unknown';
      final alarmTime = _safeIntCast(map['alarm_time_before_shift']) ?? 30;
      final createdAt = DateTime.parse(map['created_at'] as String);
      final updatedAt = DateTime.parse(map['updated_at'] as String);
      final wakeUpTime = map['wake_up_time'] as String? ?? '07:00';
      
      print('✅ AppSettings読み込み完了: userId=$userId, alarm=$alarmTime分前');
      
      return AppSettings(
        id: id,
        userId: userId,
        alarmTimeBeforeShift: alarmTime,
        wakeUpTime: wakeUpTime,  
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } catch (e) {
      print('❌ AppSettings.fromMap() エラー: $e');
      rethrow;
    }
  }

  /// 安全な int キャスト（この1つだけ保つ）
  static int? _safeIntCast(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// AppSettingsをMapに変換（DB保存用）
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'alarm_time_before_shift': alarmTimeBeforeShift,
      'wake_up_time': wakeUpTime,  // 追加
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// AppSettingsをコピーして部分更新（新しいインスタンスを生成）
  AppSettings copyWith({
    int? id,
    String? userId,
    int? alarmTimeBeforeShift,
    String? wakeUpTime, 
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppSettings(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      alarmTimeBeforeShift: alarmTimeBeforeShift ?? this.alarmTimeBeforeShift,
      wakeUpTime: wakeUpTime ?? this.wakeUpTime, 
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