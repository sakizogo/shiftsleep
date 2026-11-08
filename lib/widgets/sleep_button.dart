import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/colors.dart';
import '../constants/text_styles.dart';
import '../constants/dimensions.dart';
import 'package:uuid/uuid.dart';
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/wake_up_service.dart';
import '../services/wake_alarm_choice.dart';  // N118
import '../services/wake_alarm_registration_service.dart';  // N19

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
    // ✅ Step2-2: 処理中にこの Widget が破棄されても通知できるよう、最初の await より前に取得
    final messenger = ScaffoldMessenger.of(context);
    try {
      // ✅ H4: アラームON/OFF は SharedPreferences（AlarmService.isAlarmEnabled）を正規の保存先として判定
      final isAlarmEnabled = await AlarmService.isAlarmEnabled();  // 未保存なら true
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

      // N121：記録を保存できなかったら睡眠中にせず、アラームも登録しない
      try {
        await sleepProvider.insertSleepRecord(sleepRecord);
      } catch (e) {
        debugPrint('[SleepButton] ❌ 睡眠の記録を保存できませんでした: $e');
        messenger.showSnackBar(
          SnackBar(
            content: Text('❌ 睡眠の記録を保存できませんでした: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // ✨ Step 7：isAlarmEnabled が true の場合のみアラームをセット
      // N19：手動起床と今日の出勤前アラームから、登録するものを決める（手動が早ければ 2 本）
      String? alarmWarning;  // N118：設定・シフトを読めなかったときの ⚠️（「💤 睡眠中」のあとに出す）
      // N121：記録は保存できているので、ここで失敗しても睡眠中のままにして ⚠️ で知らせる
      try {
        if (isAlarmEnabled) {
          print('[SleepButton] ✅ アラーム有効：起床アラームをセット');
          alarmWarning = await _scheduleWakeAlarm(now, messenger);
        } else {
          print('[SleepButton] ⚠️ アラーム無効：アラームをセットしません');
        }
      } catch (e) {
        debugPrint('[SleepButton] ❌ 記録の保存後の処理に失敗: $e');
        alarmWarning = '⚠️ 睡眠は記録しましたが、アラームを登録できませんでした。『起きる』→『今から寝る』をやり直してください';
      }

      print('[SleepButton] ✅ Sleep record saved');

      // N133：ホームがスピナーに置き換わるとこの Widget は破棄されるので、mounted で飛ばさず messenger で出す
      messenger.showSnackBar(
        const SnackBar(
          content: Text('💤 睡眠中...「起きる」ボタンで終了します'),
          duration: Duration(seconds: 3),
        ),
      );

      widget.onPressed?.call();

      if (alarmWarning != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(alarmWarning),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
      }

    } catch (e) {
      print('[SleepButton] ❌ Error starting sleep: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ エラー: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  // ==================================================

  // ========== Week 26+ Step 7：「起きる」ボタン処理 ==========
  Future<void> _handleWakeUp(SleepProvider sleepProvider) async {
    // N133：処理中にこの Widget が破棄されても知らせを出せるよう、最初の await より前に取得
    final messenger = ScaffoldMessenger.of(context);
    try {
      print('[SleepButton] 🛏️ _handleWakeUp メソッドが呼ばれました');

      // 起床処理本体は WakeUpService に集約（当日の main・pre アラームもキャンセル）
      final result = await WakeUpService.wakeUp(sleepProvider, DateTime.now());

      // N142：記録なしの起床では ✅ を出さない
      if (result.recorded) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ 起床しました。睡眠が記録されました。'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      // N19：✅ のあとに続けて知らせる
      for (final text in wakeUpWarningTexts(result)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(text),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
      }

      widget.onPressed?.call();
    } catch (e) {
      print('[SleepButton] ❌ Error waking up: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ エラー: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  // ==================================================

  /// N19：判定と登録は WakeAlarmRegistrationService にまとめた。ここでは設定を読み、結果を知らせる
  /// ⏰ の案内はここで出す。戻り値は「💤 睡眠中」のあとに出す ⚠️ の文言（なければ null）
  Future<String?> _scheduleWakeAlarm(DateTime now, ScaffoldMessengerState messenger) async {
    // N118：設定はここで 1 回だけ読む（行がない・読めない → 既定値で進める）
    // N118 2b：読めなかったときの ⚠️ は wakeAlarmMessages が出す（登録できたとき・none で出勤がまだ先のときだけ）
    final read = await _readWakeAlarmSettings(now);

    final result = await WakeAlarmRegistrationService.register(
      now: now,
      settings: read.settings,
      vibrateOnMain: true,
      settingsReadFailed: read.failed,
    );
    final messages = wakeAlarmMessages(result);
    final warnings = messages.where((message) => message.color != null).map((message) => message.text);
    final infos = messages.where((message) => message.color == null);

    // 設定画面の「更新されました」などが順番待ちしていると埋もれるため、先に消してから表示
    // ⏰ は登録に失敗していないときだけなので、⚠️ を消すことはない
    if (infos.isNotEmpty) {
      messenger.clearSnackBars();
      for (final message in infos) {
        messenger.showSnackBar(
          SnackBar(content: Text(message.text), duration: const Duration(seconds: 6)),
        );
      }
    }

    return warnings.isEmpty ? null : warnings.join('\n');
  }

  /// N118：起床アラームに使う設定を読む
  /// 行がない → AppSettings の既定値（出勤前 30 分・音 default）で普通に進める
  /// 読めなかった → 既定値で進め、failed を立てる（呼ぶ側で知らせる）
  Future<({AppSettings settings, bool failed})> _readWakeAlarmSettings(DateTime now) async {
    AppSettings defaults() => AppSettings(id: 1, userId: 'test_user', createdAt: now, updatedAt: now);
    try {
      final settings = await _shiftRepository.getAppSettings('test_user');
      if (settings == null) {
        debugPrint('[SleepButton] ⚠️ 設定が見つかりません（既定値で登録します）');
      }
      return (settings: settings ?? defaults(), failed: false);
    } catch (e) {
      debugPrint('[SleepButton] ❌ 設定を読めませんでした（既定値で登録します）: $e');
      return (settings: defaults(), failed: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ========== Week 7 Phase 3 修正: SleepProvider から睡眠状態を監視 ==========
    return Consumer<SleepProvider>(
      builder: (context, sleepProvider, _) {
        // N142：復元が終わるまでは、睡眠中かどうかわからないので押せない（GestureDetector を置かない）
        if (!sleepProvider.isSleepStateRestored) {
          return _buildRestoring();
        }

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

  /// N142：睡眠状態の復元中の表示（ボタンと同じ大きさ。タップしても何も起きない）
  Widget _buildRestoring() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryGradientStart.withValues(alpha: 0.6),
            AppColors.primaryGradientEnd.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 3,
            semanticsLabel: '読み込み中',
          ),
        ),
      ),
    );
  }
}