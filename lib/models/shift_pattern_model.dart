import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/shift_enums.dart';

/// シフトパターンを表すモデル
/// 色盲対応カラーパレットを使用して、全ての利用者が判別しやすい配色を採用
class ShiftPatternModel {
  final String id;
  final String patternName;
  final ShiftType patternType;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final Color color;

  ShiftPatternModel({
    required this.id,
    required this.patternName,
    required this.patternType,
    this.startTime,
    this.endTime,
    Color? color,
  }) : color = color ?? _getDefaultColor(patternType);

  /// パターンのタイプに応じた色を取得
  static Color _getDefaultColor(ShiftType patternType) {
    switch (patternType) {
      case ShiftType.dayOff:
        return _ColorPalette.colorRed; // 赤（休日）
      case ShiftType.work:
        return _ColorPalette.colorBlue; // 青（出勤・朝勤）
    }
  }

  /// パターン登録時に自動割り当てする色を順番に取得
  /// ユーザーが複数のパターンを登録した場合、色が重複しないようにする
  static Color getColorByIndex(int index) {
    final colors = _ColorPalette.allColors;
    return colors[index % colors.length];
  }

  @override
  String toString() {
    return 'ShiftPatternModel(id: $id, name: $patternName, type: $patternType, startTime: $startTime, endTime: $endTime)';
  }
}

/// 色盲対応カラーパレット
/// 参考：Wong B (2011) Color blindness.
/// https://www.nature.com/articles/nmeth.1618
/// 
/// このパレットは以下の特性を持つ：
/// - 赤色盲（Protanopia）
/// - 緑色盲（Deuteranopia）
/// - 青黄色盲（Tritanopia）
/// いずれのタイプでも判別しやすい配色
class _ColorPalette {
  // 個別の色定義
  static const Color colorBlue = Color(0xFF0072B2);      // 青（出勤・朝勤）
  static const Color colorOrange = Color(0xFFE69F00);    // オレンジ（夜勤）
  static const Color colorRed = Color(0xFFD55E00);       // 赤紫（休日）
  static const Color colorTeal = Color(0xFF56B4E9);      // 青緑（フル勤）
  static const Color colorYellow = Color(0xFFF0E442);    // 黄土色（カスタム）
  static const Color colorPurple = Color(0xFFCC79A7);    // 赤紫ピンク（準夜勤）

  /// 全ての色をリストで管理
  /// パターン登録時に順番に割り当てられる
  static const List<Color> allColors = [
    colorBlue,
    colorOrange,
    colorRed,
    colorTeal,
    colorYellow,
    colorPurple,
  ];

  /// 色の説明（アクセシビリティ対応）
  static const Map<String, String> colorDescriptions = {
    '青': 'Blue',
    'オレンジ': 'Orange',
    '赤紫': 'Red',
    '青緑': 'Teal',
    '黄土色': 'Yellow',
    'ピンク': 'Pink',
  };
}