import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';

class EditSleepRecordScreen extends StatefulWidget {
  final SleepRecord record;

  const EditSleepRecordScreen({
    Key? key,
    required this.record,
  }) : super(key: key);

  @override
  State<EditSleepRecordScreen> createState() => _EditSleepRecordScreenState();
}

class _EditSleepRecordScreenState extends State<EditSleepRecordScreen> {
  late DateTime _editedBedtime;
  late DateTime _editedWakeTime;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _editedBedtime = widget.record.bedtime;
    _editedWakeTime = widget.record.wakeTime;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          '睡眠記録を修正',
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
      backgroundColor: AppColors.backgroundLight,
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
              // 入眠時刻の編集
              // ========================
              _buildTimeEditSection(
                title: '入眠時刻',
                icon: Icons.bedtime,
                currentTime: _editedBedtime,
                onTimeChanged: (newTime) {
                  setState(() {
                    _editedBedtime = newTime;
                    _hasChanges = true;
                  });
                },
              ),

              const SizedBox(height: AppDimensions.paddingXLarge),

              // ========================
              // 起床時刻の編集
              // ========================
              _buildTimeEditSection(
                title: '起床時刻',
                icon: Icons.alarm_on,
                currentTime: _editedWakeTime,
                onTimeChanged: (newTime) {
                  setState(() {
                    _editedWakeTime = newTime;
                    _hasChanges = true;
                  });
                },
              ),

              const SizedBox(height: AppDimensions.paddingXLarge),

              // ========================
              // 睡眠時間表示
              // ========================
              _buildSleepDurationDisplay(),

              const SizedBox(height: AppDimensions.paddingXLarge),

