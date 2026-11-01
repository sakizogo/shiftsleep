import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/sleep_record_validation.dart';
import 'package:uuid/uuid.dart';

class EditSleepRecordScreen extends StatefulWidget {
  /// 修正する記録。null なら追加モード（N106）
  final SleepRecord? record;

  /// 追加モードの入眠日の初期値（null なら今日）
  final DateTime? initialBedDate;

  const EditSleepRecordScreen({
    Key? key,
    this.record,
    this.initialBedDate,
  }) : super(key: key);

  @override
  State<EditSleepRecordScreen> createState() => _EditSleepRecordScreenState();
}

class _EditSleepRecordScreenState extends State<EditSleepRecordScreen> {
  late DateTime _editedBedtime;
  late DateTime _editedWakeTime;

  // ========== N106: 追加モード ==========
  late DateTime _bedDate;  // 入眠日（0:00）
  bool _isSaving = false;

  bool get _isAddMode => widget.record == null;

  /// 保存ボタンを押せるか（N107：修正モードも常に押せる。変わっていなければ保存時に何もせず閉じる）
  bool get _canSave => !_isSaving;

  /// 入眠・起床の日時（起床の時刻が入眠以下なら翌日。N107 で修正モードも同じ）
  ({DateTime start, DateTime end}) get _resolvedTimes => SleepRecordValidation.resolveTimes(
        bedDate: _bedDate,
        bedHour: _editedBedtime.hour,
        bedMinute: _editedBedtime.minute,
        wakeHour: _editedWakeTime.hour,
        wakeMinute: _editedWakeTime.minute,
      );
  // ======================================

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    if (record != null) {
      // N107：入眠日は入眠時刻の日付。30 日の範囲外でもそのまま表示し、保存時に止める
      _editedBedtime = record.bedtime;
      _editedWakeTime = record.wakeTime;
      _bedDate = DateTime(record.bedtime.year, record.bedtime.month, record.bedtime.day);
    } else {
      // N106：入眠日は 30 日前〜今日に収める。時刻の初期値は 23:00 → 7:00
      final now = DateTime.now();
      final initial = widget.initialBedDate ?? now;
      var bedDate = DateTime(initial.year, initial.month, initial.day);
      final earliest = SleepRecordValidation.earliestBedDate(now);
      final latest = SleepRecordValidation.latestBedDate(now);
      if (bedDate.isBefore(earliest)) bedDate = earliest;
      if (bedDate.isAfter(latest)) bedDate = latest;
      _bedDate = bedDate;
      _editedBedtime = DateTime(bedDate.year, bedDate.month, bedDate.day, 23, 0);
      _editedWakeTime = DateTime(bedDate.year, bedDate.month, bedDate.day, 7, 0);
    }
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
          _isAddMode ? '睡眠を追加' : '睡眠記録を修正',
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
              // N106: 入眠日の選択（N107 で修正モードにも出す）
              // ========================
              _buildBedDateSection(),
              const SizedBox(height: AppDimensions.paddingXLarge),

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
                        gradient: _canSave
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
                        onPressed: _canSave ? _saveChanges : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: !_canSave
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
                            color: _canSave ? Colors.white : AppColors.textMuted,
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
                      // N106：toInt() だと 13 時などが 1 つ下になるので四捨五入する
                      SleepRecordValidation.sliderValueToTimePart(newHour, max: 23),
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
                      SleepRecordValidation.sliderValueToTimePart(newMinute, max: 59),
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
    // N106：起床日を自動で決めた日時から計算する（N107 で修正モードも同じ）
    final duration = _resolvedTimes.end.difference(_resolvedTimes.start);

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
              '入眠: ${_formatDateTime(_resolvedTimes.start)} → 起床: ${_formatDateTime(_resolvedTimes.end)}',
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

  // ========== N106: 追加モード ==========

  String _formatDateTime(DateTime t) {
    return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// 入眠日の選択
  Widget _buildBedDateSection() {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 20,
              color: AppColors.primaryGradientStart,
            ),
            const SizedBox(width: AppDimensions.paddingSmall),
            Text(
              '入眠日',
              style: AppTextStyles.sectionTitleStyle,
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.paddingMedium),
        InkWell(
          onTap: _pickBedDate,
          borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
          child: Container(
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_bedDate.year}/${_bedDate.month}/${_bedDate.day}（${weekdays[_bedDate.weekday - 1]}）',
                  style: AppTextStyles.sectionTitleStyle.copyWith(
                    color: AppColors.primaryGradientStart,
                  ),
                ),
                Icon(
                  Icons.edit_calendar,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 入眠日をピッカーで選ぶ（今日から 30 日前まで）
  Future<void> _pickBedDate() async {
    final now = DateTime.now();
    final firstDate = SleepRecordValidation.earliestBedDate(now);
    final lastDate = SleepRecordValidation.latestBedDate(now);
    // N107：修正する記録の入眠日が範囲外でもピッカーが落ちないよう、初期値だけ範囲に収める
    var initialDate = _bedDate;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _bedDate = DateTime(picked.year, picked.month, picked.day);
      // スライダーは時刻だけを使うので、日付も入眠日にそろえておく
      _editedBedtime = DateTime(_bedDate.year, _bedDate.month, _bedDate.day,
          _editedBedtime.hour, _editedBedtime.minute);
      _editedWakeTime = DateTime(_bedDate.year, _bedDate.month, _bedDate.day,
          _editedWakeTime.hour, _editedWakeTime.minute);
    });
  }

