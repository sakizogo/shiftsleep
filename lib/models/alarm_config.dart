// lib/models/alarm_config.dart

// アラームモード（なし / 1回 / 2回）
enum AlarmMode {
  none,     // アラーム通知なし
  oneTime,  // メインアラーム（起床予定時刻）のみ
  twoTimes, // 事前アラーム（5分前）+ メインアラーム
}

// アラーム音の種類
enum AlarmSound {
  harsh,    // キツイ音（大きく耳に残る）
  gentle,   // 緩やかな音（やさしく目覚める）
  defaultSound, // Android デフォルト通知音
}

/// アラーム設定データモデル
/// ユーザーのアラーム設定を管理（DB に保存）
class AlarmConfig {
  final String id;              // PK
  final String userId;          // ユーザーID
  final AlarmMode alarmMode;    // アラームモード
  final AlarmSound alarmSound;  // アラーム音
  final int volume;             // 音量（0～100）
  final DateTime createdAt;     // 作成日時
  final DateTime updatedAt;     // 更新日時

  AlarmConfig({
    required this.id,
    required this.userId,
    required this.alarmMode,
    required this.alarmSound,
    required this.volume,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Dart オブジェクト → Map（DB 保存用）
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'alarmMode': alarmMode.toString().split('.').last, // 'none', 'oneTime', 'twoTimes'
      'alarmSound': alarmSound.toString().split('.').last, // 'harsh', 'gentle', 'defaultSound'
      'volume': volume,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Map（DB 読取）→ Dart オブジェクト
  factory AlarmConfig.fromMap(Map<String, dynamic> map) {
    return AlarmConfig(
      id: map['id'] as String,
      userId: map['userId'] as String,
      alarmMode: _parseAlarmMode(map['alarmMode'] as String),
      alarmSound: _parseAlarmSound(map['alarmSound'] as String),
      volume: map['volume'] as int,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  /// copyWith - 一部フィールドだけ上書きしたコピーを作成
  AlarmConfig copyWith({
    String? id,
    String? userId,
    AlarmMode? alarmMode,
    AlarmSound? alarmSound,
    int? volume,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AlarmConfig(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      alarmMode: alarmMode ?? this.alarmMode,
      alarmSound: alarmSound ?? this.alarmSound,
      volume: volume ?? this.volume,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'AlarmConfig(id: $id, userId: $userId, alarmMode: $alarmMode, '
        'alarmSound: $alarmSound, volume: $volume, updatedAt: $updatedAt)';
  }
}

/// 文字列 → AlarmMode Enum に変換
AlarmMode _parseAlarmMode(String value) {
  switch (value) {
    case 'none':
      return AlarmMode.none;
    case 'oneTime':
      return AlarmMode.oneTime;
    case 'twoTimes':
      return AlarmMode.twoTimes;
    default:
      return AlarmMode.oneTime; // デフォルト
  }
}

/// 文字列 → AlarmSound Enum に変換
AlarmSound _parseAlarmSound(String value) {
  switch (value) {
    case 'harsh':
      return AlarmSound.harsh;
    case 'gentle':
      return AlarmSound.gentle;
    case 'defaultSound':
      return AlarmSound.defaultSound;
    default:
      return AlarmSound.defaultSound; // デフォルト
  }
}
