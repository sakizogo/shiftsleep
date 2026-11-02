import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/calendar_range.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/confirm_alarm_plan.dart';
import 'shift_management_screen.dart';

class ShiftDetailScreen extends StatefulWidget {
  final Map<DateTime, ShiftData> shiftDataMap;
  final List<ShiftPatternModel> patterns;

  // ========== Week 3 Day 5 追加: 戻るコールバック ==========
  final VoidCallback? onBack;
  // ======================================================

  const ShiftDetailScreen({
    Key? key,
    required this.shiftDataMap,
    required this.patterns,
    this.onBack,  // ← 追加
  }) : super(key: key);

  @override
  State<ShiftDetailScreen> createState() => _ShiftDetailScreenState();
}

class _ShiftDetailScreenState extends State<ShiftDetailScreen> {
  late TimeOfDay _customStartTime;
  late TimeOfDay _customEndTime;
  final ShiftRepository _shiftRepository = ShiftRepository();  // ========== Week 3 Day 6-2 追加 ==========
  bool _isSaving = false;  // N117：確定の処理中（上下 2 つの確定ボタンを押せなくする）

  @override
  void initState() {
    super.initState();
    _customStartTime = const TimeOfDay(hour: 8, minute: 30);
    _customEndTime = const TimeOfDay(hour: 17, minute: 0);
  }

