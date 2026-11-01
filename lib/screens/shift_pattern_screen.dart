import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/screens/shift_management_screen.dart';
import 'package:shiftsleep/services/pattern_usage.dart';


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
  bool _isAdding = false;  // N115：追加の処理中（二度押しで 2 件入らないように）

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
                          onPressed: _isAdding ? null : _addPattern,  // N115：処理中は押せない
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
            onPressed: () => _deletePattern(pattern),
          ),
          // ========================================================================
        ],
      ),
    );
  }

  /// N104：✕ で削除する。今日以降で使われていれば止め、それ以外は確認してから消す
  Future<void> _deletePattern(ShiftPatternModel pattern) async {
    final name = pattern.patternName;

    final ({int futureCount, String? firstFutureDate, int pastCount}) usage;
    try {
      final dates = await _shiftRepository.getShiftDatesByPatternId(pattern.id);
      usage = classifyPatternUsage(dates, DateTime.now());
    } catch (e) {
      _showDeleteResult('❌ 削除に失敗しました: $e', isError: true);
      return;
    }
    if (!mounted) return;

    // 今日以降で使われている：消さずに止める（出勤前アラームに関わるため）
    if (usage.futureCount >= 1) {
      final parts = usage.firstFutureDate!.split('-');
      final firstDay = '${int.parse(parts[1])}/${int.parse(parts[2])}';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(
            '⚠️ 『$name』は今日以降の ${usage.futureCount} 日（最初は $firstDay）で使われています。'
            '先にカレンダーで別のパターンに変えてから削除してください。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final message = usage.pastCount >= 1
        ? '『$name』を削除しますか？\n過去の ${usage.pastCount} 日で使われています。カレンダーでは「削除済み」として表示されます。'
        : '『$name』を削除しますか？';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('削除', style: TextStyle(color: AppColors.warningRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _shiftRepository.deletePattern(pattern.id);
    } catch (e) {
      _showDeleteResult('❌ 削除に失敗しました: $e', isError: true);
      return;
    }
    if (!mounted) return;

    setState(() {
      _patterns.removeWhere((p) => p.id == pattern.id);
    });
    _showDeleteResult('✅ 『$name』を削除しました', isError: false);
  }

  /// N104：削除の結果を SnackBar で出す（前の SnackBar は消す）
  void _showDeleteResult(String message, {required bool isError}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.warningRed : AppColors.primaryGradientStart,
        duration: Duration(seconds: isError ? 4 : 2),
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

  /// N115：DB に入れられたときだけ一覧に加える。失敗したら入力欄はそのまま残して知らせる
  Future<void> _addPattern() async {
    if (_isAdding) return;
    if (_patternNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('シフト体系名を入力してください'),
          backgroundColor: AppColors.warningRed,
        ),
      );
      return;
    }

    setState(() => _isAdding = true);
    try {
      await _insertNewPattern();
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  /// N115・N118：失敗したときの SnackBar（前の SnackBar は消す。赤・4 秒）
  void _showPatternError(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.warningRed,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// N115：新しいパターンを DB に入れ、結果を一覧と SnackBar に出す
  Future<void> _insertNewPattern() async {
    // ========== Week 8 Phase 6 修正: colorIndex=0 を避ける ==========
    // N118：色を決めるためのパターンが読めなければ、追加をやめる（入力欄はそのまま）
    final List<ShiftPatternModel> dbPatterns;
    try {
      dbPatterns = await _shiftRepository.getAllPatterns();
    } catch (e) {
      debugPrint('Error loading patterns for color: $e');
      if (!mounted) return;
      _showPatternError('❌ パターンの追加に失敗しました: $e');
      return;
    }

    int maxColorIndex = -1;
    for (final pattern in dbPatterns) {
      if (pattern.colorIndex > maxColorIndex) {
        maxColorIndex = pattern.colorIndex;
      }
    }

    // 次の colorIndex を計算（1～5 をループ）
    // 0 番の色は休日と同じなので避ける（N103 で削除処理はなくした）
    int nextColorIndex = (maxColorIndex + 1) % 6;
    if (nextColorIndex == 0) {
      nextColorIndex = 1;  // 0 は避けて 1 にする
    }
    // ================================================================

    final newPattern = ShiftPatternModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      patternName: _patternNameController.text.trim(),
      patternType: ShiftType.work,
      startTime: _startTime,
      endTime: _endTime,
      colorIndex: nextColorIndex,
    );

    try {
      await _shiftRepository.createPattern(newPattern);
    } catch (e) {
      // 一覧には加えず、入力欄もそのまま（入れ直さずにもう一度押せるように）
      if (!mounted) return;
      _showPatternError('❌ パターンの追加に失敗しました: $e');
      return;
    }
    if (!mounted) return;

    setState(() {
      _patterns.add(newPattern);
      _patternNameController.clear();
      _startTime = const TimeOfDay(hour: 8, minute: 30);
      _endTime = const TimeOfDay(hour: 17, minute: 0);
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('✅ 『${newPattern.patternName}』を追加しました'),
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
    // N118：読めなかったら画面に残る（ホームの _patterns を [] で上書きしない）
    final List<ShiftPatternModel> latestPatterns;
    try {
      latestPatterns = await _shiftRepository.getAllPatterns();
    } catch (e) {
      debugPrint('Error loading patterns: $e');
      if (!mounted) return;
      _showPatternError('❌ パターンの読み込みに失敗しました: $e');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, latestPatterns);
    // ==============================================================
  }
}