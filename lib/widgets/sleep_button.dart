import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/text_styles.dart';
import '../constants/dimensions.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/repositories/alarm_repository.dart';
import 'package:uuid/uuid.dart';
import 'package:shiftsleep/models/sleep_record.dart';              // ← 追加
import 'package:shiftsleep/repositories/sleep_repository.dart';    // ← 追加            

class SleepButton extends StatefulWidget {
  final String userId;  // ← 追加
  final VoidCallback? onPressed;  // 

  const SleepButton({
    Key? key,
    this.userId = 'test_user',  // ← 追加
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

   // ✅ 以下を追加
  final SleepRepository _sleepRepository = SleepRepository();
  final AlarmRepository _alarmRepository = AlarmRepository();
  // ✅ ここまで

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

  try {
    // 1. SleepRecord を作成 & DB 保存
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

    await _sleepRepository.insertSleepRecord(sleepRecord);
    print('[SleepButton] ✅ Sleep record saved: ${sleepRecord.id}');

    // 2. AlarmService を初期化
    final alarmService = AlarmService();
    if (!alarmService.isInitialized) {
      await alarmService.initialize();
    }

    // 3. アラーム設定を取得
    final alarmConfig = await _alarmRepository.getAlarmConfigByUserId(widget.userId);

    // 4. アラームをスケジュール
    if (alarmConfig != null) {
      await alarmService.scheduleAlarm(
        sleepTime: now.toIso8601String(),
        wakeupTime: '07:00',
        config: alarmConfig,
      );
      print('[SleepButton] ✅ Alarm scheduled');
    }

    // 5. メッセージ表示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 睡眠記録を保存しました\n🔔 アラームをセットしました'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    // 既存のコールバック実行
    widget.onPressed?.call();
  } catch (e) {
    print('[SleepButton] ❌ Error: $e');
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
// ✅ 以下を追加
  void _onTapCancel() {
    _controller.reverse();
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryGradientStart,
                AppColors.primaryGradientEnd,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 12,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              '今から寝る',
              textAlign: TextAlign.center,
              style: AppTextStyles.buttonTextStyle,
            ),
          ),
        ),
      ),
    );
  }
  // ✅ ここまで
}  // ← これ（クラスの終わり）