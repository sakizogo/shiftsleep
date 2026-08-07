import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';

class ShiftData {
  final DateTime date;
  final ShiftPatternModel? pattern;
  final TimeOfDay? customStartTime;
  final TimeOfDay? customEndTime;

  ShiftData({
    required this.date,
    this.pattern,
    this.customStartTime,
    this.customEndTime,
  });
}

class ShiftManagementScreen extends StatefulWidget {
  final List<ShiftPatternModel> patterns;
  
  // ========== Week 3 Day 5 追加: 詳細画面へ遷移するコールバック ==========
  final Function(Map<DateTime, ShiftData>, List<ShiftPatternModel>)? onNavigateToDetails;
  // ================================================================

  const ShiftManagementScreen({
    Key? key,
    required this.patterns,
    this.onNavigateToDetails,
  }) : super(key: key);

  @override
  State<ShiftManagementScreen> createState() => ShiftManagementScreenState();
}

class ShiftManagementScreenState extends State<ShiftManagementScreen> {
  final ShiftRepository _shiftRepository = ShiftRepository();  // ========== Week 3 Day 6-2 追加 ==========
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  final Map<DateTime, ShiftData> _shiftMap = {};
  int _selectedInputMethod = 0;
  ShiftPatternModel? _selectedPattern;
  DateTime? _rangeStartDate;
  DateTime? _rangeEndDate;

  // デフォルト休日パターン
  late ShiftPatternModel _defaultDayOffPattern;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedDay = DateTime(now.year, now.month, 1);
    _selectedDay = now;

