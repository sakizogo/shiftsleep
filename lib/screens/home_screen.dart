import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/colors.dart';
import '../constants/text_styles.dart';
import '../constants/dimensions.dart';
import '../widgets/sleep_button.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/screens/settings_screen.dart';
import 'package:shiftsleep/screens/edit_sleep_record_screen.dart';
import 'package:shiftsleep/screens/shift_management_screen.dart';
import 'package:shiftsleep/screens/shift_pattern_screen.dart';
import 'package:shiftsleep/screens/sleep_records_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0; // ナビゲーション状態管理

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
      body: _buildPage(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primaryGradientStart,
        unselectedItemColor: AppColors.textMuted,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'ホーム',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'シフト管理',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '設定',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: '詳細',
          ),
        ],
      ),
    );
  }

  /// インデックスに応じてページを返す
  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return _buildHomeContent();
      case 1:
        return ShiftManagementScreen(patterns: []);
      case 2:
        return SettingsScreen(userId: 'test_user');
      case 3:
        return SleepRecordsScreen(userId: 'test_user');
      default:
        return _buildHomeContent();
    }
  }

  /// ホーム画面コンテンツ
  Widget _buildHomeContent() {
    return Consumer<SleepProvider>(
      builder: (context, sleepProvider, _) {
        if (sleepProvider.isLoading) {
          return Center(
            child: CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation(AppColors.primaryGradientStart),
            ),
          );
        }

        return SingleChildScrollView(
          child: Column(
            children: [
              // ========================
              // Main Button Section with Gradient
              // ========================
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryGradientStart,
                      AppColors.primaryGradientEnd,
                    ],
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimensions.mainButtonSectionPaddingVertical,
                  horizontal:
                      AppDimensions.mainButtonSectionPaddingHorizontal,
                ),
                child: Column(
                  children: [
                    Text(
                      _getCurrentTime(),
                      style: AppTextStyles.headerStyle.copyWith(
                        fontSize: 32,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.paddingSmall),
                    Text(
                      '現在時刻',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.paddingLarge),
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
              // Yesterday's Sleep Section - Card Style
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
                    // Section Title with Icon
                    Row(
                      children: [
                        Icon(
                          Icons.nights_stay,
                          size: 20,
                          color: AppColors.primaryGradientStart,
                        ),
                        const SizedBox(width: AppDimensions.paddingSmall),
                        Text(
                          '昨夜の睡眠',
                          style: AppTextStyles.sectionTitleStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // Data Card
                    if (sleepProvider.latestRecord != null)
                      Container(
                        padding: const EdgeInsets.all(
                          AppDimensions.paddingMedium,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: AppColors.borderDefault,
                            width: AppDimensions.borderWidthThin,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusMedium,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Time Display
                            Text(
                              '${sleepProvider.lastBedtimeFormatted} ～ ${sleepProvider.lastWakeTimeFormatted}',
                              style: AppTextStyles.bodyTextStyle.copyWith(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(
                                height: AppDimensions.paddingMedium),

                            // Sleep Duration - Large
                            Text(
                              sleepProvider.lastSleepDurationFormatted,
                              style: AppTextStyles.largeNumberStyle.copyWith(
                                fontSize: 42,
                              ),
                            ),
                            const SizedBox(
                                height: AppDimensions.paddingMedium),

                            // Star Rating + Edit Button
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                // Stars
                                Row(
                                  children: List.generate(
                                    5,
                                    (index) => Padding(
                                      padding: const EdgeInsets.only(
                                        right: AppDimensions.gapSmall,
                                      ),
                                      child: Icon(
                                        Icons.star,
                                        size: 20,
                                        color: index <
                                                _getStarCount(sleepProvider)
                                            ? AppColors.starYellow
                                            : AppColors.borderDefault,
                                      ),
                                    ),
                                  ),
                                ),
                                // Edit Button
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
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppDimensions.paddingSmall,
                                      vertical: AppDimensions.paddingXSmall,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryGradientStart
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(
                                        AppDimensions.borderRadiusSmall,
                                      ),
                                    ),
                                    child: Text(
                                      '修正',
                                      style:
                                          AppTextStyles.labelStyle.copyWith(
                                        color: AppColors.primaryGradientStart,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(
                          AppDimensions.paddingMedium,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cardBgGray,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusMedium,
                          ),
                        ),
                        child: Text(
                          'データなし',
                          style: AppTextStyles.bodyTextStyle.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ========================
              // Circadian State Section - Compact
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
                    // Section Title with Icon
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 20,
                          color: AppColors.primaryGradientStart,
                        ),
                        const SizedBox(width: AppDimensions.paddingSmall),
                        Text(
                          '体内時計の状態',
                          style: AppTextStyles.sectionTitleStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // SJL & SRI Cards
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
                                  'SJL\n(体内時計負担数)',
                                  style: AppTextStyles.labelStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                  textAlign: TextAlign.center,
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
                                  'SRI\n(睡眠規則性指数)',
                                  style: AppTextStyles.labelStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                  textAlign: TextAlign.center,
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

                    // Compact Description Box
                    Container(
                      padding: const EdgeInsets.all(
                        AppDimensions.paddingSmall,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardBgAlert,
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
                            'あなたの体内時計:',
                            style: AppTextStyles.subtitleLabelStyle.copyWith(
                              color: AppColors.darkWarning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6.0),
                          Text(
                            sleepProvider.sjl >= 2
                                ? 'SJLが2時間以上あるため、体内時計が大きく乱れています。定期的な就寝時間の調整が効果的です。'
                                : sleepProvider.sjl >= 1
                                    ? 'SJLが1時間以上あるため、体内時計がやや乱れています。'
                                    : '体内時計は正常範囲です。良好な睡眠リズムを維持してください。',
                            style: AppTextStyles.descriptionStyle.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ========================
              // Sleep Debt Section - Highlighted
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
                    // Section Title with Icon
                    Row(
                      children: [
                        Icon(
                          Icons.trending_down,
                          size: 20,
                          color: AppColors.warningRed,
                        ),
                        const SizedBox(width: AppDimensions.paddingSmall),
                        Text(
                          '睡眠負債',
                          style: AppTextStyles.sectionTitleStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // Debt Number Highlighted
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(
                        AppDimensions.paddingMedium,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardBgAlert,
                        border: Border.all(
                          color: AppColors.warningRed.withOpacity(0.3),
                          width: AppDimensions.borderWidthThin,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppDimensions.borderRadiusMedium,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          sleepProvider.sleepDebtFormatted,
                          style: AppTextStyles.debtNumberStyle,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // Average & Target
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
                              style: AppTextStyles.statNumberStyle.copyWith(
                                color: AppColors.primaryGradientStart,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ========================
              // 下部パディング（BottomNavBar用）
              // ========================
              const SizedBox(height: AppDimensions.paddingLarge),
            ],
          ),
        );
      },
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

  String _getCurrentTime() {
    DateTime now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}