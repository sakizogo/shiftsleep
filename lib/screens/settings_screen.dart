import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'shift_pattern_screen.dart';

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
  List<ShiftPatternModel> _shiftPatterns = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
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
              // ========================
              // アラーム設定セクション
              // ========================
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
                    // 起床時刻設定
                    Text(
                      '起床時刻',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    Row(
                      children: [
                        Text(
                          '${_wakeUpTime.hour.toString().padLeft(2, '0')}:${_wakeUpTime.minute.toString().padLeft(2, '0')}',
                          style: AppTextStyles.largeNumberStyle.copyWith(
                            fontSize: 32,
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () => _selectWakeUpTime(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                AppColors.primaryGradientStart,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDimensions.borderRadiusSmall,
                              ),
                            ),
                          ),
                          child: Text(
                            '変更',
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingLarge),

                    // アラームモード選択
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

                    // アラーム音選択
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
                        DropdownMenuItem(
                          value: 'default',
                          child: Text('デフォルト音'),
                        ),
                        DropdownMenuItem(
                          value: 'gentle',
                          child: Text('やさしい音'),
                        ),
                        DropdownMenuItem(
                          value: 'harsh',
                          child: Text('強めの音'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedAlarmSound = value!;
                        });
                      },
                    ),
                    const SizedBox(height: AppDimensions.paddingLarge),

                    // 音量調整
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
                ),
              ),

              const SizedBox(height: AppDimensions.paddingXLarge),

              // ========================
              // シフト体系設定セクション
              // ========================
              Text(
                '📅 シフト体系設定',
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
                    // 登録済みシフト体系
                    if (_shiftPatterns.isNotEmpty) ...[
                      Text(
                        '登録済みシフト体系',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.paddingMedium),
                      ..._shiftPatterns.map((pattern) {
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppDimensions.paddingSmall,
                          ),
                          child: _buildPatternItem(pattern),
                        );
                      }).toList(),
                      const SizedBox(height: AppDimensions.paddingMedium),
                    ],

                    // + シフト体系を登録ボタン
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _registerNewPattern,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              AppColors.primaryGradientStart,
                          padding: EdgeInsets.symmetric(
                            vertical: AppDimensions.paddingSmall,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppDimensions.borderRadiusSmall,
                            ),
                          ),
                        ),
                        child: Text(
                          '+ シフト体系を登録',
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

              const SizedBox(height: AppDimensions.paddingXLarge),

              // ========================
              // 保存ボタン
              // ========================
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
    );
  }

  /// アラームモード選択ボタン
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

  /// シフト体系アイテム
  Widget _buildPatternItem(ShiftPatternModel pattern) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingSmall,
        vertical: 10.0,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardBgGray,
        borderRadius: BorderRadius.circular(
          AppDimensions.borderRadiusSmall,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pattern.patternName,
                  style: AppTextStyles.bodyTextStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4.0),
                if (pattern.patternType.isWorkDay)
                  Text(
                    '${pattern.startTime!.hour.toString().padLeft(2, '0')}:${pattern.startTime!.minute.toString().padLeft(2, '0')} ～ ${pattern.endTime!.hour.toString().padLeft(2, '0')}:${pattern.endTime!.minute.toString().padLeft(2, '0')}',
                    style: AppTextStyles.bodyTextStyle.copyWith(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  )
                else
                  Text(
                    '休日',
                    style: AppTextStyles.bodyTextStyle.copyWith(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () => _editPattern(pattern),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                  ),
                  child: Icon(
                    Icons.edit,
                    size: 20,
                    color: AppColors.primaryGradientStart,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _deletePattern(pattern),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                  ),
                  child: Icon(
                    Icons.delete,
                    size: 20,
                    color: AppColors.warningRed,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 起床時刻選択
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

  /// 新規シフト体系登録
  void _registerNewPattern() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShiftPatternScreen(
          mode: ShiftPatternMode.register,
          onPatternsChanged: (patterns) {
            setState(() {
              _shiftPatterns = patterns;
            });
          },
          existingPatterns: _shiftPatterns,
        ),
      ),
    ).then((_) {
      setState(() {});
    });
  }

  /// シフト体系編集
  void _editPattern(ShiftPatternModel pattern) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShiftPatternScreen(
          mode: ShiftPatternMode.edit,
          editingPattern: pattern,
          onPatternsChanged: (patterns) {
            setState(() {
              _shiftPatterns = patterns;
            });
          },
          existingPatterns: _shiftPatterns,
        ),
      ),
    ).then((_) {
      setState(() {});
    });
  }

  /// シフト体系削除
  void _deletePattern(ShiftPatternModel pattern) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            '「${pattern.patternName}」を削除',
            style: AppTextStyles.sectionTitleStyle,
          ),
          content: Text(
            'このシフト体系を削除してもよろしいですか？',
            style: AppTextStyles.bodyTextStyle,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'キャンセル',
                style: AppTextStyles.bodyTextStyle.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _shiftPatterns.removeWhere((p) => p.id == pattern.id);
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('「${pattern.patternName}」を削除しました'),
                    backgroundColor: AppColors.warningRed,
                  ),
                );
              },
              child: Text(
                '削除',
                style: AppTextStyles.bodyTextStyle.copyWith(
                  color: AppColors.warningRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 設定を保存
  void _saveSettings() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('設定を保存しました'),
        backgroundColor: AppColors.primaryGradientStart,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
