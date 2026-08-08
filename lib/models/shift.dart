import 'package:shiftsleep/models/shift_pattern_model.dart';

class Shift {
  final String id;
  final String userId;
  final String shiftDate;      // "2026-08-06" 形式（ISO 8601日付のみ）
  final String patternId;      // shift_patterns テーブルへの外部キー
  final String createdAt;      // ISO 8601形式
  final String updatedAt;      // ISO 8601形式

  Shift({
    required this.id,
    required this.userId,
    required this.shiftDate,
    required this.patternId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// DBから取得したMapから変換
  factory Shift.fromMap(Map<String, dynamic> map) {
    return Shift(
      id: map['id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      shiftDate: map['shift_date'] as String,
      patternId: map['pattern_id'] as String,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  /// Map に変換
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'shift_date': shiftDate,
      'pattern_id': patternId,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  @override
  String toString() {
    return 'Shift(shiftDate: $shiftDate, patternId: $patternId, createdAt: $createdAt)';
  }
}