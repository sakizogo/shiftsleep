import 'package:flutter/material.dart';

class AppColors {
  // Primary Gradient
  static const Color primaryGradientStart = Color(0xFF8B5CF6);
  static const Color primaryGradientEnd = Color(0xFF3B82F6);

  // Warning & Alert
  static const Color warningRed = Color(0xFFE53935);
  static const Color darkWarning = Color(0xFFC62828);

  // Background & Surface
  static const Color backgroundLight = Color(0xFFFAFAFA);
  static const Color borderDefault = Color(0xFFE0E0E0);

  // Card Backgrounds
  static const Color cardBgWarning = Color(0xFFFFF9E6);
  static const Color borderWarning = Color(0xFFFFE082);

  static const Color cardBgAlert = Color(0xFFFFEBEE);
  static const Color cardBgGray = Color(0xFFF0F0F0);

  // Text Colors
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textMuted = Color(0xFF999999);

  // Accent
  static const Color starYellow = Color(0xFFFDB022);

    // ========== Week 9-1 追加: 睡眠集計セクション用カラー（Wong 2011 対応）==========
  // テキスト + 色の組み合わせで色盲対応
  
  /// 当日の睡眠集計用：青系（Wong 2011: Blue）
  static const Color summaryTodayBg = Color(0xFFE3F2FD);    // 薄い青（背景）
  static const Color summaryTodayBorder = Color(0xFF0072B2); // 濃い青（枠線）
  static const Color summaryTodayText = Color(0xFF01579B);   // テキスト
  
  /// 今週の睡眠集計用：緑系（Wong 2011: Blueish-green）
  static const Color summaryWeekBg = Color(0xFFE8F5E9);     // 薄い緑（背景）
  static const Color summaryWeekBorder = Color(0xFF009E73);  // 濃い緑（枠線）
  static const Color summaryWeekText = Color(0xFF00695C);    // テキスト
  
  /// 今月の睡眠集計用：紫系（既存 primary に調和）
  static const Color summaryMonthBg = Color(0xFFF3E5F5);    // 薄い紫（背景）
  static const Color summaryMonthBorder = Color(0xFF6A1B9A); // 濃い紫（枠線）
  static const Color summaryMonthText = Color(0xFF4A148C);   // テキスト
  // =============================================================================
}