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

      await sleepProvider.insertSleepRecord(sleepRecord);
      await sleepProvider.setCurrentSleepRecordIdNow(sleepRecord.id);
      print('[SleepButton] ✅ Sleep record saved via SleepProvider: ${sleepRecord.id}');

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
      print('[SleepButton] 🛏️ _handleWakeUp メソッドが呼ばれました');
      
      final currentSleepRecordId = sleepProvider.currentSleepRecordIdNow;
      print('[SleepButton] 🔍 currentSleepRecordId: $currentSleepRecordId');
      if (currentSleepRecordId == null) {
        throw Exception('Sleep record ID not found in SleepProvider');
      }

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

        // ========== Week 26+ 修正: 手動設定を最優先 ==========
        // ユーザー要件：手動設定 > シフト自動計算
        print('[SleepButton] 🔔 アラーム登録の準備中...');
        
        // AppSettings から起床時刻を読み込む
        final settings = await _shiftRepository.getAppSettings('test_user');
        if (settings?.wakeUpTime != null) {
          // 手動設定がある → そのままアラーム登録
          final wakeUpTimeStr = settings!.wakeUpTime;  // "20:55" 形式
          final parts = wakeUpTimeStr.split(':');
          final hour = int.parse(parts[0]);
          final minute = int.parse(parts[1]);
          final wakeUpDateTime = DateTime(now.year, now.month, now.day, hour, minute);
          
          print('[SleepButton] ✅ 手動設定の起床時刻を使用: ${wakeUpDateTime.hour}:${wakeUpDateTime.minute.toString().padLeft(2, '0')}');
          await _scheduleAlarmWithManualWakeUpTime(wakeUpDateTime);
        } else {
          // 手動設定がない → シフト始業時刻から自動計算
          print('[SleepButton] ℹ️ 手動設定がない → シフト始業時刻から自動計算');
          await _scheduleAlarmForTodayOrNextShift(now);
        }
        // ===================================================

        sleepProvider.endSleepingNow();
        print('[SleepButton] ✅ 睡眠中フラグをクリア');

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

  // ========== Week 26+ 修正: 新メソッド = 手動設定の起床時刻でアラーム登録 ==========
  /// 
  /// ユーザーが手動で設定した起床時刻を使用してアラームをスケジュール
  /// 優先度：手動設定 > シフト自動計算
  Future<void> _scheduleAlarmWithManualWakeUpTime(DateTime manualWakeUpTime) async {
    try {
      print('[SleepButton] 🎯 手動設定の起床時刻でアラーム登録開始');

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

      // ========== ステップ2: アラーム時刻を計算 ==========
      final alarmDateTime = manualWakeUpTime.subtract(Duration(minutes: alarmTimeBeforeShift));

      print('[SleepButton] ⏰ 手動設定時刻: ${manualWakeUpTime.hour}:${manualWakeUpTime.minute.toString().padLeft(2, '0')}');
      print('[SleepButton] 🔔 アラーム時刻: ${alarmDateTime.hour}:${alarmDateTime.minute.toString().padLeft(2, '0')}');

      // ★ アラーム時刻が未来かどうかチェック
      if (alarmDateTime.isBefore(DateTime.now())) {
        print('[SleepButton] ⚠️ アラーム時刻が過去です。スキップします。');
        return;
      }
      print('[SleepButton] ✅ アラーム時刻が未来です。登録を続行します。');
      // ================================================

      // ========== ステップ3: AlarmService でアラームをスケジュール ==========
      final alarmMode = AlarmMode.once;
      final preAlarmEnabled = alarmMode != AlarmMode.none;

      print('[SleepButton] 🚀 AlarmService でアラーム登録中...');

      // 手動設定時刻を「出勤時刻」として使用
      final wakeupTimeOfDay = TimeOfDay(hour: manualWakeUpTime.hour, minute: manualWakeUpTime.minute);
      
      await AlarmService.scheduleAlarmForShift(
        shiftDate: manualWakeUpTime,
        alarmTime: wakeupTimeOfDay,
        preAlarmEnabled: preAlarmEnabled,
        preAlarmMinutes: alarmTimeBeforeShift,
        selectedAlarmSound: selectedAlarmSound,
      );

      print('[SleepButton] ✅ 手動設定でのアラーム登録完了！');
      print('[SleepButton] 🔔 アラーム時刻: ${alarmDateTime.hour}:${alarmDateTime.minute.toString().padLeft(2, '0')}（ユーザー手動設定優先）');

    } catch (e) {
      print('[SleepButton] ❌ 手動設定アラーム登録 エラー: $e');
    }
  }

  // ========== 既存メソッド: シフト始業時刻から自動計算 ==========
  Future<void> _scheduleAlarmForTodayOrNextShift(DateTime wakeUpTime) async {
    try {
      print('[SleepButton] 🔔 起床日 + 明日以降のシフトを検索中...');

      final settings = await _shiftRepository.getAppSettings('test_user');
      if (settings == null) {
        print('[SleepButton] ⚠️ 設定が見つかりません');
        return;
      }

      final alarmTimeBeforeShift = settings.alarmTimeBeforeShift;
      final selectedAlarmSound = settings.selectedAlarmSound;

      final todayStart = DateTime(wakeUpTime.year, wakeUpTime.month, wakeUpTime.day);
      final thirtydaysLater = todayStart.add(const Duration(days: 30));

      print('[SleepButton] 📅 シフト検索期間: $todayStart ～ $thirtydaysLater');

      final shiftsMapList = await _shiftRepository.getShiftsForDateRange(todayStart, thirtydaysLater);
      
      if (shiftsMapList.isEmpty) {
        print('[SleepButton] ⚠️ 予定されたシフトが見つかりません');
        return;
      }

      // 設定した patterns を取得
      final patterns = await _shiftRepository.getAllPatterns();

      Map<String, dynamic>? nextWorkShift;
      DateTime? nextShiftDate;

      for (final shiftMap in shiftsMapList) {
        final patternId = shiftMap['pattern_id'] as String;
        final shiftDate = DateTime.parse(shiftMap['shift_date'] as String);
        
        if (patternId == 'default_dayoff' || 
            patternId == 'default_vacation_1day' || 
            patternId == 'default_vacation_half') {
          print('[SleepButton] ℹ️ スキップ: 休日/有休/半休');
          continue;
        }

        final pattern = patterns.firstWhere(
          (p) => p.id == patternId,
          orElse: () => throw Exception('Pattern not found: $patternId'),
        );
        
        final startTime = pattern.startTime;
        if (startTime == null) {
          print('[SleepButton] ⚠️ 出勤時刻が未設定');
          continue;
        }

        final shiftDateTimeWithStartTime = DateTime(
          shiftDate.year, shiftDate.month, shiftDate.day,
          startTime.hour, startTime.minute,
        );

        if (wakeUpTime.isBefore(shiftDateTimeWithStartTime)) {
          nextWorkShift = shiftMap;
          nextShiftDate = shiftDate;
          print('[SleepButton] ✅ シフト(当番日)を使用');
          break;
        } else {
          print('[SleepButton] ℹ️ スキップ（翌日を探す）');
          continue;
        }
      }

      if (nextWorkShift == null || nextShiftDate == null) {
        print('[SleepButton] ⚠️ 出勤予定が見つかりません');
        return;
      }

      final alarmDateTime = DateTime(
        nextShiftDate.year, nextShiftDate.month, nextShiftDate.day,
        0, 0,
      ).subtract(Duration(minutes: alarmTimeBeforeShift));

      if (alarmDateTime.isBefore(DateTime.now())) {
        print('[SleepButton] ⚠️ アラーム時刻が過去です。スキップします。');
        return;
      }

      final alarmMode = AlarmMode.once;
      final preAlarmEnabled = alarmMode != AlarmMode.none;

      await AlarmService.scheduleAlarmForShift(
        shiftDate: nextShiftDate,
        alarmTime: const TimeOfDay(hour: 0, minute: 0),
        preAlarmEnabled: preAlarmEnabled,
        preAlarmMinutes: alarmTimeBeforeShift,
        selectedAlarmSound: selectedAlarmSound,
      );

      print('[SleepButton] ✅ 自動計算でのアラーム登録完了！');

    } catch (e) {
      print('[SleepButton] ❌ 自動計算アラーム登録 エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SleepProvider>(
      builder: (context, sleepProvider, child) {
        final isSleeping = sleepProvider.isSleepingNow;

        return GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primaryGradientStart,
                    AppColors.primaryGradientEnd,
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGradientStart.withOpacity(0.3),
                    blurRadius: 10.0,
                    spreadRadius: 2.0,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  isSleeping ? '💤 睡眠中...\n起きる' : '今から\n寝る',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.buttonTextStyle.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum AlarmMode {
  none,
  once,
  twice,
}