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
      await sleepProvider.insertSleepRecord(sleepRecord);
      await sleepProvider.setCurrentSleepRecordIdNow(sleepRecord.id);
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

            // ========== Week 26+ 修正: 時間帯判定を削除 → 常にアラーム登録 ==========
            // ユーザー要件：昼間起床時でもその日のシフトがあればアラーム登録
            print('[SleepButton] 🔔 アラームをスケジュール中（時間帯関係なく）...');
            await _scheduleAlarmForTodayOrNextShift(now);
            // =========================================================================

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

  // ========== Week 26+ 修正: 新しいメソッド = その日 + 明日以降のシフトを検索 ==========
  /// 
  /// 起床時刻に関わらず、最初のシフトを見つけてアラームをスケジュール
  /// 
  /// 流れ:
  /// 1. 「起きた日」のシフトを確認
  /// 2. その日にシフトがなければ、明日以降30日間のシフトを検索
  /// 3. 最初の出勤シフトを見つける
  /// 4. 出勤時刻から alarmTimeBeforeShift 分前にアラーム実行
  /// 5. AlarmService.scheduleAlarmForShift() で実行（登録直後には鳴らない）
  Future<void> _scheduleAlarmForTodayOrNextShift(DateTime wakeUpTime) async {
    try {
      print('[SleepButton] 🔔 起床日 + 明日以降のシフトを検索中...');

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

      // ========== ステップ2: 起床日 + 明日以降30日間のシフトを取得 ==========
      final todayStart = DateTime(wakeUpTime.year, wakeUpTime.month, wakeUpTime.day);
      final thirtydaysLater = todayStart.add(const Duration(days: 30));

      print('[SleepButton] 📅 シフト検索期間: $todayStart ～ $thirtydaysLater');

      final shiftsMapList = await _shiftRepository.getShiftsForDateRange(todayStart, thirtydaysLater);
      print('[SleepButton] 📊 getShiftsForDateRange の結果: ${shiftsMapList.length}件');
      
      if (shiftsMapList.isEmpty) {
        print('[SleepButton] ⚠️ 予定されたシフトが見つかりません');
        return;
      }

      print('[SleepButton] 📅 ${shiftsMapList.length}件のシフトが見つかりました');
      // ==================================================

      // ========== ステップ3: 最初の「work」シフトを見つける（休日・有休は除外） ==========
      Map<String, dynamic>? nextWorkShift;
      DateTime? nextShiftDate;

      for (final shiftMap in shiftsMapList) {
        final patternId = shiftMap['pattern_id'] as String;
        
        print('[SleepButton] 🔍 チェック中: pattern_id=$patternId');
        
        // デフォルト休日・有休・半休は skip
        if (patternId == 'default_dayoff' || 
            patternId == 'default_vacation_1day' || 
            patternId == 'default_vacation_half') {
          print('[SleepButton] ℹ️ スキップ: 休日/有休/半休');
          continue;
        }

        nextWorkShift = shiftMap;
        nextShiftDate = DateTime.parse(shiftMap['shift_date'] as String);
        print('[SleepButton] ✅ 次のシフト: $nextShiftDate / pattern_id=$patternId');
        break;
      }

      if (nextWorkShift == null || nextShiftDate == null) {
        print('[SleepButton] ⚠️ 出勤予定が見つかりません（全てが休日/有休）');
        return;
      }
      // ======================================================

      // ========== ステップ4: patternId から出勤時刻を取得 ==========
      final patterns = await _shiftRepository.getAllPatterns();
      print('[SleepButton] 🎯 getAllPatterns で${patterns.length}個のパターンを取得');
      
      final pattern = patterns.firstWhere(
        (p) => p.id == nextWorkShift!['pattern_id'],
        orElse: () => throw Exception('Pattern not found: ${nextWorkShift!['pattern_id']}'),
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
      
      // ★ Week 26+ 重要: アラーム時刻が未来かどうかチェック
      if (alarmDateTime.isBefore(DateTime.now())) {
        print('[SleepButton] ⚠️ アラーム時刻が過去です。スキップします。');
        return;
      }
      print('[SleepButton] ✅ アラーム時刻が未来です。登録を続行します。');
      // ================================================

      // ========== ステップ6: AlarmService でアラームをスケジュール ==========
      // 登録直後には鳴らない（設定時刻になったら自動的に鳴る）
      final alarmMode = AlarmMode.once;  // デフォルトは once
      final preAlarmEnabled = alarmMode != AlarmMode.none;

      print('[SleepButton] 🚀 AlarmService.scheduleAlarmForShift() を呼び出し中...');

      await AlarmService.scheduleAlarmForShift(
        shiftDate: nextShiftDate,
        alarmTime: startTime,
        preAlarmEnabled: preAlarmEnabled,
        preAlarmMinutes: alarmTimeBeforeShift,
        selectedAlarmSound: selectedAlarmSound,
      );

      print('[SleepButton] ✅ アラームをスケジュール完了！');
      print('[SleepButton] 📍 シフト日: $nextShiftDate / 出勤時刻: ${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')}');
      print('[SleepButton] 🔔 アラーム時刻: $alarmDateTime（設定時刻に自動発火）');
      // ========================================================================

    } catch (e) {
      print('[SleepButton] ❌ アラームスケジュール エラー: $e');
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
                  isSleeping ? '💤 睡眠中...\n起きる' : '今から寝る',
                  textAlign: TextAlign.center,  // ← この行を追加
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

// ========== AlarmMode enum (AlarmService と同期) ==========
enum AlarmMode {
  none,   // アラーム無効
  once,   // 1回（出勤前アラームのみ）
  twice,  // 2回（出勤前 + 出勤時）
}