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
  final bool isDeleted;  // N104：消えたパターンの日に使う「削除済み」の仮パターンなら true

  /// N104：削除済みの文字・枠の色（灰色。色だけに頼らず「削除済み」の文字も出す）
  static const Color deletedColor = Color(0xFF757575);

  /// colorIndex から自動で色を決定（削除済みは灰色）
  Color get color => isDeleted ? deletedColor : _ColorPalette.getColorByIndex(colorIndex);

  ShiftPatternModel({
    required this.id,
    required this.patternName,
    required this.patternType,
    this.startTime,
    this.endTime,
    int? colorIndex,
  })  : colorIndex = colorIndex ?? 0,
        isDeleted = false;

  /// N104：「削除済み」の仮パターン
  /// id は元の pattern_id のまま（シフトを確定しても同じ ID で保存されるように）
  /// 種類は休日（dayOff）にして、出勤・有休・半休の判定に入らないようにする
  ShiftPatternModel.deleted(this.id)
      : patternName = '削除済み',
        patternType = ShiftType.dayOff,
        startTime = null,
        endTime = null,
        colorIndex = 0,
        isDeleted = true;

  @override
  String toString() {
    return 'ShiftPatternModel(id: $id, name: $patternName, type: $patternType, colorIndex: $colorIndex, isDeleted: $isDeleted)';
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