/// lib/models/app_settings.dart
/// アプリ全体設定を管理するモデル
/// - アラーム時間カスタマイズ（30〜180分、15分刻み）
/// - 改善アドバイスの有料版プロモーション表示設定
/// - 有料版ユーザーフラグ
/// - その他ユーザー設定

class AppSettings {
  final int id;
  final String userId;
  final int alarmTimeBeforeShift;
  final String wakeUpTime;  // \"07:00\" 形式で保存
  final String selectedAlarmSound;  // （'default', 'gentle', 'harsh'）
  final bool advicePromoVisible;  // ← Week 7 A で追加：有料版プロモーション表示フラグ
  final bool isPremiumUser;  // ← Week 7 Phase 3 追加：有料ユーザーフラグ
  final DateTime createdAt;
  final DateTime updatedAt;

  AppSettings({
    required this.id,
    required this.userId,
    this.alarmTimeBeforeShift = 30,
    this.wakeUpTime = '07:00',  // デフォルト：07:00
    this.selectedAlarmSound = 'default',
    this.advicePromoVisible = true,  // ← Week 7 A：デフォルト true（表示する）
    this.isPremiumUser = false,  // ← Week 7 Phase 3：デフォルト false（無料ユーザー）
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
      final selectedAlarmSound = map['selected_alarm_sound'] as String? ?? 'default';
      final advicePromoVisible = _safeBoolCast(map['advice_promo_visible']) ?? true;
      final isPremiumUser = _safeBoolCast(map['is_premium_user']) ?? false;  // ← Week 7 Phase 3 追加
      
      print('✅ AppSettings読み込み完了: userId=$userId, alarm=$alarmTime分前, promoVisible=$advicePromoVisible, isPremium=$isPremiumUser');
      
      return AppSettings(
        id: id,
        userId: userId,
        alarmTimeBeforeShift: alarmTime,
        wakeUpTime: wakeUpTime,  
        selectedAlarmSound: selectedAlarmSound,
        advicePromoVisible: advicePromoVisible,
        isPremiumUser: isPremiumUser,  // ← Week 7 Phase 3 追加
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } catch (e) {
      print('❌ AppSettings.fromMap() エラー: $e');
      rethrow;
    }
  }

  /// 安全な int キャスト
  static int? _safeIntCast(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// 安全な bool キャスト
  static bool? _safeBoolCast(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return null;
  }

  /// AppSettingsをMapに変換（DB保存用）
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'alarm_time_before_shift': alarmTimeBeforeShift,
      'wake_up_time': wakeUpTime,
      'selected_alarm_sound': selectedAlarmSound,
      'advice_promo_visible': advicePromoVisible ? 1 : 0,
      'is_premium_user': isPremiumUser ? 1 : 0,  // ← Week 7 Phase 3 追加（boolean を int に変換）
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
    String? selectedAlarmSound,
    bool? advicePromoVisible,
    bool? isPremiumUser,  // ← Week 7 Phase 3 追加
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppSettings(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      alarmTimeBeforeShift: alarmTimeBeforeShift ?? this.alarmTimeBeforeShift,
      wakeUpTime: wakeUpTime ?? this.wakeUpTime, 
      selectedAlarmSound: selectedAlarmSound ?? this.selectedAlarmSound,
      advicePromoVisible: advicePromoVisible ?? this.advicePromoVisible,
      isPremiumUser: isPremiumUser ?? this.isPremiumUser,  // ← Week 7 Phase 3 追加
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
  advicePromoVisible: $advicePromoVisible,
  isPremiumUser: $isPremiumUser,
  createdAt: $createdAt,
  updatedAt: $updatedAt
)
''';
}