  void _showWarning(ScaffoldMessengerState messenger, String text) {
    // N107：前の SnackBar を消してから出す（積み重なって保存ボタンを覆わないように）
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 保存前のチェック（追加・修正で共通）。問題なければ null
  /// excludeRecordId：修正のときの自分自身の ID（重なり判定から外す。N107）
  Future<ManualSleepError?> _validateTimes(
    ({DateTime start, DateTime end}) times,
    DateTime now,
    SleepProvider provider, {
    String? excludeRecordId,
  }) async {
    // 重なりは DB から入眠日の前後の記録を読んで判定する（Provider のリストだけに頼らない）
    final nearbyRecords = await SleepRepository().getSleepRecordsByDateRange(
      'test_user',
      DateTime(_bedDate.year, _bedDate.month, _bedDate.day - 2),
      DateTime(_bedDate.year, _bedDate.month, _bedDate.day + 2, 23, 59, 59),
    );

    final isSleeping = provider.isSleepingNow;
    return SleepRecordValidation.validate(
      start: times.start,
      end: times.end,
      now: now,
      existingRecords: nearbyRecords,
      sleepingRecordId: isSleeping ? provider.currentSleepRecordIdNow : null,
      sleepingStartTime: isSleeping ? provider.sleepStartTime : null,
      excludeRecordId: excludeRecordId,
    );
  }

  /// 新しい記録を保存
  Future<void> _saveNewRecord() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final provider = context.read<SleepProvider>();

    final now = DateTime.now();
    final times = _resolvedTimes;

    if (!SleepRecordValidation.isBedDateInRange(_bedDate, now)) {
      _showWarning(messenger, '⚠️ 入眠日は今日から ${SleepRecordValidation.maxDaysBack} 日前までを選んでください');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final error = await _validateTimes(times, now, provider);
      if (error != null) {
        _showWarning(messenger, error.message);
        return;
      }

      // 「今から寝る」で作る記録と同じ決め方（canEditUntil = 翌日 7:00 + 2 日）
      final tomorrow7am = DateTime(now.year, now.month, now.day + 1, 7, 0);
      final record = SleepRecord(
        id: const Uuid().v4(),
        userId: 'test_user',
        sleepDate: _bedDate,
        sleepStartTime: times.start,
        sleepStartAuto: false,
        sleepEndTime: times.end,
        sleepEndAuto: false,
        wakeUpType: 'manual',
        durationMinutes: times.end.difference(times.start).inMinutes,
        modifiedCount: 0,
        lastModifiedAt: now,
        canEditUntil: tomorrow7am.add(const Duration(days: 2)),
        createdAt: now,
        updatedAt: now,
        sleepRole: SleepRole.primary,
      );

      await provider.addManualSleepRecord(record);

      navigator.pop();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('✅ 睡眠を追加しました'),
          backgroundColor: AppColors.primaryGradientStart,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ 睡眠の追加に失敗しました: $e'),
          backgroundColor: AppColors.warningRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
  // ======================================

  /// 秒・ミリ秒を切り捨てた日時（分単位で比べるため）
  DateTime _toMinute(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute);

  /// N107：修正した記録を保存（流れは _saveNewRecord と同じ）
  Future<void> _saveEditedRecord() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final provider = context.read<SleepProvider>();
    final original = widget.record!;

    final now = DateTime.now();
    final times = _resolvedTimes;

    // 入眠・起床が元の記録と分単位で同じなら、DB を書き換えずに閉じる（modifiedCount を増やさない）
    // 入眠日は times.start の日付に入っているので、start の比較で一緒に見ている
    if (_toMinute(times.start) == _toMinute(original.sleepStartTime) &&
        _toMinute(times.end) == _toMinute(original.sleepEndTime)) {
      navigator.pop();
      return;
    }

    if (!SleepRecordValidation.isBedDateInRange(_bedDate, now)) {
      _showWarning(messenger, '⚠️ 入眠日は今日から ${SleepRecordValidation.maxDaysBack} 日前までを選んでください');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final error = await _validateTimes(times, now, provider, excludeRecordId: original.id);
      if (error != null) {
        _showWarning(messenger, error.message);
        return;
      }

      final updatedRecord = original.copyWith(
        sleepDate: _bedDate,
        sleepStartTime: times.start,
        sleepStartAuto: false,
        sleepEndTime: times.end,
        sleepEndAuto: false,
        durationMinutes: times.end.difference(times.start).inMinutes,
        modifiedCount: original.modifiedCount + 1,
        lastModifiedAt: now,
        updatedAt: now,
      );

      await provider.updateSleepRecord(updatedRecord);

      navigator.pop();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('睡眠記録を更新しました'),
          backgroundColor: AppColors.primaryGradientStart,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ 更新に失敗しました: $e'),
          backgroundColor: AppColors.warningRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 変更を保存
  void _saveChanges() async {
    // N106：追加モードは別の保存処理
    if (_isAddMode) {
      await _saveNewRecord();
      return;
    }
    await _saveEditedRecord();
  }
}