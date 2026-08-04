/// シフト管理の Enum 定義
/// ShiftSleep で使用する勤務体制、シフトタイプなど

/// ユーザーの勤務体制の複雑さレベル
enum ShiftComplexity {
  /// 1～2週間のパターンで固定（工場・流通）
  simple,

  /// ローテーションパターンが存在（警察・消防）
  moderate,

  /// 毎月シフト表から入力（看護師・飲食）
  complex,
}

/// シフトの種類
enum ShiftType {
  /// 出勤
  work,

  /// 休日
  dayOff,
}

/// アラームモード
enum AlarmMode {
  /// アラームなし
  none,

  /// 1回のみ（メインアラーム）
  once,

  /// 2回（5分前 + メイン）
  twice,
}

/// 曜日
enum DayOfWeek {
  /// 月曜日
  monday,

  /// 火曜日
  tuesday,

  /// 水曜日
  wednesday,

  /// 木曜日
  thursday,

  /// 金曜日
  friday,

  /// 土曜日
  saturday,

  /// 日曜日
  sunday,
}

/// シフトテンプレートの周期タイプ
enum TemplateType {
  /// 1週間ごと
  weekly,

  /// 2週間ごと
  biweekly,

  /// ローテーション（可変周期）
  rotation,

  /// カスタム
  custom,
}

/// Extension: DayOfWeek を日本語で表示
extension DayOfWeekExtension on DayOfWeek {
  String get displayName {
    switch (this) {
      case DayOfWeek.monday:
        return '月';
      case DayOfWeek.tuesday:
        return '火';
      case DayOfWeek.wednesday:
        return '水';
      case DayOfWeek.thursday:
        return '木';
      case DayOfWeek.friday:
        return '金';
      case DayOfWeek.saturday:
        return '土';
      case DayOfWeek.sunday:
        return '日';
    }
  }

  /// DateTime.weekday（1=月...7=日）から DayOfWeek に変換
  static DayOfWeek fromDateTimeWeekday(int weekday) {
    switch (weekday) {
      case 1:
        return DayOfWeek.monday;
      case 2:
        return DayOfWeek.tuesday;
      case 3:
        return DayOfWeek.wednesday;
      case 4:
        return DayOfWeek.thursday;
      case 5:
        return DayOfWeek.friday;
      case 6:
        return DayOfWeek.saturday;
      case 7:
        return DayOfWeek.sunday;
      default:
        return DayOfWeek.monday;
    }
  }
}

/// Extension: ShiftComplexity を日本語で表示
extension ShiftComplexityExtension on ShiftComplexity {
  String get displayName {
    switch (this) {
      case ShiftComplexity.simple:
        return 'シンプル型';
      case ShiftComplexity.moderate:
        return '中程度型';
      case ShiftComplexity.complex:
        return '複雑型';
    }
  }

  String get description {
    switch (this) {
      case ShiftComplexity.simple:
        return '1～2週間のパターンで固定（工場・流通）';
      case ShiftComplexity.moderate:
        return 'ローテーションパターンが存在（警察・消防）';
      case ShiftComplexity.complex:
        return '毎月シフト表から入力（看護師・飲食）';
    }
  }
}

/// Extension: ShiftType を日本語で表示
extension ShiftTypeExtension on ShiftType {
  String get displayName {
    switch (this) {
      case ShiftType.work:
        return '出勤';
      case ShiftType.dayOff:
        return '休日';
    }
  }

  bool get isWorkDay => this == ShiftType.work;
  bool get isDayOff => this == ShiftType.dayOff;
}

/// シフトパターン登録画面のモード
enum ShiftPatternMode {
  /// 新規登録モード
  register,

  /// 編集モード
  edit,
}

/// Extension: ShiftPatternMode を日本語で表示
extension AlarmModeExtension on AlarmMode {
  String get displayName {
    switch (this) {
      case AlarmMode.none:
        return 'なし';
      case AlarmMode.once:
        return '1回（メインのみ）';
      case AlarmMode.twice:
        return '2回（5分前＋メイン）';
    }
  }

  bool get hasPreAlarm => this == AlarmMode.twice;
  bool get hasMainAlarm => this != AlarmMode.none;
}