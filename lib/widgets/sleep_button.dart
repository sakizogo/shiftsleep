import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/colors.dart';
import '../constants/text_styles.dart';
import '../constants/dimensions.dart';
import 'package:uuid/uuid.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';

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

  bool _isSleeping = false;
  String? _currentSleepRecordId;

  final SleepRepository _sleepRepository = SleepRepository();

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

    if (_isSleeping) {
      await _handleWakeUp();
    } else {
      await _handleStartSleep();
    }
  }

  void _onTapCancel() {
    _controller.reverse();
    setState(() => _isPressed = false);
  }

  Future<void> _handleStartSleep() async {
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

      await _sleepRepository.insertSleepRecord(sleepRecord);
      print('[SleepButton] ✅ Sleep record saved: ${sleepRecord.id}');

      setState(() {
        _isSleeping = true;
        _currentSleepRecordId = sleepRecord.id;
      });

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

  Future<void> _handleWakeUp() async {
    try {
      if (_currentSleepRecordId == null) {
        throw Exception('Sleep record ID not found');
      }

      final now = DateTime.now();

      final sleepRecord =
          await _sleepRepository.getSleepRecordById(_currentSleepRecordId!);

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

        if (mounted) {
          await context.read<SleepProvider>().loadAllSleepData();
        }
      }

      setState(() {
        _isSleeping = false;
        _currentSleepRecordId = null;
      });

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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isSleeping
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
                color: Colors.black.withOpacity(_isSleeping ? 0.1 : 0.15),
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
                _isSleeping ? '睡眠中' : '今から寝る',
                textAlign: TextAlign.center,
                style: AppTextStyles.buttonTextStyle.copyWith(
                  fontSize: _isSleeping ? 14 : 16,
                ),
              ),
              if (_isSleeping)
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
  }
}