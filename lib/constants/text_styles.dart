import 'package:flutter/material.dart';
import 'colors.dart';

class AppTextStyles {
  // Header
  static const TextStyle headerStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // Section Title
  static const TextStyle sectionTitleStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // Large Number (8h 00m)
  static const TextStyle largeNumberStyle = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  // Debt Number (-14h 30m)
  static const TextStyle debtNumberStyle = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.warningRed,
  );

  // SJL/SRI Number (2.5時間 / 35点)
  static const TextStyle statNumberStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // Button Text (今から寝る)
  static const TextStyle buttonTextStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  // Body Text
  static const TextStyle bodyTextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  // Caption (修正可など)
  static const TextStyle captionStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );

  // Small Description
  static const TextStyle descriptionStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.5,
  );

  // Label (SJLなど)
  static const TextStyle labelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  // Subtitle Label
  static const TextStyle subtitleLabelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );
}