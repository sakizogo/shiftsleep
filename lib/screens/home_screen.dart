import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/text_styles.dart';
import '../constants/dimensions.dart';
import '../widgets/sleep_button.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'ShiftSleep',
          style: AppTextStyles.headerStyle,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: AppColors.borderDefault,
            height: 1.0,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Main Button Section
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppDimensions.mainButtonSectionPaddingVertical,
                horizontal: AppDimensions.mainButtonSectionPaddingHorizontal,
              ),
              child: Column(
                children: [
                  Text(
                    '現在時刻: ${_getCurrentTime()}',
                    style: AppTextStyles.bodyTextStyle,
                  ),
                  const SizedBox(height: AppDimensions.paddingMedium),
                  SleepButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('入眠時刻を記録しました')),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Yesterday's Sleep Section
            Container(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(
                vertical: AppDimensions.sectionPaddingVertical,
                horizontal: AppDimensions.sectionPaddingHorizontal,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppColors.borderDefault,
                    width: AppDimensions.borderWidthThin,
                  ),
                  bottom: BorderSide(
                    color: AppColors.borderDefault,
                    width: AppDimensions.borderWidthThin,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '昨夜の睡眠',
                    style: AppTextStyles.sectionTitleStyle,
                  ),
                  const SizedBox(height: AppDimensions.paddingSmall),
                  Text(
                    '23:00 ～ 07:00',
                    style: AppTextStyles.bodyTextStyle,
                  ),
                  const SizedBox(height: AppDimensions.paddingSmall),
                  Text(
                    '8h 00m',
                    style: AppTextStyles.largeNumberStyle,
                  ),
                  const SizedBox(height: AppDimensions.paddingSmall),
                  Row(
                    children: List.generate(
                      3,
                      (index) => Padding(
                        padding: const EdgeInsets.only(
                          right: AppDimensions.paddingSmall,
                        ),
                        child: Text(
                          '⭐',
                          style: AppTextStyles.largeNumberStyle.copyWith(
                            fontSize: 20,
                            color: AppColors.starYellow,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.paddingSmall),
                  Text(
                    '修正可 (2日残り)',
                    style: AppTextStyles.captionStyle.copyWith(
                      color: AppColors.warningRed,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Circadian State Section
            Container(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(
                vertical: AppDimensions.sectionPaddingVertical,
                horizontal: AppDimensions.sectionPaddingHorizontal,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.borderDefault,
                    width: AppDimensions.borderWidthThin,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '体内時計の状態',
                    style: AppTextStyles.sectionTitleStyle,
                  ),
                  const SizedBox(height: AppDimensions.paddingMedium),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(
                            AppDimensions.paddingSmall,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.cardBgWarning,
                            border: Border.all(
                              color: AppColors.borderWarning,
                              width: AppDimensions.borderWidthThin,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppDimensions.borderRadiusSmall,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'SJL',
                                style: AppTextStyles.labelStyle,
                              ),
                              const SizedBox(height: 4.0),
                              Text(
                                '2.5時間',
                                style: AppTextStyles.statNumberStyle,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDimensions.gapMedium),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(
                            AppDimensions.paddingSmall,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.cardBgGray,
                            border: Border.all(
                              color: AppColors.borderDefault,
                              width: AppDimensions.borderWidthThin,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppDimensions.borderRadiusSmall,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'SRI',
                                style: AppTextStyles.labelStyle,
                              ),
                              const SizedBox(height: 4.0),
                              Text(
                                '35点',
                                style: AppTextStyles.statNumberStyle,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimensions.paddingMedium),
                  Container(
                    padding: const EdgeInsets.all(
                      AppDimensions.paddingSmall,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cardBgAlert,
                      border: Border(
                        left: BorderSide(
                          color: AppColors.warningRed,
                          width: AppDimensions.borderWidthMedium,
                        ),
                      ),
                    ),
                    child: Text(
                      '評価: 大きく乱れている',
                      style: AppTextStyles.captionStyle.copyWith(
                        color: AppColors.darkWarning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.paddingMedium),
                  Container(
                    padding: const EdgeInsets.all(
                      AppDimensions.paddingSmall,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundLight,
                      border: Border.all(
                        color: AppColors.borderDefault,
                        width: AppDimensions.borderWidthThin,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppDimensions.borderRadiusSmall,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '月曜朝が眠い理由:',
                          style: AppTextStyles.subtitleLabelStyle,
                        ),
                        const SizedBox(height: 8.0),
                        Text(
                          'SJL が 2.5時間あるため、体内時計は月曜朝に夜中 20:30相当と判定されています。',
                          style: AppTextStyles.descriptionStyle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Sleep Debt Section
            Container(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(
                vertical: AppDimensions.sectionPaddingVertical,
                horizontal: AppDimensions.sectionPaddingHorizontal,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.borderDefault,
                    width: AppDimensions.borderWidthThin,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '睡眠負債',
                    style: AppTextStyles.sectionTitleStyle,
                  ),
                  const SizedBox(height: AppDimensions.paddingSmall),
                  Text(
                    '-14h 30m',
                    style: AppTextStyles.debtNumberStyle,
                  ),
                  const SizedBox(height: AppDimensions.paddingMedium),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '今月平均',
                            style: AppTextStyles.bodyTextStyle,
                          ),
                          const SizedBox(height: 4.0),
                          Text(
                            '6h 24m',
                            style: AppTextStyles.statNumberStyle,
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '目標',
                            style: AppTextStyles.bodyTextStyle,
                          ),
                          const SizedBox(height: 4.0),
                          Text(
                            '7h 00m',
                            style: AppTextStyles.statNumberStyle,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Footer Buttons
            Padding(
              padding: const EdgeInsets.all(AppDimensions.footerPadding),
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: AppDimensions.gapMedium,
                crossAxisSpacing: AppDimensions.gapMedium,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildFooterButton(
                    icon: Icons.calendar_today,
                    label: 'シフト管理',
                    onPressed: () {},
                  ),
                  _buildFooterButton(
                    icon: Icons.settings,
                    label: '設定',
                    onPressed: () {},
                  ),
                  _buildFooterButton(
                    icon: Icons.bar_chart,
                    label: '詳細',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.borderDefault,
            width: AppDimensions.borderWidthThin,
          ),
          borderRadius: BorderRadius.circular(
            AppDimensions.borderRadiusSmall,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: AppColors.textPrimary,
              size: 24.0,
            ),
            const SizedBox(height: 4.0),
            Text(
              label,
              style: AppTextStyles.labelStyle.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _getCurrentTime() {
    DateTime now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}