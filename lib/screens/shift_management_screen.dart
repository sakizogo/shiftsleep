import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/event_type.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/models/calendar_event.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';
import 'package:shiftsleep/screens/calendar_event_screen.dart';
import 'package:shiftsleep/widgets/vacation_stats_widget.dart';

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
  final Function(Map<DateTime, ShiftData>, List<ShiftPatternModel>)? onNavigateToDetails;

  const ShiftManagementScreen({
    Key? key,
    required this.patterns,
    this.onNavigateToDetails,
  }) : super(key: key);

  @override
  State<ShiftManagementScreen> createState() => ShiftManagementScreenState();
}

class ShiftManagementScreenState extends State<ShiftManagementScreen> {
  final ShiftRepository _shiftRepository = ShiftRepository();
  final VacationRepository _vacationRepository = VacationRepository();
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  final Map<DateTime, ShiftData> _shiftMap = {};
  late Map<DateTime, double> _vacationMap;
  final List<CalendarEvent> _calendarEvents = [];
  int _selectedInputMethod = 0;
  ShiftPatternModel? _selectedPattern;
  DateTime? _rangeStartDate;
  DateTime? _rangeEndDate;
  late ShiftPatternModel _defaultDayOffPattern;
  late ShiftPatternModel _defaultVacation1Day;
  late ShiftPatternModel _defaultVacationHalf;
  late List<ShiftPatternModel> _patterns;
  
  @override
  void initState() {
    super.initState();
    _vacationMap = {};
    final now = DateTime.now();
    _focusedDay = DateTime(now.year, now.month, 1);
    _selectedDay = now;
    _defaultDayOffPattern = ShiftPatternModel(
      id: 'default_dayoff',
      patternName: '休日',
      patternType: ShiftType.dayOff,
      startTime: null,
      endTime: null,
      colorIndex: 0,
    );
    
    _defaultVacation1Day = ShiftPatternModel(
      id: 'default_vacation_1day',
      patternName: '有休',
      patternType: ShiftType.vacation,
      startTime: null,
      endTime: null,
      colorIndex: 3,
    );
    _defaultVacationHalf = ShiftPatternModel(
      id: 'default_vacation_half',
      patternName: '半休',
      patternType: ShiftType.halfVacation,
      startTime: null,
      endTime: null,
      colorIndex: 4,
    );
    
    _patterns = [
      _defaultDayOffPattern,
      _defaultVacation1Day,
      _defaultVacationHalf,
    ];
    
    _initializeAllData(); 
  }
  
  Future<void> _initializeAllData() async {
    try {
      await _loadPatterns();
      await loadShifts();
      await _loadVacationData();
      await loadCalendarEvents();
      
      print('[ShiftManagementScreen] ✅ 全ての初期化が完了');
    } catch (e) {
      print('[ShiftManagementScreen] ⚠️  初期化エラー: $e');
    }
  }
  
  Future<void> _loadVacationData() async {
    try {
      final now = DateTime.now();
      final startOfYear = DateTime(now.year, 1, 1);
      final endOfYear = DateTime(now.year, 12, 31);
      
      final vacationUsages = await _vacationRepository.getVacationUsageInRange(
        'test_user',
        startOfYear,
        endOfYear,
      );
      
      setState(() {
        _vacationMap.clear();
        for (final usage in vacationUsages) {
          final dateKey = DateTime(usage.usageDate.year, usage.usageDate.month, usage.usageDate.day);
          _vacationMap[dateKey] = usage.daysUsed;
        }
      });
      print('[ShiftManagementScreen] ✅ VacationMap loaded: ${_vacationMap.length} records');
    } catch (e) {
      print('[ShiftManagementScreen] ⚠️  Error loading vacation data: $e');
    }
  }

