import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/screens/shift_management_screen.dart';


class ShiftPatternScreen extends StatefulWidget {
  final ShiftPatternMode mode;
  final ShiftPatternModel? editingPattern;
  final Function(List<ShiftPatternModel>)? onPatternsChanged;
  final List<ShiftPatternModel>? existingPatterns;

  const ShiftPatternScreen({
    Key? key,
    this.mode = ShiftPatternMode.register,
    this.editingPattern,
    this.onPatternsChanged,
    this.existingPatterns,
  }) : super(key: key);

  @override
  State<ShiftPatternScreen> createState() => _ShiftPatternScreenState();
}

class _ShiftPatternScreenState extends State<ShiftPatternScreen> {
  final TextEditingController _patternNameController = TextEditingController();
  // ========== Week 3 Day 6-1 修正: ShiftType.work のみに固定 ==========
  // ShiftType.dayOff は削除（デフォルト休日があるため不要）
  // =================================================================
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 30);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  late List<ShiftPatternModel> _patterns;
  final ShiftRepository _shiftRepository = ShiftRepository();  // ========== Week 3 Day 8 追加 ==========

  @override
  void initState() {
    super.initState();
    _patterns = List.from(widget.existingPatterns ?? []);

    // 編集モードの場合、編集対象のパターン情報をフォームに入力
    if (widget.mode == ShiftPatternMode.edit &&
        widget.editingPattern != null) {
      _patternNameController.text = widget.editingPattern!.patternName;
      if (widget.editingPattern!.startTime != null) {
        _startTime = widget.editingPattern!.startTime!;
      }
      if (widget.editingPattern!.endTime != null) {
        _endTime = widget.editingPattern!.endTime!;
      }
    }
  }

  @override
  void dispose() {
    _patternNameController.dispose();
    super.dispose();
  }

  /// シフト入力へ進むボタンが有効かチェック
  bool _canProceedToNextScreen() {
    // 新規登録済みパターンがある OR 既存パターンがある場合、進む
    return _patterns.isNotEmpty ||
        (widget.existingPatterns?.isNotEmpty ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.mode == ShiftPatternMode.edit;
    final appBarTitle =
        isEditMode ? 'シフト体系を編集' : 'シフト体系登録';

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context, 1),  // ========== Week 3 Day 6-1 修正: pop(1) に統一 ==========
        ),
        title: Text(
          appBarTitle,
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
              // タイトル & 説明
              // ========================
              Text(
                isEditMode
                    ? 'シフト体系の情報を更新してください'
                    : 'シフト体系を登録・管理してください',
                style: AppTextStyles.sectionTitleStyle.copyWith(
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingSmall),
              Text(
                '例：日勤、夜勤、準夜勤など（出勤パターンのみ登録）',
                style: AppTextStyles.bodyTextStyle.copyWith(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingLarge),

              // ========================
              // 登録済みシフト体系一覧
              // ========================
              if (_patterns.isNotEmpty) ...[
                Text(
                  '登録済みシフト体系',
                  style: AppTextStyles.bodyTextStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: AppDimensions.paddingSmall),
                ..._patterns.map((pattern) {
                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppDimensions.paddingSmall,
                    ),
                    child: _buildPatternChip(pattern),
                  );
                }).toList(),
                const SizedBox(height: AppDimensions.paddingLarge),
              ],

              // ========================
              // 登録・編集フォーム
              // ========================
              Container(
                padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: AppColors.borderDefault,
                    width: AppDimensions.borderWidthThin,
                  ),
                  borderRadius: BorderRadius.circular(
                    AppDimensions.borderRadiusMedium,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditMode ? 'シフト体系情報' : '新しいシフト体系を追加',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // シフト体系名入力
                    Text(
                      'シフト体系名',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    TextField(
                      controller: _patternNameController,
                      decoration: InputDecoration(
                        hintText: '例：日勤、夜勤、準夜勤',
                        hintStyle: AppTextStyles.bodyTextStyle.copyWith(
                          color: AppColors.textMuted,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusSmall,
                          ),
                          borderSide: const BorderSide(
                            color: AppColors.borderDefault,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusSmall,
                          ),
                          borderSide: const BorderSide(
                            color: AppColors.borderDefault,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusSmall,
                          ),
                          borderSide: BorderSide(
                            color: AppColors.primaryGradientStart,
                            width: 2.0,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.paddingSmall,
                          vertical: AppDimensions.paddingSmall,
                        ),
                      ),
                      style: AppTextStyles.bodyTextStyle,
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // ========== Week 3 Day 6-1 修正: シフト体系タイプ選択を削除 ==========
                    // ShiftType.work のみになるため、タイプ選択行は不要
                    // ====================================================================

                    // 出勤時刻選択
                    Text(
                      '出勤時刻',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    GestureDetector(
                      onTap: () => _selectStartTime(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.paddingSmall,
                          vertical: 10.0,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.borderDefault,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusSmall,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                              style: AppTextStyles.bodyTextStyle.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Icon(
                              Icons.access_time,
                              color: AppColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // 退勤時刻選択
                    Text(
                      '退勤時刻',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    GestureDetector(
                      onTap: () => _selectEndTime(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.paddingSmall,
                          vertical: 10.0,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.borderDefault,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusSmall,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
                              style: AppTextStyles.bodyTextStyle.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Icon(
                              Icons.access_time,
                              color: AppColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.paddingLarge),

                    // ========================
                    // ボタン
                    // ========================
                    if (isEditMode)
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  _updatePattern(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    AppColors.primaryGradientStart,
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
                                '更新',
                                style: AppTextStyles.bodyTextStyle.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(
                              width: AppDimensions.paddingSmall),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.pop(context, 1),  // ========== Week 3 Day 6-1 修正: pop(1) に統一 ==========
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: AppColors.borderDefault,
                                ),
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
                                'キャンセル',
                                style: AppTextStyles.bodyTextStyle.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _addPattern,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                AppColors.primaryGradientStart,
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
                            '登録/更新',  // ========== Week 3 Day 8 修正: 「追加」→「登録/更新」 ==========
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.paddingLarge),

              // ========================
              // シフト入力へ進むボタン
              // ========================
              if (!isEditMode)
                if (_canProceedToNextScreen())
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _proceedToNextScreen,
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
                        'シフト入力へ進む',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.borderDefault,
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
                        'シフト入力へ進む',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          color: AppColors.textMuted
                              .withOpacity(0.5),
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, 1),  // ========== Week 3 Day 6-1 修正: pop(1) に統一 ==========
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
                      '完了',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: AppDimensions.paddingLarge),
            ],
          ),
        ),
      ),
    );
  }

  /// シフト体系チップ（登録済み表示）
  Widget _buildPatternChip(ShiftPatternModel pattern) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingSmall,
        vertical: 8.0,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardBgGray,
        border: Border.all(
          color: AppColors.borderDefault,
        ),
        borderRadius: BorderRadius.circular(
          AppDimensions.borderRadiusSmall,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // パターン色を示す□
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: pattern.color,
                        border: Border.all(
                          color: pattern.color.withOpacity(0.5),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      pattern.patternName,
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2.0),
                Text(
                  '${pattern.startTime!.hour.toString().padLeft(2, '0')}:${pattern.startTime!.minute.toString().padLeft(2, '0')} ～ ${pattern.endTime!.hour.toString().padLeft(2, '0')}:${pattern.endTime!.minute.toString().padLeft(2, '0')}',
                  style: AppTextStyles.bodyTextStyle.copyWith(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                )
              ],
            ),
          ),
          // ========== Week 3 Day 8 修正: DB 削除を追加 ==========
          IconButton(
            icon: Icon(
              Icons.close,
              color: AppColors.textMuted,
              size: 20,
            ),
            onPressed: () async {
              // DB から削除
              await _shiftRepository.deletePattern(pattern.id);
              
              setState(() {
                _patterns.removeWhere((p) => p.id == pattern.id);
              });
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('「${pattern.patternName}」を削除しました'),
                  backgroundColor: AppColors.warningRed,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          // ========================================================================
        ],
      ),
    );
  }

  /// 出勤時刻選択
  Future<void> _selectStartTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primaryGradientStart,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
      });
    }
  }

  /// 退勤時刻選択
  Future<void> _selectEndTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primaryGradientStart,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _endTime = picked;
      });
    }
  }

  void _addPattern() async {
    if (_patternNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('シフト体系名を入力してください'),
          backgroundColor: AppColors.warningRed,
        ),
      );
      return;
    }

    // ========== Fix：DB から全パターンをロードして colorIndex を割り当て ==========
    final dbPatterns = await _shiftRepository.getAllPatterns();
  
    // DB に保存されているパターンから、最大の colorIndex を探す
    int maxColorIndex = -1;
    for (final pattern in dbPatterns) {
      if (pattern.colorIndex > maxColorIndex) {
        maxColorIndex = pattern.colorIndex;
      }
    }
  
    // 次の colorIndex を計算（0～5 をループ）
    int nextColorIndex = (maxColorIndex + 1) % 6;
    // ===========================================================================

    final newPattern = ShiftPatternModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      patternName: _patternNameController.text.trim(),
      patternType: ShiftType.work,
      startTime: _startTime,
      endTime: _endTime,
      colorIndex: nextColorIndex,  // ← DB ベースの colorIndex
    );

    // DB に保存
    await _shiftRepository.createPattern(newPattern);

    setState(() {
      _patterns.add(newPattern);
      _patternNameController.clear();
      _startTime = const TimeOfDay(hour: 8, minute: 30);
      _endTime = const TimeOfDay(hour: 17, minute: 0);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('「${newPattern.patternName}」を追加しました'),
        backgroundColor: AppColors.primaryGradientStart,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// シフト体系を更新
  void _updatePattern() {
    if (_patternNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('シフト体系名を入力してください'),
          backgroundColor: AppColors.warningRed,
        ),
      );
      return;
    }

    // 既存パターンを更新
    final index = _patterns.indexWhere(
      (p) => p.id == widget.editingPattern!.id,
    );

    if (index != -1) {
      final originalColorIndex = _patterns[index].colorIndex;
      _patterns[index] = ShiftPatternModel(
        id: widget.editingPattern!.id,
        patternName: _patternNameController.text.trim(),
        patternType: ShiftType.work,  // work のみ
        startTime: _startTime,
        endTime: _endTime,
        colorIndex: originalColorIndex,
      );

      // コールバック実行
      if (widget.onPatternsChanged != null) {
        widget.onPatternsChanged!(_patterns);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('「${_patternNameController.text.trim()}」を更新しました'),
          backgroundColor: AppColors.primaryGradientStart,
          duration: const Duration(seconds: 2),
        ),
      );

      Navigator.pop(context);
    }
  }

  void _proceedToNextScreen() async {
    // ========== Fix：DB から最新のパターンをロードして返す ==========
    final latestPatterns = await _shiftRepository.getAllPatterns();
    Navigator.pop(context, latestPatterns);
    // ==============================================================
  }
}