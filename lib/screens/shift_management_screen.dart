import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'shift_pattern_screen.dart';
import 'shift_detail_screen.dart';

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

  const ShiftManagementScreen({
    Key? key,
    required this.patterns,
  }) : super(key: key);

  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends State<ShiftManagementScreen> {
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
    );
  }

  @override
  Widget build(BuildContext context) {
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
          'シフト入力',
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
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ShiftDetailScreen(
                                shiftDataMap: _shiftMap,
                                patterns: widget.patterns,
                              ),
                            ),
                          );
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
      ),
    );
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

  /// パターン選択ボタン（修正版：複数選択可能）
  Widget _buildPatternButton(ShiftPatternModel pattern) {
    final isSelected = _selectedPattern?.id == pattern.id;
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
                ? AppColors.primaryGradientStart.withOpacity(0.15)
                : AppColors.cardBgGray,
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
            pattern.patternName,
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? AppColors.primaryGradientStart
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// 方式①：カレンダータップ入力（修正版：登録済みシフトを表示）
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
              // 登録済みシフトをイベントとして返す
              final normalized = DateTime(day.year, day.month, day.day);
              return _shiftMap.containsKey(normalized)
                  ? [_shiftMap[normalized]!.pattern?.patternName ?? '']
                  : [];
            },
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;

                // パターンが選択されていたら登録
                if (_selectedPattern != null) {
                  final normalized =
                      DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
                  _shiftMap[normalized] = ShiftData(
                    date: normalized,
                    pattern: _selectedPattern,
                  );

                  // フィードバック表示
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

        // 登録済みシフト一覧
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
                  return Padding(
                    padding: const EdgeInsets.only(
                      top: 4.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${entry.key.month}/${entry.key.day}: ${entry.value.pattern?.patternName ?? ''}',
                          style: AppTextStyles.bodyTextStyle.copyWith(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
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
                ? AppColors.primaryGradientStart.withOpacity(0.1)
                : AppColors.cardBgGray,
            borderRadius:
                BorderRadius.circular(AppDimensions.borderRadiusSmall),
          ),
          child: Text(
            _selectedPattern?.patternName ?? 'パターンを選択してください',
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _selectedPattern != null
                  ? AppColors.primaryGradientStart
                  : AppColors.textMuted,
            ),
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
}