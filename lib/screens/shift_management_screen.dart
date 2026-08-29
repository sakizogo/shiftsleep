import 'package:flutter/material.dart';
import 'package:intl/intl.dart';  // ← これを追加！
import 'package:table_calendar/table_calendar.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/models/calendar_event.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';  // ========== Week 14 追加 ==========
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
  final VacationRepository _vacationRepository = VacationRepository();  // ========== Week 14 追加 ==========
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  final Map<DateTime, ShiftData> _shiftMap = {};
  late Map<DateTime, double> _vacationMap;  // Week 20: 有休/半休マップ
  final List<CalendarEvent> _calendarEvents = [];
  int _selectedInputMethod = 0;
  ShiftPatternModel? _selectedPattern;
  DateTime? _rangeStartDate;
  DateTime? _rangeEndDate;
  late ShiftPatternModel _defaultDayOffPattern;
  // ========== Week 19 Step 2：デフォルトパターン定義 ==========
  late ShiftPatternModel _defaultVacation1Day;
  late ShiftPatternModel _defaultVacationHalf;
  // ========================================================================
  late List<ShiftPatternModel> _patterns;  // ========== Week 14 追加 ==========
  
  @override
  void initState() {
    super.initState();
    _vacationMap = {};  // Week 20: 有休/半休マップを初期化
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
    
    // ========== Week 14 追加：patterns を初期化（有休・半休を追加） ==========
    // ========== Week 19 Step 2：デフォルトパターンを late 変数に保存 ==========
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
    // ========================================================================
    
    loadShifts();
    _loadPatterns();  // Week 19 Step 2：DB パターンを読み込みしマージ
    _loadVacationData();  // Week 20 Phase 2: 有休/半休を読み込み
    loadCalendarEvents();
  }
  
  // ========== Week 20 Phase 2：vacation_usage から有休/半休情報を読み込む ==========
  Future<void> _loadVacationData() async {
    try {
      // Week 20：今年の有休/半休を読み込み
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
  // ========================================================================

  // ========== Week 19 Step 2 修正：DB パターンをデフォルト3つにマージ ==========
  Future<void> _loadPatterns() async {
    try {
      final dbPatterns = await _shiftRepository.getAllPatterns();
      setState(() {
        // デフォルト3つ（休日、有休、半休）を常に最初に表示
        _patterns = [
          _defaultDayOffPattern,
          _defaultVacation1Day,
          _defaultVacationHalf,
        ];
        
        // DB パターンを追加（ID重複を避ける）
        for (final dbPattern in dbPatterns) {
          if (dbPattern.id != 'default_dayoff' && 
              dbPattern.id != 'default_vacation_1day' && 
              dbPattern.id != 'default_vacation_half') {
            _patterns.add(dbPattern);
          }
        }
      });
      print('[ShiftManagementScreen] Loaded ${_patterns.length} patterns (デフォルト3 + DB ${dbPatterns.length})');
    } catch (e) {
      print('[ShiftManagementScreen] Error loading patterns: $e');
    }
  }
  // ========================================================================

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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CalendarEventScreen(),
                    ),
                  ).then((result) {
                    if (result == true) {
                      loadCalendarEvents();
                      setState(() {});
                    }
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: EdgeInsets.symmetric(vertical: AppDimensions.paddingMedium),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'イベント追加',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
            if (_selectedInputMethod == 0)
              _buildCalendarInputMethod()
            else if (_selectedInputMethod == 1)
              _buildRangeInputMethod()
            else
              _buildManualInputMethod(),
            // ========== Week 6 Fix D 改良: 下部の重複したボタンを削除（上部のみに統一） ==========
            // 削除済み：下部「シフト保存」ボタン
            // 理由：上部ボタンで十分（スクロール不要）、UI/UXをシンプルに
            // =========================================================================

          ],
        ),
      ),
    );
  }

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
          Expanded(
            child: _buildTabButton(label: '手入力', index: 2, isSelected: _selectedInputMethod == 2),
          ),
        ],
      ),
    );
  }

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
          borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),  // ========== Week 19 追加：overflow をクリップ ==========
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.borderDefault),
              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
            ),
            child: TableCalendar(
            rowHeight: 75,  // Week 20：セル高さを75に増加（オーバーフロー4.0px対応）  // Week 20: セル高さを増やしてオーバーフロー対応
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2026, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: (day) {
              final normalized = DateTime(day.year, day.month, day.day);
              final events = <String>[];
              
              // シフトパターン名を追加
              if (_shiftMap.containsKey(normalized)) {
                final patternName = _shiftMap[normalized]!.pattern?.patternName ?? '';
                if (patternName.isNotEmpty) {
                  events.add(patternName);
                }
              }
              
              // イベント絵文字を追加
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

              // ========== Week 20 Phase 2：半休・有休の場合は vacation_usage のみに記録 ==========
              // シフトは登録しない（既存シフトを保持）
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
                  // ========== Week 20 修正：_vacationMap に直接反映 ==========
                  final dateKey = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
                  _vacationMap[dateKey] = 0.5;
                  // ====================================================
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ ${_selectedPattern!.patternName}を登録しました'),
                    duration: const Duration(seconds: 2),
                  ),
                );
                print('[ShiftManagementScreen] ✅ 半休を登録: ${selectedDay.month}月${selectedDay.day}日');
                return;  // ← _shiftMap には入れない
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
                  // ========== Week 20 修正：_vacationMap に直接反映 ==========
                  final dateKey = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
                  _vacationMap[dateKey] = 1.0;
                  // ====================================================
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ ${_selectedPattern!.patternName}を登録しました'),
                    duration: const Duration(seconds: 2),
                  ),
                );
                print('[ShiftManagementScreen] ✅ 有休を登録: ${selectedDay.month}月${selectedDay.day}日');
                return;  // ← _shiftMap には入れない
              }

              // ========== 通常シフト（半休・有休ではない）の場合のみ _shiftMap に入れる ==========
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
              // ========================================================================
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
              // ========== Fix B Week 5 Day 4：defaultBuilder にシフト色分け追加 ==========

              selectedBuilder: (context, date, focusedDay) {
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
                    // ========== Fix Week 11：シフトパターン名表示 ==========
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
                    // ================================================================
                    
                    // ========== Week 20 Phase 2：半休・有休表示 ==========
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
                    // ================================================================
                    
                    // ========== Fix Week 11：イベント絵文字表示のみ（●マーカー削除） ==========
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
                            .take(2)  // Week 20：イベントは最大2個まで
                            .toList(),
                      ),
                    // ================================================================
                  ],
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
                    // ========== Fix Week 11：シフトパターン名表示 ==========
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
                    // ================================================================
                    // ========== Fix Week 11：イベント絵文字表示のみ（●マーカー削除） ==========
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
                            .take(2)  // Week 20：イベントは最大2個まで
                            .toList(),
                      ),
                    // ================================================================
                  ],
                );
              },
                          ),


              // ========== Fix B Week 5 Day 4：todayBuilder にシフト色分け追加 ==========
              
              
            ),
            
            
          ),
        ),
         // ========== Week 11: 有給管理セクション ==========
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 12.0,
          ),
          child: VacationStatsWidget(userId: 'test_user'),
        ),
        // ===================================================         

        const SizedBox(height: AppDimensions.paddingMedium),
        // ========== Week 6 Fix D: カレンダー下にシフト保存ボタンを配置 ==========
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _shiftMap.isNotEmpty
                ? () {
                    if (widget.onNavigateToDetails != null) {
                      widget.onNavigateToDetails!(_shiftMap, widget.patterns);
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
        // ===================================================================
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

  Widget _buildManualInputMethod() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('手入力', style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 13, color: AppColors.textMuted)),
        const SizedBox(height: AppDimensions.paddingMedium),
        Text('選択パターン:', style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w500, fontSize: 13)),
        const SizedBox(height: 6.0),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingSmall, vertical: 10.0),
          decoration: BoxDecoration(
            color: _selectedPattern != null ? _selectedPattern!.color.withOpacity(0.1) : AppColors.cardBgGray,
            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
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
                      border: Border.all(color: _selectedPattern!.color.withOpacity(0.5), width: 1),
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
                    color: _selectedPattern != null ? _selectedPattern!.color : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

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
        
        // ========== Week 14 追加：有休・半休の場合は vacation_usage にも記録 ==========
        if (_selectedPattern!.patternType == ShiftType.vacation) {
          await _vacationRepository.recordVacationUsage(
            'test_user',  // TODO: 実ユーザーIDに変更
            normalized,
            1.0,
            'カレンダーから登録（有休）',
          );
        } else if (_selectedPattern!.patternType == ShiftType.halfVacation) {
          await _vacationRepository.recordVacationUsage(
            'test_user',  // TODO: 実ユーザーIDに変更
            normalized,
            0.5,
            'カレンダーから登録（半休）',
          );
        }
        // ========================================================================
        
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
  
  // ========== Week 14 追加：シフト削除時に vacation_usage も削除 ==========
  Future<void> _deleteShiftEntry(DateTime dateKey) async {
    final shiftData = _shiftMap[dateKey];
    
    _shiftMap.remove(dateKey);
    
    // 有休・半休の場合は vacation_usage からも削除
    if (shiftData?.pattern?.patternType == ShiftType.vacation ||
        shiftData?.pattern?.patternType == ShiftType.halfVacation) {
      await _vacationRepository.deleteVacationUsageByDate(
        'test_user',  // TODO: 実ユーザーIDに変更
        dateKey,
      );
      print('[ShiftManagementScreen] ✅ 有休・半休をキャンセル: ${dateKey.month}月${dateKey.day}日');
    }
    
    setState(() {});
  }
  // ========================================================================

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
    switch (eventType) {
      case '給料日':
        return '💰';
      case 'ボーナス':
        return '🎁';
      case '慰安旅行':
        return '✈️';
      case '祝日':
        return '🎉';
      case '重要会議':
        return '📅';
      case '締切':
        return '⏰';
      default:
        return '📌';
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
        /// ========== Week 15 Step 3 追加：シフト削除ダイアログ ==========
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

                      // シフトを削除
                      final dateKey = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);  // ========== Week 16 修正 ==========
                      setState(() {
                        _shiftMap.remove(dateKey);  // ========== Week 16 修正：shiftMap → _shiftMap ==========
                      });

                      // vacation_usage からも削除（有休の場合）
                      if (shiftData.pattern?.patternType == ShiftType.vacation ||  // ========== Week 16 修正：type → patternType ==========
                          shiftData.pattern?.patternType == ShiftType.halfVacation) {  // ========== Week 16 修正 ==========
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
        // ======================================================================
}