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

    print('[SleepButton] 🎯 ボタンがタップされました (TapUp)');

    // ========== Week 7 Phase 3 修正: SleepProvider から睡眠状態を取得 ==========
    final sleepProvider = context.read<SleepProvider>();
    final isSleeping = sleepProvider.isSleepingNow;
    
    print('[SleepButton] 📊 isSleepingNow: $isSleeping');
    
    if (isSleeping) {
      print('[SleepButton] 🌅 起床処理を開始します');
      await _handleWakeUp(sleepProvider);
    } else {
      print('[SleepButton] 😴 就寝処理を開始します');
      await _handleStartSleep(sleepProvider);
    }
    // ========================================================================
  }

  void _onTapCancel() {
    _controller.reverse();
    setState(() => _isPressed = false);
  }

  // ========== Week 26+ Step 7：「寝る」ボタン処理 ==========
  Future<void> _handleStartSleep(SleepProvider sleepProvider) async {
    try {
      // ✨ AppSettings から isAlarmEnabled をチェック
      final settings = await _shiftRepository.getAppSettings('test_user');
      final isAlarmEnabled = settings?.isAlarmEnabled ?? true;  // デフォルト true
      print('[SleepButton] 🔔 isAlarmEnabled: $isAlarmEnabled');
      
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

      await sleepProvider.insertSleepRecord(sleepRecord);
      await sleepProvider.setCurrentSleepRecordIdNow(sleepRecord.id);
      
      // ✨ Step 7：isAlarmEnabled が true の場合のみ今日のシフト始業30分前アラームをセット
      if (isAlarmEnabled) {
        print('[SleepButton] ✅ アラーム有効：今日のシフト始業30分前アラームをセット');
        await _scheduleAlarmForTodayShift(now);
      } else {
        print('[SleepButton] ⚠️ アラーム無効：アラームをセットしません');
      }
      
      print('[SleepButton] ✅ Sleep record saved');

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
  // ==================================================

  // ========== Week 26+ Step 7：「起きる」ボタン処理 ==========
  Future<void> _handleWakeUp(SleepProvider sleepProvider) async {
    try {
      print('[SleepButton] 🛏️ _handleWakeUp メソッドが呼ばれました');
      
      // ========== Week 7 Phase 3 修正: SleepProvider から現在の睡眠レコード ID を取得 ==========
      final currentSleepRecordId = sleepProvider.currentSleepRecordIdNow;
      print('[SleepButton] 🔍 currentSleepRecordId: $currentSleepRecordId');
      if (currentSleepRecordId == null) {
        throw Exception('Sleep record ID not found in SleepProvider');
      }
      // ========================================================================

      final now = DateTime.now();

      final sleepRecord =
          await _sleepRepository.getSleepRecordById(currentSleepRecordId);

      if (sleepRecord != null) {
        print('[SleepButton] 💾 睡眠レコードを更新中...');
        
        final updatedRecord = sleepRecord.copyWith(
          sleepEndTime: now,
          sleepEndAuto: false,
          durationMinutes: now.difference(sleepRecord.sleepStartTime).inMinutes,
          lastModifiedAt: now,
          updatedAt: now,
        );

        await _sleepRepository.updateSleepRecord(updatedRecord);
        print('[SleepButton] ✅ Sleep record updated: ${updatedRecord.id}');

        // ========== Step 7：今日のシフト始業30分前アラームをキャンセル ==========
        print('[SleepButton] 🔔 今日のシフト始業30分前アラームをキャンセル中...');
        final today = DateTime(now.year, now.month, now.day);
        await AlarmService.cancelAlarm(today);
        await AlarmService.stopAlarmSound();
        print('[SleepButton] 🔊 アラーム音を停止しました');
        print('[SleepButton] ✅ アラームをキャンセルしました');
        // =====================================================================

        // ========== Week 7 Phase 3 修正: SleepProvider の睡眠中フラグをクリア ==========
        sleepProvider.endSleepingNow();
        print('[SleepButton] ✅ 睡眠中フラグをクリア');
        // ========================================================================

        if (mounted) {
          await sleepProvider.loadAllSleepData();
        }
      } else {
        print('[SleepButton] ⚠️ 睡眠レコードが見つかりません');
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
  // ==================================================

  // ========== Step 7：今日のシフト始業30分前アラームをセット ==========
  /// 
  /// 流れ:
  /// 1. 今日のシフトを getShiftsForDateRange(today, today) で取得
  /// 2. pattern_id から ShiftPatternModel を取得
  /// 3. 出勤時刻 - alarmTimeBeforeShift = アラーム時刻
  /// 4. AlarmService.scheduleAlarmForShift() でアラーム登録
  Future<void> _scheduleAlarmForTodayShift(DateTime wakeUpTime) async {
    try {
      print('[SleepButton] 🔔 今日のシフト始業30分前アラームをセット中...');

      // ========== ステップ1️⃣：設定を取得 ==========
      final settings = await _shiftRepository.getAppSettings('test_user');
      if (settings == null) {
        print('[SleepButton] ⚠️ 設定が見つかりません');
        return;
      }

      final alarmTimeBeforeShift = settings.alarmTimeBeforeShift;
      final selectedAlarmSound = settings.selectedAlarmSound;
      print('[SleepButton] ✅ 設定取得: 出勤前${alarmTimeBeforeShift}分、音=${selectedAlarmSound}');
      // ========================================

      // ========== ステップ2️⃣：**今日**のシフトを取得 ==========
      final today = DateTime(wakeUpTime.year, wakeUpTime.month, wakeUpTime.day);
      print('[SleepButton] 📅 今日のシフト検索: $today');

      final shiftsMapList = await _shiftRepository.getShiftsForDateRange(today, today);
      print('[SleepButton] 📊 getShiftsForDateRange の結果: ${shiftsMapList.length}件');
      
      if (shiftsMapList.isEmpty) {
        print('[SleepButton] ⚠️ 今日のシフトが見つかりません');
        return;
      }

      print('[SleepButton] 📅 今日のシフトが見つかりました');
      // ================================================

      // ========== ステップ3️⃣：pattern_id から出勤時刻を取得 ==========
      final shiftMap = shiftsMapList.first;
      final patternId = shiftMap['pattern_id'] as String;
      
      print('[SleepButton] 🔍 pattern_id: $patternId');
      
      // デフォルト休日はスキップ
      if (patternId == 'default_dayoff') {
        print('[SleepButton] ℹ️ 今日は休日です（スキップ）');
        return;
      }

      // pattern_id から ShiftPatternModel を取得
      final pattern = await _shiftRepository.getPatternById(patternId);
      if (pattern == null || pattern.startTime == null) {
        print('[SleepButton] ⚠️ 出勤時刻が設定されていません');
        return;
      }

      final startTime = pattern.startTime!;
      print('[SleepButton] ⏰ 出勤時刻: ${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')}');
      // =========================================================

      // ========== ステップ4️⃣：アラーム時刻を計算 ==========
      // 例：15:15 - 30分 = 14:45
      final alarmDateTime = DateTime(
        today.year,
        today.month,
        today.day,
        startTime.hour,
        startTime.minute,
      ).subtract(Duration(minutes: alarmTimeBeforeShift));

      print('[SleepButton] 🔔 アラーム時刻: ${alarmDateTime.hour}:${alarmDateTime.minute.toString().padLeft(2, '0')}');
      // ================================================

      // ========== ステップ5️⃣：AlarmService でアラームをスケジュール ==========
      print('[SleepButton] 🚀 AlarmService.scheduleAlarmForShift() を呼び出し中...');

      await AlarmService.scheduleAlarmForShift(
        shiftDate: today,
        alarmTime: startTime,
        preAlarmEnabled: true,
        preAlarmMinutes: alarmTimeBeforeShift,
        selectedAlarmSound: selectedAlarmSound,
      );

      print('[SleepButton] ✅ アラーム設定完了: 今日 ${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')} 出勤（${alarmTimeBeforeShift}分前にアラーム）');
      // ===================================================================

    } catch (e) {
      print('[SleepButton] ❌ アラームスケジュールエラー: $e');
      print('[SleepButton] 📍 スタックトレース: ${e.toString()}');
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