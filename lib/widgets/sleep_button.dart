import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/colors.dart';
import '../constants/text_styles.dart';
import '../constants/dimensions.dart';
import 'package:uuid/uuid.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/constants/shift_enums.dart';

class SleepButton extends StatefulWidget {
  final String userId;
  final VoidCallback? onPressed;

  const SleepButton({
    Key? key,
    this.userId = 'test_user',
    this.onPressed,
  }) : super(key: key);

  @override
  State<SleepButton> createState() => _SleepButtonState();
}

class _SleepButtonState extends State<SleepButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  final SleepRepository _sleepRepository = SleepRepository();
  final ShiftRepository _shiftRepository = ShiftRepository();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(
        milliseconds: AppDimensions.animationDurationFast,
      ),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
    setState(() => _isPressed = true);
  }

  void _onTapUp(TapUpDetails details) async {
    _controller.reverse();
    setState(() => _isPressed = false);

    // ========== Week 7 Phase 3 修正: SleepProvider から睡眠状態を取得 ==========
    final sleepProvider = context.read<SleepProvider>();
    final isSleeping = sleepProvider.isSleepingNow;
    
    if (isSleeping) {
      await _handleWakeUp(sleepProvider);
    } else {
      await _handleStartSleep(sleepProvider);
    }
    // ========================================================================
  }

  void _onTapCancel() {
    _controller.reverse();
    setState(() => _isPressed = false);
  }

  Future<void> _handleStartSleep(SleepProvider sleepProvider) async {
    try {
      final now = DateTime.now();
      final tomorrow7am = DateTime(now.year, now.month, now.day + 1, 7, 0);
      final canEditUntil = tomorrow7am.add(const Duration(days: 2));

      final sleepRecord = SleepRecord(
        id: const Uuid().v4(),
        userId: widget.userId,
        sleepDate: DateTime(now.year, now.month, now.day),
        sleepStartTime: now,
        sleepStartAuto: true,
        sleepEndTime: tomorrow7am,
        sleepEndAuto: false,
        wakeUpType: '',
        durationMinutes: 0,
        modifiedCount: 0,
        lastModifiedAt: now,
        canEditUntil: canEditUntil,
        createdAt: now,
        updatedAt: now,
      );

      // ========== Week 7 Phase 3 修正: SleepProvider にレコード挿入を依頼 ==========
      // これにより、SleepProvider が自動的に睡眠中フラグをセットする
      await sleepProvider.insertSleepRecord(sleepRecord);
      print('[SleepButton] ✅ Sleep record saved via SleepProvider: ${sleepRecord.id}');
      // ========================================================================

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('💤 睡眠中...「起きる」ボタンで終了します'),
            duration: Duration(seconds: 3),
          ),
        );
      }

      widget.onPressed?.call();
    } catch (e) {
      print('[SleepButton] ❌ Error starting sleep: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleWakeUp(SleepProvider sleepProvider) async {
    try {
      // ========== Week 7 Phase 3 修正: SleepProvider から現在の睡眠レコード ID を取得 ==========
      final currentSleepRecordId = sleepProvider.currentSleepRecordIdNow;
      if (currentSleepRecordId == null) {
        throw Exception('Sleep record ID not found in SleepProvider');
      }
      // ========================================================================

      final now = DateTime.now();

      final sleepRecord =
          await _sleepRepository.getSleepRecordById(currentSleepRecordId);

      if (sleepRecord != null) {
        final updatedRecord = sleepRecord.copyWith(
          sleepEndTime: now,
          sleepEndAuto: false,
          durationMinutes: now.difference(sleepRecord.sleepStartTime).inMinutes,
          lastModifiedAt: now,
          updatedAt: now,
        );

        await _sleepRepository.updateSleepRecord(updatedRecord);
        print('[SleepButton] ✅ Sleep record updated: ${updatedRecord.id}');

        // ========== Week 7 Phase 3 追加: アラームをスケジュール ==========
        await _scheduleAlarmForNextShift(now);
        // ================================================================

        // ========== Week 7 Phase 3 修正: SleepProvider の睡眠中フラグをクリア ==========
        sleepProvider.endSleepingNow();
        // ========================================================================

        if (mounted) {
          await sleepProvider.loadAllSleepData();
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 起床しました。睡眠が記録されました。'),
            duration: Duration(seconds: 3),
          ),
        );
      }

      widget.onPressed?.call();
    } catch (e) {
      print('[SleepButton] ❌ Error waking up: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ========== Week 7 Phase 3 追加: 次のシフト出勤に合わせてアラームをスケジュール ==========
  /// 
  /// 流れ:
  /// 1. 「起きる」を押した翌日以降のシフトを検索
  /// 2. 最初の出勤シフトを見つける
  /// 3. 出勤時刻から alarmTimeBeforeShift 分前にアラーム実行
  /// 4. AlarmService.scheduleAlarmForShift() で実行
  Future<void> _scheduleAlarmForNextShift(DateTime wakeUpTime) async {
    try {
      print('[SleepButton] 🔔 次のシフト出勤に合わせてアラームをスケジュール中...');

      // ========== ステップ1: 設定を取得 ==========
      final settings = await _shiftRepository.getAppSettings('test_user');
      if (settings == null) {
        print('[SleepButton] ⚠️ 設定が見つかりません');
        return;
      }

      final alarmTimeBeforeShift = settings.alarmTimeBeforeShift;
      final selectedAlarmSound = settings.selectedAlarmSound;
      print('[SleepButton] ✅ 設定取得: 出勤前${alarmTimeBeforeShift}分、音=${selectedAlarmSound}');
      // ========================================

      // ========== ステップ2: 明日以降30日間のシフトを取得 ==========
      final tomorrow = DateTime(wakeUpTime.year, wakeUpTime.month, wakeUpTime.day + 1);
      final thirtydaysLater = tomorrow.add(const Duration(days: 30));

      final shiftsMapList = await _shiftRepository.getShiftsForDateRange(tomorrow, thirtydaysLater);
      if (shiftsMapList.isEmpty) {
        print('[SleepButton] ⚠️ 予定されたシフトが見つかりません');
        return;
      }

      print('[SleepButton] 📅 ${shiftsMapList.length}件のシフトが見つかりました');
      // ==================================================

      // ========== ステップ3: 最初の「work」シフトを見つける ==========
      Map<String, dynamic>? nextWorkShift;
      DateTime? nextShiftDate;

      for (final shiftMap in shiftsMapList) {
        final patternId = shiftMap['pattern_id'] as String;
        
        // デフォルト休日は skip
        if (patternId == 'default_dayoff') {
          print('[SleepButton] ℹ️ スキップ: 休日');
          continue;
        }

        nextWorkShift = shiftMap;
        nextShiftDate = DateTime.parse(shiftMap['shift_date'] as String);
        print('[SleepButton] ✅ 次のシフト: $nextShiftDate / pattern_id=$patternId');
        break;
      }

      if (nextWorkShift == null || nextShiftDate == null) {
        print('[SleepButton] ⚠️ 出勤予定が見つかりません');
        return;
      }
      // ======================================================

      // ========== ステップ4: patternId から出勤時刻を取得 ==========
      final patterns = await _shiftRepository.getAllPatterns();
      final pattern = patterns.firstWhere(
        (p) => p.id == nextWorkShift!['pattern_id'],
        orElse: () => throw Exception('Pattern not found'),
      );

      final startTime = pattern.startTime;
      if (startTime == null) {
        print('[SleepButton] ⚠️ 出勤時刻が設定されていません');
        return;
      }

      print('[SleepButton] ⏰ 出勤時刻: ${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')}');
      // =========================================================

      // ========== ステップ5: アラーム時刻を計算 ==========
      final alarmDateTime = DateTime(
        nextShiftDate.year,
        nextShiftDate.month,
        nextShiftDate.day,
        startTime.hour,
        startTime.minute,
      ).subtract(Duration(minutes: alarmTimeBeforeShift));

      print('[SleepButton] 🔔 アラーム時刻: ${alarmDateTime.toString()}');
      // ================================================

      // ========== ステップ6: AlarmService でアラームをスケジュール ==========
      // AlarmMode から判定（none=無効、once=1回、twice=2回）
      final alarmMode = AlarmMode.once;  // デフォルトは once
      final preAlarmEnabled = alarmMode != AlarmMode.none;

      await AlarmService.scheduleAlarmForShift(
        shiftDate: nextShiftDate,
        alarmTime: startTime,
        preAlarmEnabled: preAlarmEnabled,
        preAlarmMinutes: alarmTimeBeforeShift,
        selectedAlarmSound: selectedAlarmSound,
      );

      print('[SleepButton] ✅ アラーム設定完了: $nextShiftDate の ${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')} 出勤');
      // ===================================================================

    } catch (e) {
      print('[SleepButton] ❌ アラームスケジュールエラー: $e');
      // エラーが発生してもユーザーに通知しない（睡眠記録は成功している）
    }
  }
  // =====================================================================================

  @override
  Widget build(BuildContext context) {
    // ========== Week 7 Phase 3 修正: SleepProvider から睡眠状態を監視 ==========
    return Consumer<SleepProvider>(
      builder: (context, sleepProvider, _) {
        final isSleeping = sleepProvider.isSleepingNow;
        
        return GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isSleeping
                      ? [
                          AppColors.primaryGradientStart.withOpacity(0.6),
                          AppColors.primaryGradientEnd.withOpacity(0.6),
                        ]
                      : [
                          AppColors.primaryGradientStart,
                          AppColors.primaryGradientEnd,
                        ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isSleeping ? 0.1 : 0.15),
                    blurRadius: 12,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isSleeping ? '睡眠中' : '今から寝る',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.buttonTextStyle.copyWith(
                      fontSize: isSleeping ? 14 : 16,
                    ),
                  ),
                  if (isSleeping)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        '起きる',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.buttonTextStyle.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    // ========================================================================
  }
}