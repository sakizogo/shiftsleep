import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../constants/colors.dart';
import '../constants/text_styles.dart';
import '../constants/dimensions.dart';
import '../widgets/sleep_button.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/screens/advice_detail_screen.dart';
import 'package:shiftsleep/services/alarm_service.dart';  // ← これを追加
import 'package:shiftsleep/screens/settings_screen.dart';
import 'package:shiftsleep/screens/edit_sleep_record_screen.dart';
import 'package:shiftsleep/screens/shift_management_screen.dart';
import 'package:shiftsleep/screens/shift_pattern_screen.dart';
import 'package:shiftsleep/screens/sleep_records_screen.dart';
import 'package:shiftsleep/screens/shift_detail_screen.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/constants/shift_enums.dart';

// Week 3 Day 5: シフト管理画面内の詳細状態管理
enum ShiftManagementView { calendar, details }

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  ShiftManagementView _shiftManagementView = ShiftManagementView.calendar;
  Map<DateTime, ShiftData>? _shiftDataMapForDetails;
  List<ShiftPatternModel>? _patternsForDetails;

  final ShiftRepository _shiftRepository = ShiftRepository();
  List<ShiftPatternModel> _patterns = [];
  bool _isLoadingPatterns = false;
  
  // ========== Week 3 Day 6-2 追加: シフト管理画面の state にアクセス ==========
  late GlobalKey<ShiftManagementScreenState> _shiftManagementKey;
  // ========================================================================

  // ========== Week 7 Phase 3: Timer for time update ==========
  Timer? _timeUpdateTimer;
  // ==========================================================

  @override
  void initState() {
    super.initState();
    
    // ========== Week 7 Phase 3: 1秒ごとに時刻を更新 ==========
    _timeUpdateTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        setState(() {
          // setState() のコールバック内は空でOK
          // build() が再実行されて _getCurrentTime() が新しい時刻を取得する
        });
      },
    );
    // =========================================================
    
    // ========== Week 3 Day 6-2 追加: GlobalKey を初期化 ==========
    _shiftManagementKey = GlobalKey<ShiftManagementScreenState>();
    // ===========================================================
    Future.microtask(
      () => context.read<SleepProvider>().loadAllSleepData(),
    );
    
    _loadPatterns();
  }

  @override
  void dispose() {
    // ========== Week 7 Phase 3: Timer をキャンセル（メモリリーク防止） ==========
    _timeUpdateTimer?.cancel();
    // =====================================================================
    super.dispose();
  }

  Future<void> _loadPatterns() async {
    setState(() {
      _isLoadingPatterns = true;
    });

    try {
      final patterns = await _shiftRepository.getAllPatterns();
    
      // ========== 古いパターン（colorIndex=0）を削除 ==========
      for (final pattern in patterns) {
        if (pattern.colorIndex == 0) {
          await _shiftRepository.deletePattern(pattern.id);
          print('🗑️  古いパターンを削除: ${pattern.patternName}');
        }
      }
    
      // 削除後に再度ロード
      final updatedPatterns = await _shiftRepository.getAllPatterns();
      // ====================================================
    
      setState(() {
        _patterns = updatedPatterns;
        _isLoadingPatterns = false;
      });
      print('Loaded ${updatedPatterns.length} patterns from DB');
    } catch (e) {
      print('Error loading patterns: $e');
      setState(() {
        _isLoadingPatterns = false;
      });
    }
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
            // ========== Week 3 Day 6-2 修正: シフト管理タブ切り替え時にリセット ==========
            // タブを切り替える際、常に ShiftManagementView をリセット
            _shiftManagementView = ShiftManagementView.calendar;
            // ========================================================================
          });
  
          // ========== Week 3 Day 6-2 修正: タブ切り替え時に loadShifts() を呼び出し ==========
          if (index == 1) {
            // パターンをリロード
            _loadPatterns();
            // シフト管理画面から DB にシフトを再ロード
            Future.delayed(const Duration(milliseconds: 100), () {
              _shiftManagementKey.currentState?.loadShifts();
            });
          }
          // ============================================================================
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

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return _buildHomeContent();
      case 1:
        if (_shiftManagementView == ShiftManagementView.details &&
            _shiftDataMapForDetails != null &&
            _patternsForDetails != null) {
          return ShiftDetailScreen(
            shiftDataMap: _shiftDataMapForDetails!,
            patterns: _patternsForDetails!,
            onBack: () {
              setState(() {
                _shiftManagementView = ShiftManagementView.calendar;
                _shiftDataMapForDetails = null;
                _patternsForDetails = null;
              });
              // ========== Week 3 Day 6-2 追加: 入力フォームをリセット＆シフトを再ロード ==========
              _loadPatterns();
              _shiftManagementKey.currentState?.clearShiftMap();
              _shiftManagementKey.currentState?.loadShifts();
              // ==============================================================
            },
          );
        } else {
          return ShiftManagementScreen(
            key: _shiftManagementKey,  // ========== Week 3 Day 6-2 修正: GlobalKey に変更 ==========
            patterns: _patterns,
            onNavigateToDetails: (shiftDataMap, patterns) {
              setState(() {
                _shiftDataMapForDetails = shiftDataMap as Map<DateTime, ShiftData>;
                _patternsForDetails = patterns as List<ShiftPatternModel>;
                _shiftManagementView = ShiftManagementView.details;
              });
            },
          );
        }
      case 2:
        return SettingsScreen(userId: 'test_user');
      case 3:
        return SleepRecordsScreen(userId: 'test_user');
      default:
        return _buildHomeContent();
    }
  }

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
                      // ========== Week 8 Phase 6 修正: 当日シフトから起床時刻を自動計算 ==========
                      await _calculateAndScheduleWakeUpTime(sleepProvider);
                      // ========================================================================
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
                            Text(
                              '${sleepProvider.lastBedtimeFormatted} ～ ${sleepProvider.lastWakeTimeFormatted}',
                              style: AppTextStyles.bodyTextStyle.copyWith(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(
                                height: AppDimensions.paddingMedium),

                            Text(
                              sleepProvider.lastSleepDurationFormatted,
                              style: AppTextStyles.largeNumberStyle.copyWith(
                                fontSize: 42,
                              ),
                            ),
                            const SizedBox(
                                height: AppDimensions.paddingMedium),

                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
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
              // ========== Week 7 A 追加: 分割睡眠セクション ==========
              // 【昨晩の睡眠】メイン睡眠 + 補助睡眠の詳細表示
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
                    Row(
                      children: [
                        Icon(
                          Icons.bedtime,
                          size: 20,
                          color: AppColors.primaryGradientStart,
                        ),
                        const SizedBox(width: AppDimensions.paddingSmall),
                        Text(
                          '睡眠の内訳',
                          style: AppTextStyles.sectionTitleStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // ========== メイン睡眠 + 補助睡眠 の 2列表示 ==========
                    Row(
                      children: [
                        // メイン睡眠
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(
                              AppDimensions.paddingSmall,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
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
                                  'メイン睡眠',
                                  style: AppTextStyles.labelStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6.0),
                                Text(
                                  sleepProvider.lastPrimarySleepFormatted,
                                  style: AppTextStyles.statNumberStyle
                                      .copyWith(
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  '（長時間睡眠）',
                                  style: AppTextStyles.descriptionStyle
                                      .copyWith(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AppDimensions.gapMedium),
                        // 補助睡眠
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(
                              AppDimensions.paddingSmall,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
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
                                  '補助睡眠',
                                  style: AppTextStyles.labelStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6.0),
                                Text(
                                  sleepProvider.lastSupplementarySleepFormatted,
                                  style: AppTextStyles.statNumberStyle
                                      .copyWith(
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  '（昼寝など）',
                                  style: AppTextStyles.descriptionStyle
                                      .copyWith(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // ========== 総睡眠時間 ==========
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(
                        AppDimensions.paddingSmall,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primaryGradientStart.withOpacity(0.1),
                            AppColors.primaryGradientEnd.withOpacity(0.1),
                          ],
                        ),
                        border: Border.all(
                          color: AppColors.primaryGradientStart
                              .withOpacity(0.3),
                          width: AppDimensions.borderWidthThin,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppDimensions.borderRadiusSmall,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '合計睡眠時間',
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            sleepProvider.lastTotalSleepFormatted,
                            style: AppTextStyles.statNumberStyle.copyWith(
                              fontSize: 16,
                              color: AppColors.primaryGradientStart,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
// ========================================================================
              // ========== Week 7 A 追加: 睡眠改善アドバイスセクション ==========
              // 無料版：最優先アドバイス 1個
              // 有料版：優先度1,2のアドバイス 最大5個
              if (sleepProvider.hasAdvice)
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
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb,
                            size: 20,
                            color: AppColors.primaryGradientStart,
                          ),
                          const SizedBox(width: AppDimensions.paddingSmall),
                          Text(
                            '💡 改善アドバイス',
                            style: AppTextStyles.sectionTitleStyle,
                          ),
                          if (sleepProvider.isPremiumUser)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: AppDimensions.paddingSmall,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                  vertical: 2.0,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGradientStart,
                                  borderRadius: BorderRadius.circular(4.0),
                                ),
                                child: Text(
                                  'プレミアム',
                                  style: AppTextStyles.labelStyle.copyWith(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.paddingMedium),

                      // ========== メインアドバイス（優先度1） ==========
                      if (sleepProvider.topAdvice != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(
                            AppDimensions.paddingMedium,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.primaryGradientStart.withOpacity(0.15),
                                AppColors.primaryGradientEnd.withOpacity(0.15),
                              ],
                            ),
                            border: Border.all(
                              color: AppColors.primaryGradientStart
                                  .withOpacity(0.5),
                              width: AppDimensions.borderWidthThin,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppDimensions.borderRadiusMedium,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // タイトル
                              Text(
                                sleepProvider.topAdvice!.title,
                                style: AppTextStyles.subtitleLabelStyle
                                    .copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.primaryGradientStart,
                                ),
                              ),
                              const SizedBox(
                                height: AppDimensions.paddingMedium,
                              ),

                              // 説明
                              Text(
                                sleepProvider.topAdvice!.description,
                                style: AppTextStyles.bodyTextStyle.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.5,
                                ),
                              ),

                              // アクションTip
                              if (sleepProvider.topAdvice!.actionTip != null)
                                Column(
                                  children: [
                                    const SizedBox(
                                      height: AppDimensions.paddingMedium,
                                    ),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(
                                        AppDimensions.paddingSmall,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(
                                          AppDimensions.borderRadiusSmall,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            '💡 ',
                                            style: AppTextStyles.bodyTextStyle,
                                          ),
                                          Expanded(
                                            child: Text(
                                              sleepProvider
                                                  .topAdvice!.actionTip!,
                                              style: AppTextStyles
                                                  .descriptionStyle
                                                  .copyWith(
                                                color: AppColors
                                                    .primaryGradientStart,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      
// ========== 「全てのアドバイスを見る」ボタン ==========
                      if (sleepProvider.hasAdvice)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppDimensions.paddingMedium,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AdviceDetailScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('全てのアドバイスを見る'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    AppColors.primaryGradientStart,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppDimensions.borderRadiusMedium,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        
                      // ========== 追加アドバイス（有料版のみ）==========
                      if (sleepProvider.isPremiumUser &&
                          sleepProvider.displayedAdvice.length > 1)
                        Column(
                          children: [
                            const SizedBox(
                              height: AppDimensions.paddingMedium,
                            ),
                            ...sleepProvider.displayedAdvice
                                .skip(1)
                                .map((advice) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: AppDimensions.paddingSmall,
                                      ),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(
                                          AppDimensions.paddingSmall,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: AppColors.borderDefault,
                                            width: AppDimensions
                                                .borderWidthThin,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(
                                            AppDimensions.borderRadiusSmall,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              advice.title,
                                              style: AppTextStyles
                                                  .labelStyle
                                                  .copyWith(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 4.0),
                                            Text(
                                              advice.description,
                                              style: AppTextStyles
                                                  .descriptionStyle
                                                  .copyWith(
                                                fontSize: 11,
                                                color: AppColors
                                                    .textSecondary,
                                              ),
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ],
                        ),

                      // ========== 「もっと見る」ボタン（有料版のみ）==========
                      if (sleepProvider.isPremiumUser &&
                          sleepProvider.allAdvice.length >
                              sleepProvider.displayedAdvice.length)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppDimensions.paddingMedium,
                          ),
                          child: Center(
                            child: TextButton(
                              onPressed: () {
                                // TODO: 詳細アドバイス画面へ遷移
                                print(
                                    'Navigate to detailed advice screen');
                              },
                              child: Text(
                                '全てのアドバイスを見る',
                                style: AppTextStyles.labelStyle.copyWith(
                                  color: AppColors.primaryGradientStart,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
// ====================================================================
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
                            // ========== Week 9-1 追加: 睡眠集計セクション（当日/今週/今月）==========
                            // Wong 2011 パレット対応（色盲アクセシビリティ）
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
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.bar_chart,
                                        size: 20,
                                        color: AppColors.primaryGradientStart,
                                      ),
                                      const SizedBox(width: AppDimensions.paddingSmall),
                                      Text(
                                        '睡眠集計',
                                        style: AppTextStyles.sectionTitleStyle,
                                      ),
                                    ],
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
                                            color: AppColors.summaryTodayBg,
                                            border: Border.all(
                                              color: AppColors.summaryTodayBorder,
                                              width: AppDimensions.borderWidthThin,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              AppDimensions.borderRadiusSmall,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                '当日',
                                                style: AppTextStyles.labelStyle.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                  color: AppColors.summaryTodayBorder,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 6.0),
                                              Text(
                                                sleepProvider.todaysSleepDurationFormatted,
                                                style: AppTextStyles.statNumberStyle.copyWith(
                                                  fontSize: 16,
                                                  color: AppColors.summaryTodayText,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 4.0),
                                              Text(
                                                '今日の合計',
                                                style: AppTextStyles.descriptionStyle.copyWith(
                                                  fontSize: 10,
                                                  color: AppColors.summaryTodayBorder,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: AppDimensions.gapSmall),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(
                                            AppDimensions.paddingSmall,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.summaryWeekBg,
                                            border: Border.all(
                                              color: AppColors.summaryWeekBorder,
                                              width: AppDimensions.borderWidthThin,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              AppDimensions.borderRadiusSmall,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                '今週',
                                                style: AppTextStyles.labelStyle.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                  color: AppColors.summaryWeekBorder,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 6.0),
                                              Text(
                                                sleepProvider.thisWeekTotalSleepFormatted,
                                                style: AppTextStyles.statNumberStyle.copyWith(
                                                  fontSize: 16,
                                                  color: AppColors.summaryWeekText,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 4.0),
                                              Text(
                                                '月～日累計',
                                                style: AppTextStyles.descriptionStyle.copyWith(
                                                  fontSize: 10,
                                                  color: AppColors.summaryWeekBorder,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: AppDimensions.gapSmall),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(
                                            AppDimensions.paddingSmall,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.summaryMonthBg,
                                            border: Border.all(
                                              color: AppColors.summaryMonthBorder,
                                              width: AppDimensions.borderWidthThin,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              AppDimensions.borderRadiusSmall,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                '今月',
                                                style: AppTextStyles.labelStyle.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                  color: AppColors.summaryMonthBorder,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 6.0),
                                              Text(
                                                sleepProvider.thisMonthAverageSleepFormatted,
                                                style: AppTextStyles.statNumberStyle.copyWith(
                                                  fontSize: 16,
                                                  color: AppColors.summaryMonthText,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 4.0),
                                              Text(
                                                '平均睡眠時間',
                                                style: AppTextStyles.descriptionStyle.copyWith(
                                                  fontSize: 10,
                                                  color: AppColors.summaryMonthBorder,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // ========================================================================
              const SizedBox(height: AppDimensions.paddingLarge),
                            // ========== Week 3 Day 5 修正: シフト体系登録ボタン（移動・スタイル改善） ==========
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
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ShiftPatternScreen(
                                          mode: ShiftPatternMode.register,
                                          existingPatterns: _patterns,
                                        ),
                                      ),
                                    );
                      
                                    // ========== Fix：戻ってきたパターンを反映 ==========
                                    if (result is List<ShiftPatternModel>) {
                                      setState(() {
                                        _patterns = result;
                                        _selectedIndex = 1;  // シフト管理タブに切り替え
                                      });
                                    } else if (result == 1) {
                                      // 後方互換性のため
                                      setState(() {
                                        _selectedIndex = 1;
                                      });
                                      await _loadPatterns();
                                    }
                                    // ==================================================
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    elevation: 0,
                                    side: BorderSide(
                                      color: AppColors.primaryGradientStart,
                                      width: 2,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      vertical: AppDimensions.paddingMedium,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppDimensions.borderRadiusMedium,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'シフト体系登録',
                                    style: AppTextStyles.bodyTextStyle.copyWith(
                                      color: AppColors.primaryGradientStart,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // ================================================================================================================================================================

            ],
          ),
        );
      },
    );
  }

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
  /// ========== Week 8 Phase 6 追加: 当日シフトから起床時刻を自動計算 ==========
  /// 
  /// 処理フロー:
  /// 1. 当日（今日）のシフトを取得
  /// 2. シフトの出勤時刻を取得
  /// 3. AppSettings からアラーム時間を取得
  /// 4. 起床時刻を計算: 出勤時刻 - アラーム時間
  /// 5. SleepProvider に設定
  /// 6. アラームをスケジュール
  Future<void> _calculateAndScheduleWakeUpTime(SleepProvider sleepProvider) async {
    try {
      print('🌙 [HomeScreen] Step 1: 当日シフトを検索中...');
      
      // Step 1: 当日のシフトを取得
      final today = DateTime.now();
      final shiftsForToday = await _shiftRepository.getShiftsForDateRange(today, today);
      
      if (shiftsForToday.isEmpty) {
        print('⚠️  [HomeScreen] 今日のシフトがありません');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('今日のシフトが設定されていません')),
        );
        return;
      }

      print('✅ [HomeScreen] Step 1完了: シフト${shiftsForToday.length}件を取得');

      // Step 2: シフトパターンから出勤時刻を取得
      print('🌙 [HomeScreen] Step 2: シフトパターンを検索中...');
      final shift = shiftsForToday.first;
      final patternId = shift['pattern_id'] as String;
      final allPatterns = await _shiftRepository.getAllPatterns();
      final pattern = allPatterns.firstWhere(
        (p) => p.id == patternId,
        orElse: () {
          throw Exception('Pattern not found: $patternId');
        },
      );

      if (pattern.startTime == null) {
        print('⚠️  [HomeScreen] シフトパターンに出勤時刻がありません');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('出勤時刻が設定されていません')),
        );
        return;
      }

      print('✅ [HomeScreen] Step 2完了: 出勤時刻 ${pattern.startTime!.hour}:${pattern.startTime!.minute.toString().padLeft(2, '0')}');

      // Step 3: AppSettings からアラーム時間を取得
      print('🌙 [HomeScreen] Step 3: AppSettings を検索中...');
      final settings = await _shiftRepository.getAppSettings('test_user');
      final alarmMinutesBefore = settings?.alarmTimeBeforeShift ?? 30;  // デフォルト: 30分前

      print('✅ [HomeScreen] Step 3完了: アラーム時間 = ${alarmMinutesBefore}分前');

      // Step 4: 起床時刻を計算
      print('🌙 [HomeScreen] Step 4: 起床時刻を計算中...');
      final shiftStartTime = pattern.startTime!;
      final shiftStartDateTime = DateTime(
        today.year,
        today.month,
        today.day,
        shiftStartTime.hour,
        shiftStartTime.minute,
      );

      final wakeUpDateTime = shiftStartDateTime.subtract(Duration(minutes: alarmMinutesBefore));
      print('✅ [HomeScreen] Step 4完了: 起床時刻 = '
          '${wakeUpDateTime.hour}:${wakeUpDateTime.minute.toString().padLeft(2, '0')}');

      // Step 5: SleepProvider に設定
      print('🌙 [HomeScreen] Step 5: SleepProvider に起床時刻を設定中...');
      sleepProvider.setAutoWakeUpTime(wakeUpDateTime);
      print('✅ [HomeScreen] Step 5完了: SleepProvider に設定されました');

      // Step 6: アラームをスケジュール
      print('🌙 [HomeScreen] Step 6: アラームをスケジュール中...');
      await AlarmService.scheduleAlarmForShift(
        shiftDate: today,
        alarmTime: TimeOfDay(hour: wakeUpDateTime.hour, minute: wakeUpDateTime.minute),
        preAlarmEnabled: false,  // 「今から寝る」時点では事前アラーム不要
      );
      print('✅ [HomeScreen] Step 6完了: アラームをスケジュールしました');

      // 完了メッセージ
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${wakeUpDateTime.hour}:${wakeUpDateTime.minute.toString().padLeft(2, '0')} に起床アラームをセットしました',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      print('✅✅✅ [HomeScreen] Week 8 Phase 6 完了！');
    } catch (e) {
      print('❌ [HomeScreen] エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }
  // ========================================================================  
}