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
  final int colorIndex;  // ← 新規追加：色のインデックス
  
  /// colorIndex から自動で色を決定
  Color get color => _ColorPalette.getColorByIndex(colorIndex);

  ShiftPatternModel({
    required this.id,
    required this.patternName,
    required this.patternType,
    this.startTime,
    this.endTime,
    int? colorIndex,
  }) : colorIndex = colorIndex ?? 0;

  @override
  String toString() {
    return 'ShiftPatternModel(id: $id, name: $patternName, type: $patternType, colorIndex: $colorIndex)';
  }
}

/// 色盲対応カラーパレット
class _ColorPalette {
  static const Color colorBlue = Color(0xFF0072B2);      // 青
  static const Color colorOrange = Color(0xFFE69F00);    // オレンジ
  static const Color colorRed = Color(0xFFD55E00);       // 赤紫
  static const Color colorTeal = Color(0xFF56B4E9);      // 青緑
  static const Color colorYellow = Color(0xFFF0E442);    // 黄土色
  static const Color colorPurple = Color(0xFFCC79A7);    // ピンク

  static const List<Color> allColors = [
    colorBlue,
    colorOrange,
    colorRed,
    colorTeal,
    colorYellow,
    colorPurple,
  ];

  /// インデックスから色を取得（色盲対応パレット）
  static Color getColorByIndex(int index) {
    return allColors[index % allColors.length];
  }

  static const Map<String, String> colorDescriptions = {
    '青': 'Blue',
    'オレンジ': 'Orange',
    '赤紫': 'Red',
    '青緑': 'Teal',
    '黄土色': 'Yellow',
    'ピンク': 'Pink',
  };
}