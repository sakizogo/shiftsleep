import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
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
  ShiftType _selectedType = ShiftType.work;
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 30);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  late List<ShiftPatternModel> _patterns;

  @override
  void initState() {
    super.initState();
    _patterns = List.from(widget.existingPatterns ?? []);

    // 編集モードの場合、編集対象のパターン情報をフォームに入力
    if (widget.mode == ShiftPatternMode.edit &&
        widget.editingPattern != null) {
      _patternNameController.text = widget.editingPattern!.patternName;
      _selectedType = widget.editingPattern!.patternType;
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
          onPressed: () => Navigator.pop(context),
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
                    : 'シフト体系を登録してください',
                style: AppTextStyles.sectionTitleStyle.copyWith(
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingSmall),
              Text(
                isEditMode
                    ? '例：日勤、夜勤、準夜勤、休日など'
                    : '例：日勤、夜勤、準夜勤、休日など',
                style: AppTextStyles.bodyTextStyle.copyWith(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingLarge),

              // ========================
              // 登録済みシフト体系一覧（新規登録時のみ）
              // ========================
              if (!isEditMode && _patterns.isNotEmpty) ...[
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

                    // シフト体系タイプ選択
                    Text(
                      'シフト体系タイプ',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTypeButton(
                            type: ShiftType.work,
                            isSelected: _selectedType == ShiftType.work,
                            onTap: () {
                              setState(() {
                                _selectedType = ShiftType.work;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: AppDimensions.paddingSmall),
                        Expanded(
                          child: _buildTypeButton(
                            type: ShiftType.dayOff,
                            isSelected: _selectedType == ShiftType.dayOff,
                            onTap: () {
                              setState(() {
                                _selectedType = ShiftType.dayOff;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // 出勤パターンの場合：時刻入力
                    if (_selectedType == ShiftType.work) ...[
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
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Icon(
                                Icons.access_time,
                                color: AppColors.primaryGradientStart,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDimensions.paddingMedium),

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
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Icon(
                                Icons.access_time,
                                color: AppColors.primaryGradientStart,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDimensions.paddingMedium),
                    ],

                    // ボタン（新規登録 vs 更新）
                    if (!isEditMode)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _patternNameController.text.trim().isNotEmpty
                                  ? _addPattern
                                  : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _patternNameController.text
                                    .trim()
                                    .isNotEmpty
                                ? AppColors.primaryGradientStart
                                : AppColors.borderDefault,
                            padding: EdgeInsets.symmetric(
                              vertical: AppDimensions.paddingSmall,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDimensions.borderRadiusSmall,
                              ),
                            ),
                          ),
                          child: Text(
                            '+ シフト体系を登録',
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              color: _patternNameController.text
                                      .trim()
                                      .isNotEmpty
                                  ? Colors.white
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _patternNameController.text.trim().isNotEmpty
                                  ? _updatePattern
                                  : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _patternNameController.text
                                    .trim()
                                    .isNotEmpty
                                ? AppColors.primaryGradientStart
                                : AppColors.borderDefault,
                            padding: EdgeInsets.symmetric(
                              vertical: AppDimensions.paddingSmall,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDimensions.borderRadiusSmall,
                              ),
                            ),
                          ),
                          child: Text(
                            'シフト体系を更新',
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              color: _patternNameController.text
                                      .trim()
                                      .isNotEmpty
                                  ? Colors.white
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.paddingXLarge),

              // ========================
              // 次へボタン（新規登録時のみ）
              // ========================
              if (!isEditMode)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canProceedToNextScreen() ? _proceedToNextScreen : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _canProceedToNextScreen()
                          ? AppColors.primaryGradientStart
                          : AppColors.borderDefault,
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
                        color: _canProceedToNextScreen()
                            ? Colors.white
                            : AppColors.textMuted,
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
                    onPressed: () => Navigator.pop(context),
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

  /// シフト体系タイプボタン
  Widget _buildTypeButton({
    required ShiftType type,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 10.0,
            horizontal: AppDimensions.paddingSmall,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryGradientStart.withOpacity(0.1)
                : Colors.white,
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryGradientStart
                  : AppColors.borderDefault,
              width: isSelected ? 2.0 : 1.0,
            ),
            borderRadius: BorderRadius.circular(
              AppDimensions.borderRadiusSmall,
            ),
          ),
          child: Text(
            type.displayName,
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: isSelected
                  ? AppColors.primaryGradientStart
                  : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
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
                if (pattern.patternType == ShiftType.work)
                  Text(
                    '${pattern.startTime!.hour.toString().padLeft(2, '0')}:${pattern.startTime!.minute.toString().padLeft(2, '0')} ～ ${pattern.endTime!.hour.toString().padLeft(2, '0')}:${pattern.endTime!.minute.toString().padLeft(2, '0')}',
                    style: AppTextStyles.bodyTextStyle.copyWith(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  )
                else
                  Text(
                    '休日',
                    style: AppTextStyles.bodyTextStyle.copyWith(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              color: AppColors.textMuted,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _patterns.removeWhere((p) => p.id == pattern.id);
              });
            },
          ),
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

  /// シフト体系を追加
  void _addPattern() {
    if (_patternNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('シフト体系名を入力してください'),
          backgroundColor: AppColors.warningRed,
        ),
      );
      return;
    }

    final newPattern = ShiftPatternModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      patternName: _patternNameController.text.trim(),
      patternType: _selectedType,
      startTime: _selectedType == ShiftType.work ? _startTime : null,
      endTime: _selectedType == ShiftType.work ? _endTime : null,
      colorIndex: _patterns.length,  // ← 新規追加：既存パターン数をインデックスとする
    );

    setState(() {
      _patterns.add(newPattern);
      _patternNameController.clear();
      _selectedType = ShiftType.work;
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
      final originalColorIndex = _patterns[index].colorIndex;  // ← 元の色インデックスを保持
      _patterns[index] = ShiftPatternModel(
        id: widget.editingPattern!.id,
        patternName: _patternNameController.text.trim(),
        patternType: _selectedType,
        startTime: _selectedType == ShiftType.work ? _startTime : null,
        endTime: _selectedType == ShiftType.work ? _endTime : null,
        colorIndex: originalColorIndex,  // ← 色は変わらない
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

  /// 次画面へ遷移
  void _proceedToNextScreen() {
    // ShiftManagementScreen に直接遷移
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShiftManagementScreen(
          patterns: _patterns,
        ),
      ),
    );
  }
}