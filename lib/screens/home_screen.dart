import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/colors.dart';
import '../constants/text_styles.dart';
import '../constants/dimensions.dart';
import '../widgets/sleep_button.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/screens/settings_screen.dart';
import 'package:shiftsleep/screens/edit_sleep_record_screen.dart';
import 'sleep_records_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 画面読み込み時にデータを取得
    Future.microtask(
      () => context.read<SleepProvider>().loadAllSleepData(),
    );
  }

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
      body: Consumer<SleepProvider>(
        builder: (context, sleepProvider, _) {
          if (sleepProvider.isLoading) {
            return Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.primaryGradientStart),
              ),
            );
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                // ========================
                // Main Button Section
                // ========================
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
                        onPressed: () async {
                          // 新規睡眠記録を挿入後、最新データを再ロード
                          await sleepProvider.loadLatestSleepData();
                        },
                      ),
                    ],
                  ),
                ),

                // ========================
                // Yesterday's Sleep Section
                // ========================
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

                      // 実データ表示
                      if (sleepProvider.latestRecord != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 時刻表示
                            Text(
                              '${sleepProvider.lastBedtimeFormatted} ～ ${sleepProvider.lastWakeTimeFormatted}',
                              style: AppTextStyles.bodyTextStyle,
                            ),
                            const SizedBox(height: AppDimensions.paddingSmall),
                            // 睡眠時間
                            Text(
                              sleepProvider.lastSleepDurationFormatted,
                              style: AppTextStyles.largeNumberStyle,
                            ),
                            const SizedBox(height: AppDimensions.paddingSmall),
                            // 星評価（動的）
                            Row(
                              children: List.generate(
                                5,
                                (index) => Padding(
                                  padding: const EdgeInsets.only(
                                    right: AppDimensions.paddingSmall,
                                  ),
                                  child: Icon(
                                    Icons.star,
                                    size: 20,
                                    color: index < _getStarCount(sleepProvider)
                                        ? AppColors.starYellow
                                        : AppColors.borderDefault,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppDimensions.paddingSmall),
                            // 修正ボタン
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        EditSleepRecordScreen(
                                          record: sleepProvider.latestRecord!,
                                        ),
                                  ),
                                );
                              },
                              child: Text(
                                '修正する',
                                style: AppTextStyles.bodyTextStyle.copyWith(
                                  color: AppColors.primaryGradientStart,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          'データなし',
                          style: AppTextStyles.bodyTextStyle.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),

                // ========================
                // Circadian State Section
                // ========================
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
                          // SJL カード
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
                                    '${sleepProvider.sjl.toStringAsFixed(1)}h',
                                    style: AppTextStyles.statNumberStyle,
                                  ),
                                  const SizedBox(height: 4.0),
                                  Text(
                                    sleepProvider.sjlEvaluation,
                                    style: AppTextStyles.labelStyle.copyWith(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: AppDimensions.gapMedium),
                          // SRI カード
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
                                    '${sleepProvider.sri.toStringAsFixed(0)}',
                                    style: AppTextStyles.statNumberStyle,
                                  ),
                                  const SizedBox(height: 4.0),
                                  Text(
                                    sleepProvider.sriEvaluation,
                                    style: AppTextStyles.labelStyle.copyWith(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.paddingMedium),
                      // 警告ボックス
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
                          '評価: ${sleepProvider.sjlEvaluation}',
                          style: AppTextStyles.captionStyle.copyWith(
                            color: AppColors.darkWarning,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDimensions.paddingMedium),
                      // 説明ボックス
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
                              'SJL が大きい理由:',
                              style: AppTextStyles.subtitleLabelStyle,
                            ),
                            const SizedBox(height: 8.0),
                            Text(
                              sleepProvider.sjl >= 2
                                  ? 'SJLが2時間以上あるため、体内時計が大きく乱れています。'
                                  : sleepProvider.sjl >= 1
                                      ? 'SJLが1時間以上あるため、やや体内時計が乱れています。'
                                      : 'あなたの体内時計は正常範囲です。',
                              style: AppTextStyles.descriptionStyle,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ========================
                // Sleep Debt Section
                // ========================
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
                        sleepProvider.sleepDebtFormatted,
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
                                _calculateMonthlyAverage(sleepProvider),
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

                // ========================
                // Footer Buttons
                // ========================
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
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('シフト管理画面（未実装）'),
                            ),
                          );
                        },
                      ),
                      _buildFooterButton(
                        icon: Icons.settings,
                        label: '設定',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const SettingsScreen(userId: 'test_user'),
                            ),
                          );
                        },
                      ),
                      _buildFooterButton(
                        icon: Icons.list,
                        label: '詳細',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SleepRecordsScreen(
                                userId: 'test_user',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ========================
  // Helper Methods
  // ========================

  int _getStarCount(SleepProvider provider) {
    if (provider.latestRecord == null) return 0;

    final duration = provider.latestRecord!.wakeTime.difference(
      provider.latestRecord!.bedtime,
    );

    final adjustedDuration =
        duration.isNegative ? duration + Duration(days: 1) : duration;

    final hours = adjustedDuration.inHours.toDouble();

    if (hours >= 7) return 5;
    if (hours >= 6) return 4;
    if (hours >= 5) return 3;
    if (hours >= 4) return 2;
    return 1;
  }

  String _calculateMonthlyAverage(SleepProvider provider) {
    if (provider.last30DaysRecords.isEmpty) {
      return '--:--';
    }

    int totalMinutes = 0;
    for (final record in provider.last30DaysRecords) {
      final duration = record.wakeTime.difference(record.bedtime);
      if (duration.isNegative) {
        totalMinutes += (duration.inMinutes.toInt() + 24 * 60);
      } else {
        totalMinutes += duration.inMinutes.toInt();
      }
    }

    final averageMinutes = totalMinutes ~/ provider.last30DaysRecords.length;
    return '${averageMinutes ~/ 60}h ${averageMinutes % 60}m';
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
