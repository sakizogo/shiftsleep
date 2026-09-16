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

  // ============ Week 26+ 修正：就寝時にアラーム登録（今日 or 明日を正しく判定） ============
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

      // ✅ Step 1️⃣：設定を読み込み
      final settings = await _shiftRepository.getAppSettings('test_user');
      if (settings == null) {
        print('[SleepButton] ⚠️ 設定が見つかりません');
        sleepProvider.setAlarmSet(false);
        return;
      }

      final wakeUpTimeStr = settings.wakeUpTime;  // "07:00" 形式
      final alarmTimeBeforeShift = settings.alarmTimeBeforeShift;  // 30（分）
      final selectedAlarmSound = settings.selectedAlarmSound;  // 'default'

      print('[SleepButton] ⏰ 設定取得: wakeUpTime=$wakeUpTimeStr, 出勤前=${alarmTimeBeforeShift}分, 音=$selectedAlarmSound');

      // ✅ Step 2️⃣：wakeUpTime を "07:00" から TimeOfDay に変換
      final timeParts = wakeUpTimeStr.split(':');
      if (timeParts.length != 2) {
        print('[SleepButton] ❌ 無効な時刻形式: $wakeUpTimeStr');
        sleepProvider.setAlarmSet(false);
        return;
      }

      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final alarmTime = TimeOfDay(hour: hour, minute: minute);
      
      print('[SleepButton] ✅ TimeOfDay に変換: ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}');

      // ✅ Step 3️⃣：今日の起床時刻がまだ未来か判定
      final todayWakeUp = DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      print('[SleepButton] 🕐 現在時刻: $now');
      print('[SleepButton] 🕐 今日の起床時刻: $todayWakeUp');
      print('[SleepButton] 🕐 比較: todayWakeUp.isAfter(now) = ${todayWakeUp.isAfter(now)}');

      late DateTime shiftDate;
      if (todayWakeUp.isAfter(now)) {
        // ✅ 今日の起床時刻がまだ未来 → 今日のアラームを登録
        shiftDate = DateTime(now.year, now.month, now.day);
        print('[SleepButton] 📆 今日のアラームを登録: $shiftDate');
      } else {
        // ✅ 今日の起床時刻は過去 → 明日のアラームを登録
        shiftDate = DateTime(now.year, now.month, now.day + 1);
        print('[SleepButton] 📆 明日のアラームを登録: $shiftDate');
      }

      print('[SleepButton] 📞 AlarmService.scheduleAlarmForShift() を呼び出し中...');
      print('[SleepButton]   - shiftDate: $shiftDate');
      print('[SleepButton]   - alarmTime: ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}');
      print('[SleepButton]   - preAlarmMinutes: $alarmTimeBeforeShift');
      print('[SleepButton]   - selectedAlarmSound: $selectedAlarmSound');

      await AlarmService.scheduleAlarmForShift(
        shiftDate: shiftDate,
        alarmTime: alarmTime,
        preAlarmEnabled: true,
        preAlarmMinutes: alarmTimeBeforeShift,
        selectedAlarmSound: selectedAlarmSound,
      );

      sleepProvider.setAlarmSet(true);
      print('[SleepButton] ✅ アラーム登録完了！');

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
      sleepProvider.setAlarmSet(false);
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
  // ===========================================================

  // ============ Week 26+ 修正：起床時にアラームキャンセル ============
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

        // ✅ Step 1️⃣：アラームをキャンセル
        // cancelAlarm(DateTime date) は日付を指定してキャンセル
        print('[SleepButton] 🛑 アラームをキャンセル中（日付: ${now}）...');
        await AlarmService.cancelAlarm(now);
        // ✅ 現在再生中のアラーム音を停止
        await AlarmService.stopAlarmSound();
        print('[SleepButton] 🛑 アラーム音停止完了');
        print('[SleepButton] ✅ アラームキャンセル完了！');

        sleepProvider.setAlarmSet(false);
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
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    return Consumer<SleepProvider>(
      builder: (context, sleepProvider, child) {
        final isSleeping = sleepProvider.isSleepingNow;
        final isAlarmSet = sleepProvider.isAlarmSet;

        return GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
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
                      isSleeping ? '💤 睡眠中...\n起きる' : '今から寝る',
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
              if (isAlarmSet) ...[
                const SizedBox(height: 12),
                Text(
                  '🔔 アラーム設定中',
                  style: AppTextStyles.buttonTextStyle.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
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