    // デフォルト休日パターンを作成
    _defaultDayOffPattern = ShiftPatternModel(
      id: 'default_dayoff',
      patternName: '休日',
      patternType: ShiftType.dayOff,
      startTime: null,
      endTime: null,
      colorIndex: 0,
    );
    // DB からシフトデータを読み込む
    loadShifts();  // ========== Week 3 Day 6-2 修正: public メソッドに変更 ==========
  }

  @override
  Widget build(BuildContext context) {
    // ========== Week 3 Day 5 修正: Scaffold を削除し、コンテンツのみを返す ==========
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppDimensions.sectionPaddingVertical,
          horizontal: AppDimensions.sectionPaddingHorizontal,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========================
            // 入力方式タブ
            // ========================
            _buildInputMethodTabs(),
            const SizedBox(height: AppDimensions.paddingLarge),

            // ========================
            // パターンクイック選択（追加：デフォルト休日を含む）
            // ========================
            Text(
              'パターンを選択',
              style: AppTextStyles.bodyTextStyle.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: AppDimensions.paddingSmall),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // デフォルト休日パターン
                  Padding(
                    padding: const EdgeInsets.only(
                      right: AppDimensions.paddingSmall,
                    ),
                    child: _buildPatternButton(_defaultDayOffPattern),
                  ),
                  // ユーザーが登録したパターン
                  ...widget.patterns.map((pattern) {
                    return Padding(
                      padding: const EdgeInsets.only(
                        right: AppDimensions.paddingSmall,
                      ),
                      child: _buildPatternButton(pattern),
                    );
                  }).toList(),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.paddingLarge),

            // ========================
            // 入力方式別コンテンツ
            // ========================
            if (_selectedInputMethod == 0)
              _buildCalendarInputMethod()
            else if (_selectedInputMethod == 1)
              _buildRangeInputMethod()
            else
              _buildManualInputMethod(),

            const SizedBox(height: AppDimensions.paddingXLarge),

            // ========================
            // 完了ボタン
            // ========================
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _shiftMap.isNotEmpty
                    ? () {
                        // ========== Week 3 Day 5 修正: Navigator.push を削除、コールバック導入 ==========
                        if (widget.onNavigateToDetails != null) {
                          widget.onNavigateToDetails!(_shiftMap, widget.patterns);
                        }
                        // ================================================================
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _shiftMap.isNotEmpty
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
                  'シフト入力完了',
                  style: AppTextStyles.bodyTextStyle.copyWith(
                    color: _shiftMap.isNotEmpty
                        ? Colors.white
                        : AppColors.textMuted,
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
    );
    // ================================================================
  }

  /// 入力方式タブ
  Widget _buildInputMethodTabs() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              label: 'カレンダー',
              index: 0,
              isSelected: _selectedInputMethod == 0,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: AppColors.borderDefault,
          ),
          Expanded(
            child: _buildTabButton(
              label: '期間指定',
              index: 1,
              isSelected: _selectedInputMethod == 1,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: AppColors.borderDefault,
          ),
          Expanded(
            child: _buildTabButton(
              label: '手入力',
              index: 2,
              isSelected: _selectedInputMethod == 2,
            ),
          ),
        ],
      ),
    );
  }

  /// タブボタン
  Widget _buildTabButton({
    required String label,
    required int index,
    required bool isSelected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedInputMethod = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          color: isSelected
              ? AppColors.primaryGradientStart.withOpacity(0.1)
              : Colors.transparent,
          child: Text(
            label,
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 12,
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

  /// パターン選択ボタン（色分け版）
  Widget _buildPatternButton(ShiftPatternModel pattern) {
    final isSelected = _selectedPattern?.id == pattern.id;
    
    final textColor = _isLightColor(pattern.color) ? Colors.black87 : Colors.white;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedPattern = isSelected ? null : pattern;
          });
        },
        borderRadius:
            BorderRadius.circular(AppDimensions.borderRadiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingSmall,
            vertical: 6.0,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? pattern.color.withOpacity(0.2)
                : pattern.color.withOpacity(0.1),
            border: Border.all(
              color: isSelected ? pattern.color : pattern.color.withOpacity(0.5),
              width: isSelected ? 2.0 : 1.0,
            ),
            borderRadius: BorderRadius.circular(
              AppDimensions.borderRadiusSmall,
            ),
          ),
          child: Text(
            pattern.patternName,
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? pattern.color : pattern.color.withOpacity(0.7),
            ),
          ),
        ),
      ),
    );
  }

  /// 色が明るいか暗いかを判定（テキスト色決定用）
  bool _isLightColor(Color color) {
    return (color.red * 0.299 + color.green * 0.587 + color.blue * 0.114) > 128;
  }

  /// 方式①：カレンダータップ入力
  Widget _buildCalendarInputMethod() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'パターンを選択してから日付をタップ',
          style: AppTextStyles.bodyTextStyle.copyWith(
            fontSize: 13,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppDimensions.paddingMedium),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.borderDefault),
            borderRadius:
                BorderRadius.circular(AppDimensions.borderRadiusMedium),
          ),
          child: TableCalendar(
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2026, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) {
              return isSameDay(_selectedDay, day);
            },
            eventLoader: (day) {
              final normalized = DateTime(day.year, day.month, day.day);
              return _shiftMap.containsKey(normalized)
                  ? [_shiftMap[normalized]!.pattern?.patternName ?? '']
                  : [];
            },
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;

                final normalized = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);

                if (_shiftMap.containsKey(normalized)) {
                  _shiftMap.remove(normalized);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${selectedDay.month}/${selectedDay.day}の登録を削除しました'),
                      backgroundColor: AppColors.warningRed,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                } else if (_selectedPattern != null) {
                  _shiftMap[normalized] = ShiftData(
                    date: normalized,
                    pattern: _selectedPattern,
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${selectedDay.month}/${selectedDay.day}に「${_selectedPattern!.patternName}」を設定しました',
                      ),
                      backgroundColor: AppColors.primaryGradientStart,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('パターンを選択してください'),
                      backgroundColor: AppColors.warningRed,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarStyle: CalendarStyle(
              defaultDecoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius:
                    BorderRadius.circular(AppDimensions.borderRadiusSmall),
              ),
              weekendDecoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius:
                    BorderRadius.circular(AppDimensions.borderRadiusSmall),
              ),
              selectedDecoration: BoxDecoration(
                color: AppColors.primaryGradientStart,
                shape: BoxShape.rectangle,
                borderRadius:
                    BorderRadius.circular(AppDimensions.borderRadiusSmall),
              ),
              todayDecoration: BoxDecoration(
                color: AppColors.primaryGradientStart.withOpacity(0.3),
                shape: BoxShape.rectangle,
                borderRadius:
                    BorderRadius.circular(AppDimensions.borderRadiusSmall),
              ),
              outsideDecoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius:
                    BorderRadius.circular(AppDimensions.borderRadiusSmall),
              ),
              markerDecoration: BoxDecoration(
                color: AppColors.starYellow,
                shape: BoxShape.circle,
              ),
              defaultTextStyle: AppTextStyles.bodyTextStyle.copyWith(
                fontSize: 14,
              ),
              weekendTextStyle: AppTextStyles.bodyTextStyle.copyWith(
                fontSize: 14,
              ),
              selectedTextStyle: AppTextStyles.bodyTextStyle.copyWith(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, date, focusedDay) {
                final normalized = DateTime(date.year, date.month, date.day);
                if (_shiftMap.containsKey(normalized)) {
                  final pattern = _shiftMap[normalized]?.pattern;
                  final patternColor = pattern?.color ?? Colors.grey;
                  final patternName = pattern?.patternName ?? '';
                  
                  // パターン名を短縮（2文字目まで）
                  final shortName = patternName.length > 2 
                    ? patternName.substring(0, 2) 
                    : patternName;
                  
                  // テキスト色：休日は赤、その他は黒
                  final textColor = pattern?.patternType == ShiftType.dayOff 
                    ? Colors.red 
                    : Colors.black87;
                  
                  return Container(
                    decoration: BoxDecoration(
                      color: patternColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          shortName,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return null;
              },
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: AppTextStyles.bodyTextStyle.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              leftChevronIcon: Icon(
                Icons.chevron_left,
                color: AppColors.primaryGradientStart,
                size: 24,
              ),
              rightChevronIcon: Icon(
                Icons.chevron_right,
                color: AppColors.primaryGradientStart,
                size: 24,
              ),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: AppTextStyles.bodyTextStyle.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              weekendStyle: AppTextStyles.bodyTextStyle.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppDimensions.paddingMedium),

        if (_shiftMap.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(AppDimensions.paddingSmall),
            decoration: BoxDecoration(
              color: AppColors.cardBgGray,
              borderRadius:
                  BorderRadius.circular(AppDimensions.borderRadiusSmall),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '登録済みシフト（${_shiftMap.length}日）',
                  style: AppTextStyles.bodyTextStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6.0),
                ..._shiftMap.entries.map((entry) {
                  final patternColor = entry.value.pattern?.color ?? Colors.grey;
                  return Padding(
                    padding: const EdgeInsets.only(
                      top: 4.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: patternColor,
                                border: Border.all(
                                  color: patternColor.withOpacity(0.5),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            Text(
                              '${entry.key.month}/${entry.key.day}: ${entry.value.pattern?.patternName ?? ''}',
                              style: AppTextStyles.bodyTextStyle.copyWith(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _shiftMap.remove(entry.key);
                            });
                          },
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: AppColors.warningRed,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
      ],
    );
  }

  /// 方式②：期間指定入力
  Widget _buildRangeInputMethod() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '開始日と終了日を指定',
          style: AppTextStyles.bodyTextStyle.copyWith(
            fontSize: 13,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppDimensions.paddingMedium),
        Row(
          children: [
            Expanded(
              child: _buildDateField(
                label: '開始日',
                date: _rangeStartDate,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _rangeStartDate ?? DateTime.now(),
                    firstDate: DateTime.utc(2024, 1, 1),
                    lastDate: DateTime.utc(2026, 12, 31),
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
                      _rangeStartDate = picked;
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: AppDimensions.paddingSmall),
            Expanded(
              child: _buildDateField(
                label: '終了日',
                date: _rangeEndDate,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _rangeEndDate ?? DateTime.now(),
                    firstDate: DateTime.utc(2024, 1, 1),
                    lastDate: DateTime.utc(2026, 12, 31),
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
                      _rangeEndDate = picked;
                    });
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.paddingMedium),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _rangeStartDate != null &&
                    _rangeEndDate != null &&
                    _selectedPattern != null
                ? _applyRangeShift
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _rangeStartDate != null &&
                      _rangeEndDate != null &&
                      _selectedPattern != null
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
              '期間に適用',
              style: AppTextStyles.bodyTextStyle.copyWith(
                color: _rangeStartDate != null &&
                        _rangeEndDate != null &&
                        _selectedPattern != null
                    ? Colors.white
                    : AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
        if (_shiftMap.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppDimensions.paddingMedium),
            child: Container(
              padding: const EdgeInsets.all(AppDimensions.paddingSmall),
              decoration: BoxDecoration(
                color: AppColors.cardBgWarning,
                borderRadius:
                    BorderRadius.circular(AppDimensions.borderRadiusSmall),
              ),
              child: Text(
                '設定済み：${_shiftMap.length}日',
                style: AppTextStyles.bodyTextStyle.copyWith(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 方式③：手入力
  Widget _buildManualInputMethod() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'パターンと時刻を手入力',
          style: AppTextStyles.bodyTextStyle.copyWith(
            fontSize: 13,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppDimensions.paddingMedium),
        Text(
          '選択されたパターン：',
          style: AppTextStyles.bodyTextStyle.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6.0),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingSmall,
            vertical: 10.0,
          ),
          decoration: BoxDecoration(
            color: _selectedPattern != null
                ? _selectedPattern!.color.withOpacity(0.1)
                : AppColors.cardBgGray,
            borderRadius:
                BorderRadius.circular(AppDimensions.borderRadiusSmall),
          ),
          child: Row(
            children: [
              if (_selectedPattern != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _selectedPattern!.color,
                      border: Border.all(
                        color: _selectedPattern!.color.withOpacity(0.5),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  _selectedPattern?.patternName ?? 'パターンを選択してください',
                  style: AppTextStyles.bodyTextStyle.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _selectedPattern != null
                        ? _selectedPattern!.color
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 日付フィールド
  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyTextStyle.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6.0),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingSmall,
              vertical: 10.0,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderDefault),
              borderRadius:
                  BorderRadius.circular(AppDimensions.borderRadiusSmall),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  date != null
                      ? '${date.month}/${date.day}'
                      : 'タップで選択',
                  style: AppTextStyles.bodyTextStyle.copyWith(
                    fontSize: 14,
                    color: date != null
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                  ),
                ),
                Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: AppColors.primaryGradientStart,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 期間のシフトを適用
  void _applyRangeShift() {
    if (_rangeStartDate == null ||
        _rangeEndDate == null ||
        _selectedPattern == null) {
      return;
    }

    DateTime current = _rangeStartDate!;
    while (!current.isAfter(_rangeEndDate!)) {
      final normalized = DateTime(current.year, current.month, current.day);
      _shiftMap[normalized] = ShiftData(
        date: normalized,
        pattern: _selectedPattern,
      );
      current = current.add(const Duration(days: 1));
    }

    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_rangeEndDate!.difference(_rangeStartDate!).inDays + 1}日間のシフトを設定しました',
        ),
        backgroundColor: AppColors.primaryGradientStart,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  // ========== Week 3 Day 6-2 修正: public メソッドに変更、タブ切り替え時に呼び出し可能 ==========
  /// DB からシフトデータをロード（public メソッド）
  Future<void> loadShifts() async {
    try {
      print('🔄 loadShifts() 開始');
      final now = DateTime.now();
      // 前月・当月・来月の3ヶ月分を読み込む
      final startDate = DateTime(now.year, now.month - 1, 1);
      final endDate = DateTime(now.year, now.month + 2, 0);
      
      print('📅 読み込み範囲: ${startDate.toIso8601String()} ～ ${endDate.toIso8601String()}');
      
      final shiftRecords = await _shiftRepository.getShiftsForDateRange(startDate, endDate);
      
      print('📝 取得したシフト数: ${shiftRecords.length}');
      
      setState(() {
        _shiftMap.clear();
        
        for (final record in shiftRecords) {
          final dateStr = record['shift_date'] as String;
          final patternId = record['pattern_id'] as String?;
          
          final date = DateTime.parse(dateStr);
          final normalized = DateTime(date.year, date.month, date.day);
          
          // patternId で正確にパターンを検索
          ShiftPatternModel? matchingPattern;
          if (patternId != null) {
            matchingPattern = widget.patterns.firstWhere(
              (p) => p.id == patternId,
              orElse: () => _defaultDayOffPattern,
            );
          } else {
            matchingPattern = _defaultDayOffPattern;
          }
          
          _shiftMap[normalized] = ShiftData(
            date: normalized,
            pattern: matchingPattern,
          );
          
          print('✅ シフト読込: ${normalized.toIso8601String()} → ${matchingPattern.patternName}');
        }
      });
      
      print('✨ loadShifts() 完了 - 合計: ${_shiftMap.length}日');
    } catch (e) {
      print('❌ Error loading shifts from DB: $e');
    }
  }
  
  // ========== Week 3 Day 6-2 追加: 入力データをリセット（戻る時に呼び出し） ==========
  /// シフト入力フォームをリセット
  void clearShiftMap() {
    print('🔄 clearShiftMap() - 入力データをリセット');
    setState(() {
      _shiftMap.clear();
      _selectedPattern = null;
      _rangeStartDate = null;
      _rangeEndDate = null;
      _selectedInputMethod = 0;
      final now = DateTime.now();
      _focusedDay = DateTime(now.year, now.month, 1);
      _selectedDay = now;
    });
    print('✨ clearShiftMap() 完了');
  }
  // ========================================================================
}