  Future<void> _loadPatterns() async {
    try {
      final dbPatterns = await _shiftRepository.getAllPatterns();
      setState(() {
        _patterns = [
          _defaultDayOffPattern,
          _defaultVacation1Day,
          _defaultVacationHalf,
        ];
        
        for (final dbPattern in dbPatterns) {
          if (dbPattern.id != 'default_dayoff' && 
              dbPattern.id != 'default_vacation_1day' && 
              dbPattern.id != 'default_vacation_half') {
            _patterns.add(dbPattern);
          }
        }
      });
      print('[ShiftManagementScreen] Loaded ${_patterns.length} patterns');
    } catch (e) {
      print('[ShiftManagementScreen] Error loading patterns: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppDimensions.sectionPaddingVertical,
          horizontal: AppDimensions.sectionPaddingHorizontal,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========== Week 27+ Step 2：上部の「+ イベント追加」ボタンを削除 ==========
            // （削除済み）
            // ===================================================
            
            const SizedBox(height: AppDimensions.paddingLarge),
            _buildInputMethodTabs(),
            const SizedBox(height: AppDimensions.paddingLarge),
            Text(
              'パターン選択',
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
                  ..._patterns.map((pattern) {
                    return Padding(
                      padding: const EdgeInsets.only(right: AppDimensions.paddingSmall),
                      child: _buildPatternButton(pattern),
                    );
                  }).toList(),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.paddingLarge),
            // ========== Week 27+ Step 2：タブに基づいてコンテンツを表示 ==========
            // ========== Week 27+ Step 2 修正：イベント追加は remove ==========
            if (_selectedInputMethod == 0)
              _buildCalendarInputMethod()
            else if (_selectedInputMethod == 1)
              _buildRangeInputMethod(),
            // タブ2は表示しない（直接遷移するため）
            // ===================================================
          ],
        ),
      ),
    );
  }

  // ========== Week 27+ Step 2：タブを3つに拡張 ==========
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
            child: _buildTabButton(label: 'カレンダー', index: 0, isSelected: _selectedInputMethod == 0),
          ),
          Container(width: 1, height: 40, color: AppColors.borderDefault),
          Expanded(
            child: _buildTabButton(label: '範囲指定', index: 1, isSelected: _selectedInputMethod == 1),
          ),
          Container(width: 1, height: 40, color: AppColors.borderDefault),
          // ========== Week 27+ Step 2 修正：イベント追加タブは直接遷移 ==========
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (context) => const CalendarEventScreen()),
                  );
                  if (result == true) {
                    await loadCalendarEvents();
                    setState(() {});
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  color: _selectedInputMethod == 2 ? AppColors.primaryGradientStart.withOpacity(0.1) : Colors.transparent,
                  child: Text(
                    'イベント追加',
                    style: AppTextStyles.bodyTextStyle.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: _selectedInputMethod == 2 ? AppColors.primaryGradientStart : AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          // ================================================================
        ],
      ),
    );
  }
  // ===================================================

  Widget _buildTabButton({required String label, required int index, required bool isSelected}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedInputMethod = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          color: isSelected ? AppColors.primaryGradientStart.withOpacity(0.1) : Colors.transparent,
          child: Text(
            label,
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: isSelected ? AppColors.primaryGradientStart : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildPatternButton(ShiftPatternModel pattern) {
    final isSelected = _selectedPattern?.id == pattern.id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedPattern = isSelected ? null : pattern),
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingSmall, vertical: 6.0),
          decoration: BoxDecoration(
            color: isSelected ? pattern.color.withOpacity(0.2) : pattern.color.withOpacity(0.1),
            border: Border.all(
              color: isSelected ? pattern.color : pattern.color.withOpacity(0.5),
              width: isSelected ? 2.0 : 1.0,
            ),
            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
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

  Widget _buildCalendarInputMethod() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'パターン選択後、日付をタップ',
          style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: AppDimensions.paddingMedium),
        Padding(
          padding: const EdgeInsets.only(bottom: AppDimensions.paddingSmall),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
                  });
                },
                child: Icon(Icons.chevron_left, color: AppColors.primaryGradientStart, size: 24),
              ),
              Text(
                '${_focusedDay.month}月 ${_focusedDay.year}',
                style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
                  });
                },
                child: Icon(Icons.chevron_right, color: AppColors.primaryGradientStart, size: 24),
              ),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.borderDefault),
              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
            ),
            child: TableCalendar(
            rowHeight: 75,
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2026, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: (day) {
              final normalized = DateTime(day.year, day.month, day.day);
              final events = <String>[];
              
              if (_shiftMap.containsKey(normalized)) {
                final patternName = _shiftMap[normalized]!.pattern?.patternName ?? '';
                if (patternName.isNotEmpty) {
                  events.add(patternName);
                }
              }
              
              for (final event in _calendarEvents) {
                final eventDate = event.eventDate is String 
                    ? DateTime.parse(event.eventDate as String)
                    : event.eventDate as DateTime;
                if (isSameDay(eventDate, day)) {
                  events.add(_getEventEmoji(event.eventType));
                }
              }
              
              return events;
            },
            onDaySelected: (selectedDay, focusedDay) async {
              final selectedDate = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);

              if (_selectedPattern?.patternType == ShiftType.halfVacation) {
                await _vacationRepository.recordVacationUsage(
                  'test_user',
                  selectedDay,
                  0.5,
                  'カレンダーから登録（半休）',
                );
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                  final dateKey = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
                  _vacationMap[dateKey] = 0.5;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ ${_selectedPattern!.patternName}を登録しました'),
                    duration: const Duration(seconds: 2),
                  ),
                );
                print('[ShiftManagementScreen] ✅ 半休を登録: ${selectedDay.month}月${selectedDay.day}日');
                return;
              } else if (_selectedPattern?.patternType == ShiftType.vacation) {
                await _vacationRepository.recordVacationUsage(
                  'test_user',
                  selectedDay,
                  1.0,
                  'カレンダーから登録（有休）',
                );
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                  final dateKey = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
                  _vacationMap[dateKey] = 1.0;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ ${_selectedPattern!.patternName}を登録しました'),
                    duration: const Duration(seconds: 2),
                  ),
                );
                print('[ShiftManagementScreen] ✅ 有休を登録: ${selectedDay.month}月${selectedDay.day}日');
                return;
              }

              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
                if (_selectedPattern != null) {
                  _shiftMap[selectedDate] = ShiftData(
                    date: selectedDay,
                    pattern: _selectedPattern,
                    customStartTime: null,
                    customEndTime: null,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ ${_selectedPattern!.patternName}を登録しました'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              });
            },
            onPageChanged: (focusedDay) => _focusedDay = focusedDay,
            calendarStyle: CalendarStyle(
              defaultDecoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.rectangle,
              ),
              selectedDecoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.rectangle,
                border: Border.all(
                  color: AppColors.primaryGradientStart,
                  width: 2.0,
                ),
                borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
              ),
              todayDecoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.rectangle,
                border: Border.all(
                  color: AppColors.primaryGradientStart.withOpacity(0.5),
                  width: 1.0,
                ),
                borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
              ),
              markerDecoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
              ),
              outsideTextStyle: const TextStyle(color: Colors.grey),
              defaultTextStyle: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 13),
              selectedTextStyle: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 13),
              todayTextStyle: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            calendarBuilders: CalendarBuilders(
              selectedBuilder: (context, date, focusedDay) {
                return GestureDetector(
                  onLongPress: () => _showDeleteDialog(date),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3.0),
                      child: Text(
                        '${date.day}',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    SizedBox(
                      height: 20,
                      child: _shiftMap.containsKey(DateTime(date.year, date.month, date.day))
                          ? Container(
                              decoration: BoxDecoration(
                                color: _shiftMap[DateTime(date.year, date.month, date.day)]!.pattern?.color.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 1.0),
                              child: Text(
                                _shiftMap[DateTime(date.year, date.month, date.day)]!.pattern?.patternName ?? '',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: _shiftMap[DateTime(date.year, date.month, date.day)]!.pattern?.color ?? Colors.black54,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    
                    SizedBox(
                      height: 16,
                      child: _vacationMap.containsKey(DateTime(date.year, date.month, date.day))
                          ? Text(
                              _vacationMap[DateTime(date.year, date.month, date.day)]! == 0.5 ? '🌤️ 半休' : '🏖️ 有休',
                              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            )
                          : const SizedBox.shrink(),
                    ),
                    
                    if (_calendarEvents.any((e) {
                      final eventDate = e.eventDate is String
                          ? DateTime.parse(e.eventDate as String)
                          : e.eventDate as DateTime;
                      return isSameDay(eventDate, date);
                    }))
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _calendarEvents
                            .where((e) {
                              final eventDate = e.eventDate is String
                                  ? DateTime.parse(e.eventDate as String)
                                  : e.eventDate as DateTime;
                              return isSameDay(eventDate, date);
                            })
                            .map((e) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2.0),
                              child: Text(
                                _getEventEmoji(e.eventType),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ))
                            .take(2)
                            .toList(),
                      ),
                  ],
                  ),
                );
              },
              defaultBuilder: (context, date, focusedDay) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3.0),
                      child: Text(
                        '${date.day}',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    SizedBox(
                      height: 20,
                      child: _shiftMap.containsKey(DateTime(date.year, date.month, date.day))
                          ? Container(
                              decoration: BoxDecoration(
                                color: _shiftMap[DateTime(date.year, date.month, date.day)]!.pattern?.color.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 1.0),
                              child: Text(
                                _shiftMap[DateTime(date.year, date.month, date.day)]!.pattern?.patternName ?? '',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: _shiftMap[DateTime(date.year, date.month, date.day)]!.pattern?.color ?? Colors.black54,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    if (_calendarEvents.any((e) {
                      final eventDate = e.eventDate is String
                          ? DateTime.parse(e.eventDate as String)
                          : e.eventDate as DateTime;
                      return isSameDay(eventDate, date);
                    }))
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _calendarEvents
                            .where((e) {
                              final eventDate = e.eventDate is String
                                  ? DateTime.parse(e.eventDate as String)
                                  : e.eventDate as DateTime;
                              return isSameDay(eventDate, date);
                            })
                            .map((e) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2.0),
                              child: Text(
                                _getEventEmoji(e.eventType),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ))
                            .take(2)
                            .toList(),
                      ),
                  ],
                );
              },
                          ),


              
              
            ),
            
            
          ),
        ),
         Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 12.0,
          ),
          child: VacationStatsWidget(userId: 'test_user'),
        ),

        const SizedBox(height: AppDimensions.paddingMedium),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _shiftMap.isNotEmpty
                ? () {
                    if (widget.onNavigateToDetails != null) {
                      final result = widget.onNavigateToDetails!(_shiftMap, widget.patterns);
                      if (result is Future) {
                        result.then((value) {
                          if (value == true) {
                            loadShifts();
                            setState(() {});
                          }
                        });
                      }
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _shiftMap.isNotEmpty
                  ? AppColors.primaryGradientStart
                  : AppColors.borderDefault,
              padding: EdgeInsets.symmetric(vertical: AppDimensions.paddingMedium),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
              ),
            ),
            child: Text(
              'シフト保存',
              style: AppTextStyles.bodyTextStyle.copyWith(
                color: _shiftMap.isNotEmpty ? Colors.white : AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 16,
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
              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('保存予定: ${_shiftMap.length}日', style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6.0),
                ..._shiftMap.entries.map((entry) {
                  final patternColor = entry.value.pattern?.color ?? Colors.grey;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4.0),
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
                                border: Border.all(color: patternColor.withOpacity(0.5), width: 1),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            Text(
                              '${entry.key.month}/${entry.key.day}: ${entry.value.pattern?.patternName ?? ''}',
                              style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => _deleteShiftEntry(entry.key),
                          child: Icon(Icons.close, size: 16, color: AppColors.warningRed),
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

  Widget _buildRangeInputMethod() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('開始日と終了日を指定', style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 13, color: AppColors.textMuted)),
        const SizedBox(height: AppDimensions.paddingMedium),
        Row(
          children: [
            Expanded(
              child: _buildDateField(
                label: '開始',
                date: _rangeStartDate,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _rangeStartDate ?? DateTime.now(),
                    firstDate: DateTime.utc(2024, 1, 1),
                    lastDate: DateTime.utc(2026, 12, 31),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: AppColors.primaryGradientStart)),
                      child: child!,
                    ),
                  );
                  if (picked != null) setState(() => _rangeStartDate = picked);
                },
              ),
            ),
            const SizedBox(width: AppDimensions.paddingSmall),
            Expanded(
              child: _buildDateField(
                label: '終了',
                date: _rangeEndDate,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _rangeEndDate ?? DateTime.now(),
                    firstDate: DateTime.utc(2024, 1, 1),
                    lastDate: DateTime.utc(2026, 12, 31),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: AppColors.primaryGradientStart)),
                      child: child!,
                    ),
                  );
                  if (picked != null) setState(() => _rangeEndDate = picked);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.paddingMedium),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _rangeStartDate != null && _rangeEndDate != null && _selectedPattern != null ? _applyRangeShift : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _rangeStartDate != null && _rangeEndDate != null && _selectedPattern != null ? AppColors.primaryGradientStart : AppColors.borderDefault,
              padding: EdgeInsets.symmetric(vertical: AppDimensions.paddingSmall),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall)),
            ),
            child: Text('範囲適用', style: AppTextStyles.bodyTextStyle.copyWith(
              color: _rangeStartDate != null && _rangeEndDate != null && _selectedPattern != null ? Colors.white : AppColors.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            )),
          ),
        ),
        if (_shiftMap.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppDimensions.paddingMedium),
            child: Container(
              padding: const EdgeInsets.all(AppDimensions.paddingSmall),
              decoration: BoxDecoration(color: AppColors.cardBgWarning, borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall)),
              child: Text('予定済み: ${_shiftMap.length}日', style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ),
      ],
    );
  }

  
  // ===================================================

  Widget _buildDateField({required String label, required DateTime? date, required VoidCallback onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w500, fontSize: 12)),
        const SizedBox(height: 6.0),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingSmall, vertical: 10.0),
            decoration: BoxDecoration(border: Border.all(color: AppColors.borderDefault), borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(date != null ? '${date.month}/${date.day}' : 'タップして選択', style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 14, color: date != null ? AppColors.textPrimary : AppColors.textMuted)),
                Icon(Icons.calendar_today, size: 18, color: AppColors.primaryGradientStart),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _applyRangeShift() async {
      if (_rangeStartDate == null || _rangeEndDate == null || _selectedPattern == null) return;
      DateTime current = _rangeStartDate!;
      while (!current.isAfter(_rangeEndDate!)) {
        final normalized = DateTime(current.year, current.month, current.day);
        _shiftMap[normalized] = ShiftData(date: normalized, pattern: _selectedPattern);
        
        if (_selectedPattern!.patternType == ShiftType.vacation) {
          await _vacationRepository.recordVacationUsage(
            'test_user',
            normalized,
            1.0,
            'カレンダーから登録（有休）',
          );
        } else if (_selectedPattern!.patternType == ShiftType.halfVacation) {
          await _vacationRepository.recordVacationUsage(
            'test_user',
            normalized,
            0.5,
            'カレンダーから登録（半休）',
          );
        }
        
        current = current.add(const Duration(days: 1));
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_rangeEndDate!.difference(_rangeStartDate!).inDays + 1}日追加'),
          backgroundColor: AppColors.primaryGradientStart,
          duration: const Duration(seconds: 2),
        ),
      );
    }

  Future<void> loadCalendarEvents() async {
    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month - 1, 1);
      final endDate = DateTime(now.year, now.month + 2, 0);
      final events = await _shiftRepository.getCalendarEventsForDateRange(startDate, endDate);
      setState(() {
        _calendarEvents.clear();
        _calendarEvents.addAll(events);
      });
    } catch (e) {
      print('エラー: $e');
    }
  }
  
  Future<void> _deleteShiftEntry(DateTime dateKey) async {
    final shiftData = _shiftMap[dateKey];
    
    _shiftMap.remove(dateKey);
    
    if (shiftData?.pattern?.patternType == ShiftType.vacation ||
        shiftData?.pattern?.patternType == ShiftType.halfVacation) {
      await _vacationRepository.deleteVacationUsageByDate(
        'test_user',
        dateKey,
      );
      print('[ShiftManagementScreen] ✅ 有休・半休をキャンセル: ${dateKey.month}月${dateKey.day}日');
    }
    
    setState(() {});
  }

  Future<void> loadShifts() async {
    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month - 1, 1);
      final endDate = DateTime(now.year, now.month + 2, 0);
      final shiftRecords = await _shiftRepository.getShiftsForDateRange(startDate, endDate);
      setState(() {
        _shiftMap.clear();
        for (final record in shiftRecords) {
          final dateStr = record['shift_date'] as String;
          final patternId = record['pattern_id'] as String?;
          final date = DateTime.parse(dateStr);
          final normalized = DateTime(date.year, date.month, date.day);
          ShiftPatternModel? matchingPattern;
          if (patternId != null) {
            matchingPattern = _patterns.firstWhere(
              (p) => p.id == patternId,
              orElse: () => _defaultDayOffPattern,
            );
          } else {
            matchingPattern = _defaultDayOffPattern;
          }
          _shiftMap[normalized] = ShiftData(date: normalized, pattern: matchingPattern);
        }
      });
      print("DEBUG: _shiftMap loaded with ${_shiftMap.length} entries");
      _shiftMap.forEach((key, value) {
        print("  ${key.toString()}: ${value.pattern?.patternName}");
      });
    } catch (e) {
      print('エラー: $e');
    }
  }

  String _getEventEmoji(String eventType) {
    try {
      final matchedType = eventTypes.firstWhere(
        (type) => type.id == eventType,
        orElse: () => EventType(
          id: 'unknown',
          name: 'その他',
          emoji: '🔔',
        ),
      );
      return matchedType.emoji;
    } catch (e) {
      debugPrint('⚠️  イベント絵文字取得エラー: $e');
      return '🔔';
    }
  }

  void clearShiftMap() {
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
  }
        void _showDeleteShiftDialog(DateTime selectedDay, ShiftData shiftData) {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('${selectedDay.month}月${selectedDay.day}日'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('登録内容: ${shiftData.pattern?.patternName ?? "不明"}'),
                    const SizedBox(height: 8),
                    const Text('このシフトを削除しますか？'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);

                      final dateKey = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
                      setState(() {
                        _shiftMap.remove(dateKey);
                      });

                      if (shiftData.pattern?.patternType == ShiftType.vacation ||
                          shiftData.pattern?.patternType == ShiftType.halfVacation) {
                        _vacationRepository.deleteVacationUsageByDate(
                          'test_user',
                          selectedDay,
                        );
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ シフトを削除しました'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Text(
                      '削除',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              );
            },
          );
        }

  Map<String, dynamic> _getDeleteTargetsForDate(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final targets = <String, dynamic>{};
    
    if (_shiftMap.containsKey(normalizedDate)) {
      final shiftData = _shiftMap[normalizedDate]!;
      final patternName = shiftData.pattern?.patternName ?? '?';
      targets['shift'] = 'シフト：$patternName';
    }
    
    if (_vacationMap.containsKey(normalizedDate)) {
      final daysUsed = _vacationMap[normalizedDate]!;
      if (daysUsed == 1.0) {
        targets['vacation_full'] = '有休（1.0日）🏖️';
      } else if (daysUsed == 0.5) {
        targets['vacation_half'] = '半休（0.5日）🌤️';
      }
    }
    
    try {
      final event = _calendarEvents.where((e) {
        final eventDate = DateTime.parse(e.eventDate);
        return isSameDay(eventDate, normalizedDate);
      }).firstOrNull;
      
      if (event != null) {
        targets['event'] = 'イベント：${event.eventName ?? '無題'} ${event.eventEmoji}';
      }
    } catch (e) {
      debugPrint('Error checking events: $e');
    }
    
    return targets;
  }

  Future<void> _showDeleteDialog(DateTime selectedDate) async {
    final targets = _getDeleteTargetsForDate(selectedDate);
    
    if (targets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('この日付には削除対象がありません'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    
    final selectedItems = <String>{};
    selectedItems.addAll(targets.keys);
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('削除確認'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: targets.entries.map((entry) {
                  return CheckboxListTile(
                    title: Text(entry.value as String),
                    value: selectedItems.contains(entry.key),
                    onChanged: (bool? isChecked) {
                      setState(() {
                        if (isChecked == true) {
                          selectedItems.add(entry.key);
                        } else {
                          selectedItems.remove(entry.key);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: selectedItems.isEmpty
                      ? null
                      : () async {
                          await _deleteSelectedItems(selectedDate, selectedItems);
                          if (mounted) {
                            Navigator.pop(context);
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('削除しました')),
                            );
                          }
                        },
                  child: const Text('削除', style: TextStyle(color: Colors.red)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteSelectedItems(DateTime date, Set<String> selectedItems) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    const userId = 'test_user';
    
    try {
      if (selectedItems.contains('shift') && _shiftMap.containsKey(normalizedDate)) {
        await _shiftRepository.deleteShift(normalizedDate);
        _shiftMap.remove(normalizedDate);
      }
      
      if ((selectedItems.contains('vacation_full') || selectedItems.contains('vacation_half')) &&
          _vacationMap.containsKey(normalizedDate)) {
        await _vacationRepository.deleteVacationUsageByDate(userId, normalizedDate);
        _vacationMap.remove(normalizedDate);
      }
      
      if (selectedItems.contains('event')) {
        _calendarEvents.removeWhere((e) {
          final eventDate = DateTime.parse(e.eventDate);
          return isSameDay(eventDate, normalizedDate);
        });
      }
    } catch (e) {
      debugPrint('Error deleting items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除に失敗しました: $e')),
        );
      }
    }
  }
}