  @override
  Widget build(BuildContext context) {
    // シフトデータを日付順にソート
    final sortedDates = widget.shiftDataMap.keys.toList()..sort();

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        centerTitle: true,
        // ========== Week 3 Day 5 削除: 戻るボタンを削除（タブ機能で戻る） ==========
        // leading: IconButton(...) を削除
        // ================================================================
        title: Text(
          'シフト詳細確認',
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
              // サマリー
              // ========================
              Container(
                padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                decoration: BoxDecoration(
                  color: AppColors.primaryGradientStart.withOpacity(0.1),
                  border: Border.all(
                    color: AppColors.primaryGradientStart.withOpacity(0.3),
                  ),
                  borderRadius: BorderRadius.circular(
                    AppDimensions.borderRadiusMedium,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '設定済みシフト',
                          style: AppTextStyles.bodyTextStyle.copyWith(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          '${widget.shiftDataMap.length}日間',
                          style: AppTextStyles.largeNumberStyle.copyWith(
                            fontSize: 28,
                            color: AppColors.primaryGradientStart,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.check_circle,
                      size: 48,
                      color: AppColors.primaryGradientStart,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.paddingLarge),
              // ========== Week 3 Day 7: 上部シフト保存ボタン ==========
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveShifts,  // N117：処理中は押せない
                  style: ElevatedButton.styleFrom(
                     backgroundColor: AppColors.primaryGradientStart,
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
                     'シフトを確定',
                     style: AppTextStyles.bodyTextStyle.copyWith(
                       color: Colors.white,
                       fontWeight: FontWeight.w600,
                       fontSize: 16,
                     ),
                   ),
                 ),
               ),

const SizedBox(height: AppDimensions.paddingLarge),
// ================================================================
              // ========================
              // シフト一覧
              // ========================
              Text(
                'シフト一覧',
                style: AppTextStyles.sectionTitleStyle,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),

              if (sortedDates.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppDimensions.paddingLarge,
                    ),
                    child: Text(
                      'シフトが設定されていません',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                )
              else
                ...sortedDates.map((date) {
                  final shiftData = widget.shiftDataMap[date]!;
                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppDimensions.paddingSmall,
                    ),
                    child: _buildShiftCard(date, shiftData),
                  );
                }).toList(),

              const SizedBox(height: AppDimensions.paddingMedium),

              // ========== Week 3 Day 7: シフト一覧下の保存ボタン ==========
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveShifts,  // N117：処理中は押せない
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGradientStart,
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
                    'シフトを確定',
                    style: AppTextStyles.bodyTextStyle.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              // ================================================================

              
              const SizedBox(height: AppDimensions.paddingLarge),
            ],
          ),
        ),
      ),
    );
  }

  /// ========== Week 6 Fix C: シフトカード（色表示機能追加） ==========
  /// シフトカード
  Widget _buildShiftCard(DateTime date, ShiftData shiftData) {
    final dayOfWeek = _getDayOfWeek(date);
    final pattern = shiftData.pattern;
    final patternColor = pattern?.color ?? AppColors.textMuted;

    // ========== Fix C 修正: ClipRRectで角丸を実現 ==========
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        AppDimensions.borderRadiusMedium,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            left: BorderSide(
              color: patternColor,
              width: 8.0,  // ← 色付き左枠の幅
            ),
            top: BorderSide(
              color: AppColors.borderDefault,
            ),
            right: BorderSide(
              color: AppColors.borderDefault,
            ),
            bottom: BorderSide(
              color: AppColors.borderDefault,
            ),
          ),
        ),
        // ===================================================================
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日付 + 曜日
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${date.month}月${date.day}日（${dayOfWeek}）',
                style: AppTextStyles.bodyTextStyle.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              // N104：削除済みの仮パターンも種類は dayOff だが、「休日」の札は出さない
              if (pattern?.patternType == ShiftType.dayOff && pattern?.isDeleted != true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.paddingSmall,
                    vertical: 2.0,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cardBgAlert,
                    borderRadius: BorderRadius.circular(
                      AppDimensions.borderRadiusSmall,
                    ),
                  ),
                  child: Text(
                    '休日',
                    style: AppTextStyles.bodyTextStyle.copyWith(
                      fontSize: 11,
                      color: AppColors.warningRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppDimensions.paddingSmall),

          // ========== Fix C 追加: パターン名の前に色付き■を追加 ==========
          // パターン名
          if (pattern != null)
            Row(
              children: [
                // 色を示す小さな■（12×12px）
                Container(
                  width: 12.0,
                  height: 12.0,
                  decoration: BoxDecoration(
                    color: patternColor,
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                ),
                const SizedBox(width: 8.0),
                // パターン名
                Expanded(
                  child: Text(
                    pattern.patternName,
                    style: AppTextStyles.bodyTextStyle.copyWith(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          // ===================================================================

          // 時間情報
          if (pattern?.patternType == ShiftType.work &&
              pattern?.startTime != null &&
              pattern?.endTime != null)
            Padding(
              padding: const EdgeInsets.only(
                top: AppDimensions.paddingSmall,
              ),
              child: Text(
                '${pattern!.startTime!.hour.toString().padLeft(2, '0')}:${pattern!.startTime!.minute.toString().padLeft(2, '0')} ～ ${pattern!.endTime!.hour.toString().padLeft(2, '0')}:${pattern!.endTime!.minute.toString().padLeft(2, '0')}',
                style: AppTextStyles.bodyTextStyle.copyWith(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          // 編集ボタン
          const SizedBox(height: AppDimensions.paddingSmall),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                _showEditDialog(date, shiftData);
              },
              child: Text(
                '編集',
                style: AppTextStyles.bodyTextStyle.copyWith(
                  fontSize: 12,
                  color: AppColors.primaryGradientStart,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      ),  // ← Container と ClipRRect の閉じタグ
    );
  }
  // ==============================================================================

  /// 編集ダイアログ
  void _showEditDialog(DateTime date, ShiftData shiftData) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            '${date.month}月${date.day}日のシフト編集',
            style: AppTextStyles.sectionTitleStyle,
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'パターン選択',
                  style: AppTextStyles.bodyTextStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8.0),
                ...widget.patterns.map((pattern) {
                  final isSelected = shiftData.pattern?.id == pattern.id;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        widget.shiftDataMap[date] = ShiftData(
                          date: date,
                          pattern: pattern,
                        );
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 6.0,
                      ),
                      margin: const EdgeInsets.only(bottom: 6.0),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryGradientStart.withOpacity(0.1)
                            : AppColors.cardBgGray,
                        borderRadius: BorderRadius.circular(
                          AppDimensions.borderRadiusSmall,
                        ),
                      ),
                      child: Text(
                        pattern.patternName,
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontSize: 13,
                          color: isSelected
                              ? AppColors.primaryGradientStart
                              : AppColors.textSecondary,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 16.0),
                Text(
                  '削除',
                  style: AppTextStyles.bodyTextStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.warningRed,
                  ),
                ),
                const SizedBox(height: 8.0),
                GestureDetector(
                  onTap: () {
                    print('🔍 削除ボタンタップ開始 - date: $date');

                    // N117：ここではアラームを取り消さない（DB はまだ変わらないため）
                    // 「シフトを確定」で DB に書けたあと、消した日の pre はまとめて取り消される
                    setState(() {
                      widget.shiftDataMap.remove(date);
                    });

                    print('🔍 ダイアログを閉じる');
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 6.0,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cardBgAlert,
                      borderRadius: BorderRadius.circular(
                        AppDimensions.borderRadiusSmall,
                      ),
                    ),
                    child: Text(
                      'このシフトを削除',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        fontSize: 13,
                        color: AppColors.warningRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'キャンセル',
                style: AppTextStyles.bodyTextStyle.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 曜日を取得
  String _getDayOfWeek(DateTime date) {
    const days = ['月', '火', '水', '木', '金', '土', '日'];
    return days[date.weekday - 1];
  }

  /// ========== Phase 3.2 修正: シフト保存 + アラームスケジュール ==========
  /// シフトを保存 + アラームをスケジュール
  /// N117：処理中は確定ボタンを押せない（二度押しで全件削除と作り直しが入り混じらないように）
  Future<void> _saveShifts() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _saveShiftsAndScheduleAlarms();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveShiftsAndScheduleAlarms() async {
    // ========== デバッグログ追加 ==========
    print('💾 保存開始 - シフト数: ${widget.shiftDataMap.length}');
    print('💾 保存データ:');
    for (final entry in widget.shiftDataMap.entries) {
      print('  - ${entry.key.toIso8601String()}: ${entry.value.pattern?.patternName}');
    }
    // ====================================

    // Map<DateTime, ShiftData> を Map<DateTime, ShiftPatternModel?> に変換
    final Map<DateTime, ShiftPatternModel?> patternMap = {};
    for (final entry in widget.shiftDataMap.entries) {
      patternMap[entry.key] = entry.value.pattern;
    }

    // ✅ ShiftPre: 出勤前アラームの設定値を1回だけ取得（行がなければ既定の30分）
    // N118：読めなかったら確定ごとやめる（シフト・アラームには触らず、詳細確認画面に残る）
    final int alarmTimeBeforeShift;
    try {
      final alarmSettings = await _shiftRepository.getAppSettings('test_user');
      alarmTimeBeforeShift = alarmSettings?.alarmTimeBeforeShift ?? 30;
    } catch (e) {
      debugPrint('Error loading settings before saving shifts: $e');
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('❌ 設定を読み込めなかったため、確定しませんでした。もう一度お試しください'),
          backgroundColor: AppColors.warningRed,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // N117：全件削除と作り直しを 1 つのトランザクションで行う（失敗したら確定前の行に戻る）
    // アラームはこれが成功してから動かす（失敗したらアラームには一切触らない）
    final List<({String shiftDate, String? patternId})> oldShifts;
    try {
      oldShifts = await _shiftRepository.replaceAllShifts(patternMap);
    } catch (e) {
      // 詳細確認画面に残り（編集した内容はそのまま）、アラームには進まない
      debugPrint('Error saving shifts: $e');
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ シフトの保存に失敗しました: $e'),
          backgroundColor: AppColors.warningRed,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    print('✅ DB保存完了');

    // N117：古い行の日の pre を取り消し、新しい出勤日の pre を登録する（どちらも今日〜CalendarRange の終わり）
    final plan = confirmAlarmPlan(oldShifts, patternMap, DateTime.now(), CalendarRange.lastDate);
    String? alarmErrorCode;  // ✅ Step2-2: 取り消し・登録の失敗を記録（EXACT_ALARM_DENIED を優先）

    // ✅ H3: pre だけを取り消す（main＝起床アラームは残す）。1 日失敗しても最後まで続ける
    for (final date in plan.cancel) {
      try {
        await AlarmService.cancelPreAlarm(date);
      } catch (e) {
        debugPrint('Error cancelling pre alarm ($date): $e');
        if (alarmErrorCode != 'EXACT_ALARM_DENIED') alarmErrorCode = 'SCHEDULE_FAILED';
      }
    }
    print('🔕 古いシフトの出勤前アラーム（pre）を取り消し: ${plan.cancel.length}件');

    // ✅ ========== Phase 3.2 追加: アラームをスケジュール ==========
    print('⏰ アラームスケジュール開始...');
    // N117：シフトは保存できているので、ここで例外が起きても「保存に失敗」にはせず、アラームの ⚠️ で知らせる
    try {
      // ✅ ShiftPre: 出勤前アラームの設定値は確定の前に読んだもの（N118）を使う
      // ✅ ShiftPre: 出勤前アラームが「無効（0）」なら登録しない
      if (alarmTimeBeforeShift <= 0) {
        print('ℹ️ 出勤前アラームが無効（0）のため、シフト勤務アラームは登録しません');
      } else {
        for (final shift in plan.schedule) {
          print('🔔 アラームスケジュール: ${shift.date}, 出勤時刻: ${shift.startTime.hour}:${shift.startTime.minute}');

          final errorCode = await AlarmService.scheduleAlarmForShift(
            shiftDate: shift.date,
            alarmTime: shift.startTime,
            mainAlarmEnabled: false,  // ✅ ShiftPre: 出勤時刻ちょうどのアラームは登録しない
            preAlarmEnabled: true,
            preAlarmMinutes: alarmTimeBeforeShift,  // ✅ ShiftPre: 5分前固定を廃止し、設定値を使用
            selectedAlarmSound: 'default',
          );
          if (errorCode != null && alarmErrorCode != 'EXACT_ALARM_DENIED') {
            alarmErrorCode = errorCode;
          }
        }
      }
      // ✅ Step1-B: 過去時刻はスキップされ得るため「完了」と断定しない
      print('📨 アラーム登録処理を実行完了（${plan.schedule.length}件） ※登録/スキップの結果は [AlarmService] ログを参照');
    } catch (e) {
      debugPrint('Error scheduling shift alarms: $e');
      if (alarmErrorCode != 'EXACT_ALARM_DENIED') alarmErrorCode = 'SCHEDULE_FAILED';
    }
    // ==============================================================

    // 成功メッセージ
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('✅ シフトを保存しました'),
        backgroundColor: AppColors.primaryGradientStart,
        duration: const Duration(seconds: 2),
      ),
    );
    // ✅ Step2-2: アラームの取り消し・登録に失敗した場合は、保存完了の後に警告を1回だけ表示
    final alarmError = AlarmService.alarmErrorMessage(alarmErrorCode);
    if (alarmError != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(alarmError),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }

    // onBack コールバック実行で戻る
    if (widget.onBack != null) {
      widget.onBack!();
    }
  }
  // ==============================================================================
  // ==============================================================================
}