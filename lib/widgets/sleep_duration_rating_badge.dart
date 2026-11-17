import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/services/sleep_record_kind.dart';

/// N110：評価ごとの文字の色（白地で 4.5:1 以上。不足・長すぎは darkWarning、良好は summaryMonthText、補助はふつうの文字色）
Color sleepDurationRatingColor(SleepDurationRating rating) {
  switch (rating) {
    case SleepDurationRating.short:
    case SleepDurationRating.tooLong:
      return AppColors.darkWarning;
    case SleepDurationRating.good:
      return AppColors.summaryMonthText;
    case SleepDurationRating.supplementary:
      return AppColors.textPrimary;
  }
}

/// N110：評価の札（白地・色付きの細い枠と文字。色だけに頼らない）
class SleepDurationRatingBadge extends StatelessWidget {
  final SleepDurationRating rating;
  final String label;

  const SleepDurationRatingBadge({super.key, required this.rating, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = sleepDurationRatingColor(rating);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Text(
        label,
        style: AppTextStyles.captionStyle.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}
