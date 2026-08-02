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
          padding: const EdgeInsets.all(AppDimensions.sectionPaddingHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppDimensions.paddingMedium),

              // ========================
              // 入眠時刻の編集
              // ========================
              _buildTimeEditSection(
                title: '入眠時刻',
                currentTime: _editedBedtime,
                onTimeChanged: (newTime) {
                  setState(() {
                    _editedBedtime = newTime;
                    _hasChanges = true;
                  });
                },
              ),

              const SizedBox(height: AppDimensions.paddingLarge),

              // ========================
              // 起床時刻の編集
              // ========================
              _buildTimeEditSection(
                title: '起床時刻',
                currentTime: _editedWakeTime,
                onTimeChanged: (newTime) {
                  setState(() {
                    _editedWakeTime = newTime;
                    _hasChanges = true;
                  });
                },
              ),

              const SizedBox(height: AppDimensions.paddingLarge),

              // ========================
              // 睡眠時間表示
              // ========================
              _buildSleepDurationDisplay(),

              const SizedBox(height: AppDimensions.paddingLarge),

              // ========================
              // ボタンエリア
              // ========================
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.borderDefault,
                        padding: EdgeInsets.symmetric(
                          vertical: AppDimensions.paddingMedium,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusSmall,
                          ),
                        ),
                      ),
                      child: Text(
                        'キャンセル',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.paddingMedium),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _hasChanges ? _saveChanges : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hasChanges
                            ? AppColors.primaryGradientStart
                            : AppColors.borderDefault,
                        padding: EdgeInsets.symmetric(
                          vertical: AppDimensions.paddingMedium,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusSmall,
                          ),
                        ),
                      ),
                      child: Text(
                        '保存',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppDimensions.paddingLarge),
            ],
          ),
        ),
      ),
    );
  }

  /// 時刻編集セクション（入眠・起床）
  Widget _buildTimeEditSection({
    required String title,
    required DateTime currentTime,
    required Function(DateTime) onTimeChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.sectionTitleStyle,
        ),
        const SizedBox(height: AppDimensions.paddingMedium),
        Container(
          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderDefault),
            borderRadius: BorderRadius.circular(
              AppDimensions.borderRadiusSmall,
            ),
          ),
          child: Column(
            children: [
              // 時刻表示
              Text(
                '${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}',
                style: AppTextStyles.largeNumberStyle.copyWith(
                  fontSize: 36,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingMedium),

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

  /// スライダーウィジェット
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTextStyles.bodyTextStyle.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              value.toInt().toString().padLeft(2, '0'),
              style: AppTextStyles.sectionTitleStyle.copyWith(
                fontSize: 16,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          label: value.toInt().toString().padLeft(2, '0'),
          onChanged: onChanged,
          activeColor: AppColors.primaryGradientStart,
          inactiveColor: AppColors.borderDefault,
        ),
      ],
    );
  }

  /// 睡眠時間表示
  Widget _buildSleepDurationDisplay() {
    final duration = _editedWakeTime.difference(_editedBedtime);

    // 翌日にまたがる場合
    final adjustedDuration =
        duration.isNegative ? duration + Duration(days: 1) : duration;

    final hours = adjustedDuration.inHours;
    final minutes = adjustedDuration.inMinutes % 60;

    return Container(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      decoration: BoxDecoration(
        color: AppColors.cardBgWarning,
        border: Border.all(color: AppColors.borderWarning),
        borderRadius: BorderRadius.circular(
          AppDimensions.borderRadiusSmall,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '睡眠時間',
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppDimensions.paddingSmall),
          Text(
            '${hours}h ${minutes}m',
            style: AppTextStyles.largeNumberStyle.copyWith(
              fontSize: 32,
            ),
          ),
          const SizedBox(height: AppDimensions.paddingSmall),
          Text(
            '入眠: ${_editedBedtime.hour.toString().padLeft(2, '0')}:${_editedBedtime.minute.toString().padLeft(2, '0')} '
            '→ '
            '起床: ${_editedWakeTime.hour.toString().padLeft(2, '0')}:${_editedWakeTime.minute.toString().padLeft(2, '0')}',
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontSize: 12,
              color: AppColors.textMuted,
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
            content: Text('睡眠記録を更新しました'),
            backgroundColor: AppColors.primaryGradientStart,
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
          ),
        );
      }
    }
  }
}