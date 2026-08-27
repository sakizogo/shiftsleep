import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/premium_service.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/screens/vacation_settings_screen.dart';
import 'package:shiftsleep/screens/vacation_usage_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String userId;

  const SettingsScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TimeOfDay _wakeUpTime = const TimeOfDay(hour: 7, minute: 0);
  AlarmMode _alarmMode = AlarmMode.once;
  String _selectedAlarmSound = 'default';
  double _soundVolume = 1.0;
  int _alarmTimeBeforeShift = 30;
  bool _advicePromoVisible = true;
  bool _isPremiumUser = false;
  bool _isLoading = false;

  final ShiftRepository _shiftRepository = ShiftRepository();
  final PremiumService _premiumService = PremiumService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _shiftRepository.getAppSettings('test_user');

      if (settings != null && mounted) {
        print('✅ 設定を読み込み: 起床時刻=${settings.wakeUpTime}, アラーム時間=${settings.alarmTimeBeforeShift}分前, 音=${settings.selectedAlarmSound}, promoVisible=${settings.advicePromoVisible}, isPremium=${settings.isPremiumUser}');

        final timeParts = settings.wakeUpTime.split(':');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);

        setState(() {
          _wakeUpTime = TimeOfDay(hour: hour, minute: minute);
          _alarmTimeBeforeShift = settings.alarmTimeBeforeShift;
          _selectedAlarmSound = settings.selectedAlarmSound;
          _advicePromoVisible = settings.advicePromoVisible;
          _isPremiumUser = settings.isPremiumUser;
        });
      }
    } catch (e) {
      print('⚠️ 設定読み込みエラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          backgroundColor: AppColors.backgroundLight,
          elevation: 0,
          centerTitle: true,
          title: Text(
            '設定',
            style: AppTextStyles.headerStyle,
          ),
          foregroundColor: AppColors.textPrimary,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(
              color: AppColors.borderDefault,
              height: 1.0,
            ),
          ),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppDimensions.sectionPaddingVertical,
              horizontal: AppDimensions.sectionPaddingHorizontal,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💳 プレミアム版ステータス',
                  style: AppTextStyles.sectionTitleStyle,
                ),
                const SizedBox(height: AppDimensions.paddingMedium),

                Container(
                  padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                  decoration: BoxDecoration(
                    color: _isPremiumUser
                        ? Colors.green.withOpacity(0.05)
                        : Colors.grey.withOpacity(0.05),
                    border: Border.all(
                      color: _isPremiumUser
                          ? Colors.green
                          : AppColors.borderDefault,
                    ),
                    borderRadius: BorderRadius.circular(
                      AppDimensions.borderRadiusMedium,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'あなたのプラン',
                                style: AppTextStyles.bodyTextStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8.0),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12.0,
                                  vertical: 4.0,
                                ),
                                decoration: BoxDecoration(
                                  color: _isPremiumUser
                                      ? Colors.green
                                      : AppColors.textMuted,
                                  borderRadius: BorderRadius.circular(12.0),
                                ),
                                child: Text(
                                  _isPremiumUser ? 'プレミアム版 ✨' : '無料版',
                                  style: AppTextStyles.bodyTextStyle.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            _isPremiumUser ? Icons.check_circle : Icons.info,
                            color: _isPremiumUser ? Colors.green : AppColors.textMuted,
                            size: 40,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.paddingMedium),

                      if (!_isPremiumUser) ...[
                        Text(
                          'プレミアム版でできることは：',
                          style: AppTextStyles.bodyTextStyle.copyWith(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8.0),
                        _buildBenefitItem('📊 詳細なアドバイスを取得'),
                        _buildBenefitItem('🎯 最大5つの改善提案'),
                        _buildBenefitItem('💾 すべての睡眠データを保存'),
                        const SizedBox(height: AppDimensions.paddingMedium),
                      ],

                      if (!_isPremiumUser)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _showPaywall,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGradientStart,
                              disabledBackgroundColor: AppColors.textMuted,
                              padding: EdgeInsets.symmetric(
                                vertical: AppDimensions.paddingMedium,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppDimensions.borderRadiusMedium,
                                ),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    '✨ プレミアム版にアップグレード（¥980/月）',
                                    style: AppTextStyles.bodyTextStyle.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            vertical: AppDimensions.paddingMedium,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(
                              AppDimensions.borderRadiusMedium,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '✅ プレミアム版をご利用中です',
                              style: AppTextStyles.bodyTextStyle.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: AppDimensions.paddingLarge),
                const SizedBox(height: AppDimensions.paddingLarge),

                Text(
                  '🔔 アラーム設定',
                  style: AppTextStyles.sectionTitleStyle,
                ),
                const SizedBox(height: AppDimensions.paddingMedium),

                Container(
                  padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.borderDefault),
                    borderRadius: BorderRadius.circular(
                      AppDimensions.borderRadiusMedium,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '起床時刻',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      const SizedBox(height: 8.0),
                      Consumer<SleepProvider>(
                        builder: (context, sleepProvider, _) {
                          final displayWakeUpTime = sleepProvider.autoWakeUpTimeOfDay ?? _wakeUpTime;
                          return Row(
                            children: [
                              Text(
                                '${displayWakeUpTime.hour.toString().padLeft(2, '0')}:${displayWakeUpTime.minute.toString().padLeft(2, '0')}',
                                style: AppTextStyles.largeNumberStyle.copyWith(fontSize: 32),
                              ),
                              const Spacer(),
                              ElevatedButton(
                                onPressed: () => _selectWakeUpTime(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryGradientStart,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
                                  ),
                                ),
                                child: Text('変更', style: AppTextStyles.bodyTextStyle.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: AppDimensions.paddingLarge),

                      Text(
                        '出勤前アラーム',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        'シフト出勤予定時刻の何分前に通知します',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      DropdownButton<int>(
                        value: _alarmTimeBeforeShift,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('無効（アラームなし）'),
                          ),
                          ...List.generate(
                            (180 - 30) ~/ 10 + 1,
                            (index) {
                              final minutes = 30 + (index * 10);
                              return DropdownMenuItem(
                                value: minutes,
                                child: Text('$minutes分前'),
                              );
                            },
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _alarmTimeBeforeShift = value;
                            });
                            _updateWakeUpTimeInProvider();
                          }
                        },
                      ),
                      const SizedBox(height: AppDimensions.paddingLarge),

                      Text(
                        'アラームモード',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        children: [
                          Expanded(
                            child: _buildAlarmModeButton(AlarmMode.none),
                          ),
                          const SizedBox(width: AppDimensions.paddingSmall),
                          Expanded(
                            child: _buildAlarmModeButton(AlarmMode.once),
                          ),
                          const SizedBox(width: AppDimensions.paddingSmall),
                          Expanded(
                            child: _buildAlarmModeButton(AlarmMode.twice),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.paddingLarge),

                      Text(
                        'アラーム音',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      DropdownButton<String>(
                        value: _selectedAlarmSound,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'default', child: Text('デフォルト音')),
                          DropdownMenuItem(value: 'gentle', child: Text('やさしい音')),
                          DropdownMenuItem(value: 'harsh', child: Text('強めの音')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedAlarmSound = value!;
                          });
                        },
                      ),
                      const SizedBox(height: AppDimensions.paddingLarge),

                      Text(
                        '音量',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        children: [
                          Icon(
                            Icons.volume_down,
                            color: AppColors.textMuted,
                          ),
                          Expanded(
                            child: Slider(
                              value: _soundVolume,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (value) {
                                setState(() {
                                  _soundVolume = value;
                                });
                              },
                              activeColor:
                                  AppColors.primaryGradientStart,
                              inactiveColor: AppColors.borderDefault,
                            ),
                          ),
                          Icon(
                            Icons.volume_up,
                            color: AppColors.primaryGradientStart,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8.0),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _testAlarmSound,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warningRed,
                        ),
                        child: Text(
                          '🔊 テストアラーム',
                          style: AppTextStyles.bodyTextStyle.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppDimensions.paddingLarge),

                Text(
                  '📋 有給管理',
                        style: AppTextStyles.sectionTitleStyle,
                      ),
                      const SizedBox(height: AppDimensions.paddingMedium),

                      Container(
                        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppColors.borderDefault),
                          borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VacationSettingsScreen(
                                        userId: widget.userId,
                                      ),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryGradientStart,
                                  padding: EdgeInsets.symmetric(vertical: AppDimensions.paddingMedium),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
                                  ),
                                ),
                                child: Text(
                                  '⚙️ 有給設定（入社日・付与日数）',
                                  style: AppTextStyles.bodyTextStyle.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppDimensions.paddingMedium),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VacationUsageScreen(
                                        userId: widget.userId,
                                      ),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryGradientStart,
                                  padding: EdgeInsets.symmetric(vertical: AppDimensions.paddingMedium),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
                                  ),
                                ),
                                child: Text(
                                  '📝 有給使用記録',
                                  style: AppTextStyles.bodyTextStyle.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '💡 改善アドバイス表示設定',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'プレミアム版案内を表示',
                                style: AppTextStyles.bodyTextStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4.0),
                              Text(
                                'アドバイス詳細画面で有料版の\nプロモーション表示を ON/OFF',
                                style: AppTextStyles.bodyTextStyle.copyWith(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: _advicePromoVisible,
                            onChanged: (value) {
                              setState(() {
                                _advicePromoVisible = value;
                              });
                            },
                            activeColor: AppColors.primaryGradientStart,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppDimensions.paddingLarge),
                const SizedBox(height: AppDimensions.paddingLarge),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGradientStart,
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
                      '設定を保存',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppDimensions.paddingLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitItem(String benefit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(
        benefit,
        style: AppTextStyles.bodyTextStyle.copyWith(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Future<void> _showPaywall() async {
    try {
      setState(() {
        _isLoading = true;
      });

      print('[SettingsScreen] 💳 有料版ステータスを確認中...');

      final isPremium = await _premiumService.checkPremiumStatus(userId: 'test_user');

      print('[SettingsScreen] ✅ 有料版ステータス確認完了: $isPremium');

      if (mounted) {
        setState(() {
          _isPremiumUser = isPremium;
        });

        if (context.mounted) {
          final sleepProvider = context.read<SleepProvider>();
          sleepProvider.setPremiumStatus(isPremium);
        }

        if (isPremium) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✨ プレミアム版をご利用中です！'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('無料版をご利用中です。プレミアム版でさらに多くの機能をご利用いただけます。'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('[SettingsScreen] ❌ 有料版確認エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('確認エラー: $e'),
            backgroundColor: AppColors.warningRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildAlarmModeButton(AlarmMode mode) {
    final isSelected = _alarmMode == mode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _alarmMode = mode;
          });
        },
        borderRadius:
            BorderRadius.circular(AppDimensions.borderRadiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 10.0,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryGradientStart.withOpacity(0.1)
                : AppColors.cardBgGray,
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryGradientStart
                  : AppColors.borderDefault,
              width: isSelected ? 2.0 : 1.0,
            ),
            borderRadius: BorderRadius.circular(
              AppDimensions.borderRadiusSmall,
            ),
          ),
          child: Text(
            mode.displayName,
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? AppColors.primaryGradientStart
                  : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Future<void> _selectWakeUpTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _wakeUpTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primaryGradientStart,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _wakeUpTime = picked;
      });
    }
  }

  Future<void> _testAlarmSound() async {
    print('🔊 テストアラーム開始...');
    await AlarmService.showTestNotification(
      selectedAlarmSound: _selectedAlarmSound,
      volume: _soundVolume,
    );

    if (mounted) {
      final volumePercent = (_soundVolume * 100).toStringAsFixed(0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('テストアラーム再生中...（音量: $volumePercent%、2秒で停止）'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _saveSettings() async {
    try {
      final shiftRepository = ShiftRepository();

      final wakeUpTimeStr = '${_wakeUpTime.hour.toString().padLeft(2, '0')}:${_wakeUpTime.minute.toString().padLeft(2, '0')}';

      final appSettings = AppSettings(
        id: 1,
        userId: 'test_user',
        alarmTimeBeforeShift: _alarmTimeBeforeShift,
        wakeUpTime: wakeUpTimeStr,
        selectedAlarmSound: _selectedAlarmSound,
        advicePromoVisible: _advicePromoVisible,
        isPremiumUser: _isPremiumUser,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await shiftRepository.createOrUpdateAppSettings(appSettings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('設定を保存しました'),
            backgroundColor: AppColors.primaryGradientStart,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      print('✅ 設定を保存: 起床時刻=$wakeUpTimeStr, アラーム時間=$_alarmTimeBeforeShift分前, promoVisible=$_advicePromoVisible, isPremium=$_isPremiumUser');
    } catch (e) {
      print('❌ 設定保存エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラー: $e'),
            backgroundColor: AppColors.warningRed,
          ),
        );
      }
    }
  }
    Future<void> _updateWakeUpTimeInProvider() async {
      try {
        print('🔴 [DEBUG] _updateWakeUpTimeInProvider() が呼び出されました！');
      
        final startDate = DateTime.now();
        final endDate = startDate.add(Duration(days: 30));
        final shiftsData = await _shiftRepository.getShiftsForDateRange(startDate, endDate);
      
        print('🔴 [DEBUG] shifts数: ${shiftsData.length}');
      
        if (shiftsData.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('シフトが登録されていません'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }

        final firstShiftData = shiftsData.first;
        final patternId = firstShiftData['pattern_id'] as String;
      
        final allPatterns = await _shiftRepository.getAllPatterns();
      
        var matchingPattern;
        for (final p in allPatterns) {
          if (p.id == patternId) {
            matchingPattern = p;
            break;
          }
        }

        if (matchingPattern == null || matchingPattern.startTime == null) {
          print('⚠️ パターンが見つかりません: patternId=$patternId');
          return;
        }

        final shiftDateStr = firstShiftData['shift_date'] as String;
        final shiftDate = DateTime.parse(shiftDateStr);
        final shiftStartTime = DateTime(
          shiftDate.year,
          shiftDate.month,
          shiftDate.day,
          matchingPattern.startTime.hour,
          matchingPattern.startTime.minute,
        );
      
        final wakeUpDateTime = shiftStartTime.subtract(Duration(minutes: _alarmTimeBeforeShift));
      
        if (mounted) {
          final sleepProvider = context.read<SleepProvider>();
          sleepProvider.setAutoWakeUpTime(wakeUpDateTime);
        
          final wakeUpHour = wakeUpDateTime.hour.toString().padLeft(2, '0');
          final wakeUpMin = wakeUpDateTime.minute.toString().padLeft(2, '0');
          final shiftHour = shiftStartTime.hour.toString().padLeft(2, '0');
          final shiftMin = shiftStartTime.minute.toString().padLeft(2, '0');
        
          print('✅ 起床時刻を更新: $wakeUpHour:$wakeUpMin (シフト開始 $shiftHour:$shiftMin - ${_alarmTimeBeforeShift}分)');
        }
      } catch (e) {
        print('❌ 起床時刻更新エラー: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('起床時刻計算エラー: $e'),
              backgroundColor: AppColors.warningRed,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
 
}