              // ========================
              // ボタンエリア
              // ========================
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cardBgGray,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(
                          vertical: AppDimensions.paddingMedium,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusMedium,
                          ),
                          side: BorderSide(
                            color: AppColors.borderDefault,
                            width: AppDimensions.borderWidthThin,
                          ),
                        ),
                      ),
                      child: Text(
                        'キャンセル',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.paddingMedium),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: _hasChanges
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.primaryGradientStart,
                                  AppColors.primaryGradientEnd,
                                ],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(
                          AppDimensions.borderRadiusMedium,
                        ),
                      ),
                      child: ElevatedButton(
                        onPressed: _hasChanges ? _saveChanges : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: !_hasChanges
                              ? AppColors.borderDefault
                              : Colors.transparent,
                          elevation: 0,
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
                          '保存',
                          style: AppTextStyles.bodyTextStyle.copyWith(
                            color: _hasChanges ? Colors.white : AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppDimensions.paddingXLarge),
            ],
          ),
        ),
      ),
    );
  }

  /// 時刻編集セクション（入眠・起床）
  Widget _buildTimeEditSection({
    required String title,
    required IconData icon,
    required DateTime currentTime,
    required Function(DateTime) onTimeChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title with Icon
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: AppColors.primaryGradientStart,
            ),
            const SizedBox(width: AppDimensions.paddingSmall),
            Text(
              title,
              style: AppTextStyles.sectionTitleStyle,
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.paddingMedium),

        // Time Display Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
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
            children: [
              // 時刻表示（大きく）
              Text(
                '${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}',
                style: AppTextStyles.largeNumberStyle.copyWith(
                  fontSize: 48,
                  color: AppColors.primaryGradientStart,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingLarge),

              // 時間スライダー（0～23）
              _buildSlider(
                label: '時間',
                value: currentTime.hour.toDouble(),
                min: 0,
                max: 23,
                onChanged: (newHour) {
                  onTimeChanged(
                    DateTime(
                      currentTime.year,
                      currentTime.month,
                      currentTime.day,
                      newHour.toInt(),
                      currentTime.minute,
                    ),
                  );
                },
              ),

              const SizedBox(height: AppDimensions.paddingMedium),

              // 分スライダー（0～59）
              _buildSlider(
                label: '分',
                value: currentTime.minute.toDouble(),
                min: 0,
                max: 59,
                onChanged: (newMinute) {
                  onTimeChanged(
                    DateTime(
                      currentTime.year,
                      currentTime.month,
                      currentTime.day,
                      currentTime.hour,
                      newMinute.toInt(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// スライダーウィジェット（改善版）
  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required Function(double) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label & Value
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTextStyles.bodyTextStyle.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.paddingSmall,
                vertical: AppDimensions.paddingXSmall,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryGradientStart.withOpacity(0.1),
                borderRadius: BorderRadius.circular(
                  AppDimensions.borderRadiusSmall,
                ),
              ),
              child: Text(
                value.toInt().toString().padLeft(2, '0'),
                style: AppTextStyles.sectionTitleStyle.copyWith(
                  fontSize: 16,
                  color: AppColors.primaryGradientStart,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8.0),

        // Slider
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6.0,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: 12.0,
              elevation: 2.0,
            ),
            overlayShape: RoundSliderOverlayShape(
              overlayRadius: 16.0,
            ),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min).toInt(),
            label: value.toInt().toString().padLeft(2, '0'),
            onChanged: onChanged,
            activeColor: AppColors.primaryGradientStart,
            inactiveColor: AppColors.borderDefault,
          ),
        ),
      ],
    );
  }

  /// 睡眠時間表示（改善版）
  Widget _buildSleepDurationDisplay() {
    final duration = _editedWakeTime.difference(_editedBedtime);

    // 翌日にまたがる場合
    final adjustedDuration =
        duration.isNegative ? duration + Duration(days: 1) : duration;

    final hours = adjustedDuration.inHours;
    final minutes = adjustedDuration.inMinutes % 60;

    // 睡眠時間に基づく評価
    final totalHours = hours + (minutes / 60);
    final isGood = totalHours >= 6;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      decoration: BoxDecoration(
        gradient: isGood
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryGradientStart.withOpacity(0.1),
                  AppColors.primaryGradientEnd.withOpacity(0.1),
                ],
              )
            : null,
        color: !isGood ? AppColors.cardBgAlert : null,
        border: Border.all(
          color: isGood
              ? AppColors.primaryGradientStart.withOpacity(0.3)
              : AppColors.warningRed.withOpacity(0.3),
          width: AppDimensions.borderWidthThin,
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
              Text(
                '睡眠時間',
                style: AppTextStyles.bodyTextStyle.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.paddingSmall,
                  vertical: AppDimensions.paddingXSmall,
                ),
                decoration: BoxDecoration(
                  color: isGood
                      ? AppColors.primaryGradientStart.withOpacity(0.15)
                      : AppColors.warningRed.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(
                    AppDimensions.borderRadiusSmall,
                  ),
                ),
                child: Text(
                  isGood ? '良好' : '不足',
                  style: AppTextStyles.captionStyle.copyWith(
                    color: isGood
                        ? AppColors.primaryGradientStart
                        : AppColors.warningRed,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.paddingMedium),

          // Sleep Duration Number
          Text(
            '${hours}h ${minutes}m',
            style: AppTextStyles.largeNumberStyle.copyWith(
              fontSize: 40,
              color: isGood
                  ? AppColors.primaryGradientStart
                  : AppColors.warningRed,
            ),
          ),
          const SizedBox(height: AppDimensions.paddingSmall),

          // Time Range Details
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingSmall,
              vertical: AppDimensions.paddingXSmall,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(
                AppDimensions.borderRadiusSmall,
              ),
            ),
            child: Text(
              '入眠: ${_editedBedtime.hour.toString().padLeft(2, '0')}:${_editedBedtime.minute.toString().padLeft(2, '0')} '
              '→ '
              '起床: ${_editedWakeTime.hour.toString().padLeft(2, '0')}:${_editedWakeTime.minute.toString().padLeft(2, '0')}',
              style: AppTextStyles.bodyTextStyle.copyWith(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 変更を保存
  void _saveChanges() async {
    // 編集した内容で新しい SleepRecord を作成
    final updatedRecord = widget.record.copyWith(
      sleepStartTime: _editedBedtime,
      sleepEndTime: _editedWakeTime,
      updatedAt: DateTime.now(),
    );

    try {
      // Provider 経由で更新を保存
      await context.read<SleepProvider>().updateSleepRecord(updatedRecord);

      // 保存成功時、前画面に戻る
      if (mounted) {
        Navigator.pop(context);

        // 成功メッセージ
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('睡眠記録を更新しました'),
            backgroundColor: AppColors.primaryGradientStart,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                AppDimensions.borderRadiusSmall,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // エラー表示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('更新に失敗しました: $e'),
            backgroundColor: AppColors.warningRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                AppDimensions.borderRadiusSmall,
              ),
            ),
          ),
        );
      }
    }
  }
}