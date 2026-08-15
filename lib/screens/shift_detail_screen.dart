import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
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
                  onPressed: _saveShifts,
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
                     'シフトを保存',
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
                  onPressed: _saveShifts,
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
                    'シフトを保存',
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
              if (pattern?.patternType == ShiftType.dayOff)
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
                    setState(() {
                      widget.shiftDataMap.remove(date);
                    });
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

  /// ========== Week 3 Day 6-2 修正: シフトをDB に保存 ==========
  /// シフトを保存
  Future<void> _saveShifts() async {
    try {
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

       // DB に保存
       await _shiftRepository.createShifts(patternMap);

       print('✅ DB保存完了');

      // 成功メッセージ
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.shiftDataMap.length}日間のシフトを保存しました'),
            backgroundColor: AppColors.primaryGradientStart,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // onBack コールバック実行で戻る
      if (widget.onBack != null) {
        widget.onBack!();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('シフト保存に失敗しました: $e'),
            backgroundColor: AppColors.warningRed,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      print('Error saving shifts: $e');
    }
  }
  // ==============================================================================
}