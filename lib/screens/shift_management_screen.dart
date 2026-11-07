import 'package:flutter/material.dart';
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
import 'package:shiftsleep/services/alarm_service.dart';  // ✅ H3
import 'package:shiftsleep/services/range_apply_message.dart';  // N93
import 'package:shiftsleep/services/shift_draft.dart';  // N140
import 'package:shiftsleep/services/shift_load.dart';  // N118
import 'package:shiftsleep/screens/calendar_event_screen.dart';
import 'package:shiftsleep/widgets/vacation_stats_widget.dart';
import 'package:shiftsleep/constants/calendar_range.dart';

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

/// N140：差分を作るために、日付 → パターンの Map にする（パターンのない ShiftData は保存されないので飛ばす）
Map<DateTime, ShiftPatternModel> shiftPatternsOf(Map<DateTime, ShiftData> shiftMap) {
  return {
    for (final entry in shiftMap.entries)
      if (entry.value.pattern != null) entry.key: entry.value.pattern!,
  };
}

class ShiftManagementScreen extends StatefulWidget {
  final List<ShiftPatternModel> patterns;
  final Function(Map<DateTime, ShiftData>, List<ShiftPatternModel>)? onNavigateToDetails;
  final ShiftDraftStore draftStore;  // N140：未確定の差分の置き場所（home_screen が持つ）

  const ShiftManagementScreen({
    Key? key,
    required this.patterns,
    required this.draftStore,
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
  int _vacationStatsVersion = 0;  // N77・N69：増やすと VacationStatsWidget を作り直して残日数を読み直す
  bool _isApplyingRange = false;  // N93：期間指定の処理中（二度押しで 2 回走らないように）
  // N118：読み込みに失敗している部分（空でないあいだは登録・保存を止め、バナーを出す）
  final Set<ShiftLoadPart> _loadFailures = {};
  bool _isReloading = false;  // N118：［再読み込み］の処理中
  // N140：この State で最後に DB から読めた内容（基準）。一度も読めていないあいだは null
  Map<DateTime, ShiftPatternModel>? _baseShifts;
  bool _patternsLoaded = false;  // N140：この State でパターンを読めたか

  /// N140 2/4：画面が変わるたびに、未確定の件数をバッジへ伝える（_shiftMap を変える場所を 1 か所ずつ直さなくて済むように）
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _syncDraftCount();
  }

  void _syncDraftCount() {
    if (!mounted) return;
    widget.draftStore.reportLive(_liveDraft());
  }

  @override
  void dispose() {
    // N140：State が消えても未確定が残るように、差分を預ける
    widget.draftStore.saveFromScreen(base: _baseShifts, current: shiftPatternsOf(_shiftMap));
    debugPrint('[ShiftDraft] 画面を閉じる：差分 ${widget.draftStore.draft.length} 件');
    super.dispose();
  }

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
      // ========== 🆕 修正：_loadVacationData を最初に実行 ==========
      print('[ShiftManagementScreen] 🔄 Step 1️⃣ 有休データを読み込み中...');
      await _loadVacationData();
      print('[ShiftManagementScreen] ✅ Step 1️⃣ 有休データ読み込み完了');
      
      // その後、他のデータを読み込む
      print('[ShiftManagementScreen] 🔄 Step 2️⃣ パターン・シフト・イベントを読み込み中...');
      await _loadPatterns();
      await loadShifts();
      await loadCalendarEvents();
      print('[ShiftManagementScreen] ✅ Step 2️⃣ 読み込み完了');
      
      print('[ShiftManagementScreen] ✅ 全ての初期化が完了');
    } catch (e) {
      print('[ShiftManagementScreen] ⚠️ 初期化エラー: $e');
    }
  }

  /// N118：［再読み込み］。処理中は押せない
  Future<void> _reloadAll() async {
    if (_isReloading) return;
    setState(() => _isReloading = true);
    try {
      await _initializeAllData();
    } finally {
      if (mounted) setState(() => _isReloading = false);
    }
  }

  /// N140：基準を読めるまで「シフト保存」を止める（replaceAllShifts は全行を書き直すので、読む前の Map では確定しない）
  bool _ensureBaseLoaded() {
    if (_baseShifts != null) return true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('⏳ シフトを読み込み中です。少し待ってからもう一度押してください'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 4),
      ),
    );
    return false;
  }

  /// N140：今の未確定の差分（基準を読む前なら、入れた分だけ）
  ShiftDraft _currentDraft() {
    final base = _baseShifts;
    final current = shiftPatternsOf(_shiftMap);
    return base == null ? editsWithoutBase(current) : computeShiftDraft(base: base, current: current);
  }

  /// N140 2/4：表示する未確定（基準を読む前は、預かっている差分にこの State で入れた分を重ねる）
  ShiftDraft _liveDraft() {
    final local = _currentDraft();
    return _baseShifts == null ? overlayShiftDraft(widget.draftStore.draft, local) : local;
  }

  /// N140 2/4：未確定を破棄する（確定済みのシフトは DB にあるので変わらない。有休の行は 3/4 まで戻らない）
  Future<void> _confirmDiscardDraft(int count) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(draftDiscardDialogTitle),
        content: Text(draftDiscardDialogBody(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('やめる'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('破棄する'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;

    widget.draftStore.clear();
    setState(() {
      _shiftMap.clear();
      _baseShifts?.forEach((date, pattern) {
        _shiftMap[date] = ShiftData(date: date, pattern: pattern);
      });
    });
    debugPrint('[ShiftDraft] 破棄：$count 件');
    // 読み直しに失敗したときの知らせが優先されるように、読み直す前に出す
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(draftDiscardedMessage(count)),
        duration: const Duration(seconds: 2),
      ),
    );
    await loadShifts();
  }

  /// N140 2/4：未確定があることを知らせるバナー（青系。📝 と文章・日数で意味が分かるようにする）
  Widget _buildDraftBanner(int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(
        color: AppColors.draftBannerBg,
        border: Border(left: BorderSide(color: AppColors.draftAccent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            draftBannerText(count),
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              // 期間指定の処理中は押せない（破棄のあとに残りの日が入らないように）
              onPressed: _isApplyingRange ? null : () => _confirmDiscardDraft(count),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.textPrimary),
              ),
              child: const Text(draftDiscardButtonLabel),
            ),
          ),
        ],
      ),
    );
  }

  /// N118：読み込みに失敗した部分を覚えて知らせる（その部分の表示は消さずに残す）
  void _onLoadFailed(ShiftLoadPart part, Object e) {
    if (!mounted) return;
    setState(() => _loadFailures.add(part));
    _showTapError(loadFailureMessage(part, e));
  }

  /// N118：読み込みに失敗しているあいだは止める。止めたら false
  bool _ensureLoaded() {
    final message = loadBlockMessage(_loadFailures);
    if (message == null) return true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ),
    );
    return false;
  }

    /// N118：失敗したら _vacationMap は消さずに残す（setState の前で止まる）
    Future<void> _loadVacationData() async {
      final loaded = <DateTime, double>{};
      try {
        // N67：カレンダーの範囲全体を読む（来年の 🏖️ も出るように）
        final startOfYear = CalendarRange.firstDate;
        final endOfYear = CalendarRange.lastDate;

        print('[ShiftManagementScreen] 🔍 有休データ検索範囲: $startOfYear ～ $endOfYear');

        final vacationUsages = await _vacationRepository.getVacationUsageInRange(
          'test_user',
          startOfYear,
          endOfYear,
        );

        print('[ShiftManagementScreen] 📊 取得した有休レコード数: ${vacationUsages.length}');

        for (final usage in vacationUsages) {
          // 🔧 修正：UTC → ローカルに変換
          final utcDate = usage.usageDate;
          final localDate = utcDate.isUtc
              ? DateTime(utcDate.year, utcDate.month, utcDate.day)
              : DateTime(usage.usageDate.year, usage.usageDate.month, usage.usageDate.day);

          loaded[localDate] = usage.daysUsed;
          print('[ShiftManagementScreen] 📌 有休登録: ${localDate.month}月${localDate.day}日 = ${usage.daysUsed}日');
        }
      } catch (e) {
        debugPrint('[ShiftManagementScreen] ❌ Error loading vacation data: $e');
        _onLoadFailed(ShiftLoadPart.vacation, e);
        return;
      }
      if (!mounted) return;
      setState(() {
        _loadFailures.remove(ShiftLoadPart.vacation);
        _vacationMap
          ..clear()
          ..addAll(loaded);
      });
      print('[ShiftManagementScreen] ✅ VacationMap loaded: ${_vacationMap.length} records');
    }

  /// N118：失敗したらパターン一覧は消さずに残す（setState の前で止まる）
  Future<void> _loadPatterns() async {
    final List<ShiftPatternModel> dbPatterns;
    try {
      dbPatterns = await _shiftRepository.getAllPatterns();
    } catch (e) {
      debugPrint('[ShiftManagementScreen] ❌ Error loading patterns: $e');
      _onLoadFailed(ShiftLoadPart.patterns, e);
      return;
    }
    if (!mounted) return;
    setState(() {
      _loadFailures.remove(ShiftLoadPart.patterns);
      _patternsLoaded = true;
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
  }

  @override
  Widget build(BuildContext context) {
    final draft = _liveDraft();  // N140 2/4
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
            // ========== Week 27+ Step 2：タブに基づいてコンテンツを表示 ==========
            // ========== Week 27+ Step 2 修正：イベント追加は remove ==========
            // N118：読み込みに失敗しているあいだはバナーを出したままにする
            if (_loadFailures.isNotEmpty) ...[
              _buildLoadErrorBanner(),
              const SizedBox(height: AppDimensions.paddingMedium),
            ],
            // N140 2/4：未確定があるときだけ出す
            if (!draft.isEmpty) ...[
              _buildDraftBanner(draft.length),
              const SizedBox(height: AppDimensions.paddingMedium),
            ],
            _buildInputMethodTabs(),
            const SizedBox(height: AppDimensions.paddingLarge),
            if (_selectedInputMethod == 0)
              _buildCalendarInputMethod(draft)
            else if (_selectedInputMethod == 1)
              _buildRangeInputMethod(draft),
            // タブ2は表示しない（直接遷移するため）
            // ===================================================
          ],
        ),
      ),
    );
  }

  /// N118：読み込みに失敗したときのバナー（色だけに頼らず ⚠️ と文字でも示す）
  Widget _buildLoadErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.paddingSmall),
      decoration: BoxDecoration(
        color: AppColors.cardBgAlert,
        border: Border.all(color: AppColors.warningRed, width: 1.5),
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '⚠️ シフトを読み込めませんでした。再読み込みするまで、登録・保存はできません',
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimensions.paddingSmall),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _isReloading ? null : _reloadAll,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_isReloading ? '読み込み中…' : '再読み込み'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGradientStart,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
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

  Widget _buildCalendarInputMethod(ShiftDraft draft) {
    final canProceed = canProceedToConfirm(totalDays: _shiftMap.length, pendingDays: draft.length);  // N140 2/4
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppDimensions.paddingSmall),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    final prev = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
                    if (!prev.isBefore(CalendarRange.firstDate)) _focusedDay = prev;  // N67：範囲の外に出ない
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
                    final next = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
                    if (!next.isAfter(CalendarRange.lastDate)) _focusedDay = next;  // N67：範囲の外に出ない
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
            firstDay: CalendarRange.firstDayUtc,  // N67
            lastDay: CalendarRange.lastDayUtc,
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

              // N118：パターンを選んでいて、読み込みに失敗しているなら止める（日を選ぶだけなら止めない）
              if (_selectedPattern != null && !_ensureLoaded()) return;

              if (_selectedPattern?.patternType == ShiftType.halfVacation) {
                // N93：await のあいだにパターンの選択が変わっても、押したときのパターンで続ける
                final pattern = _selectedPattern!;
                // N99：有休パターンの日に半休を入れたら、有休パターンを外す（シフトなし＋半休にする）
                // 出勤・休日などは今までどおり残す（N77 の共存）
                final removeVacationShift =
                    _shiftMap[selectedDate]?.pattern?.patternType == ShiftType.vacation;
                var vacationShiftRemoved = false;
                try {
                  if (removeVacationShift) {
                    // 保存前に開き直しても有休パターンが戻らないよう、DB からもすぐ消す（N98 の長押し削除と同じ）
                    await _shiftRepository.deleteShift(selectedDate);
                    _baseShifts?.remove(selectedDate);  // N140：DB から消したので基準からも外す
                    _shiftMap.remove(selectedDate);
                    vacationShiftRemoved = true;
                    // N78 で出勤を有休に置き換えて未保存なら、出勤前アラームが残っているので取り消す
                    await AlarmService.cancelPreAlarm(selectedDate);
                  }
                  await _vacationRepository.recordVacationUsage(
                    'test_user',
                    selectedDay,
                    0.5,
                    'カレンダーから登録（半休）',
                  );
                } catch (e) {
                  debugPrint('Error recording half vacation: $e');
                  if (!mounted) return;
                  // 有休パターンを外せたあとで失敗したときは、外した分だけ画面に出す
                  if (vacationShiftRemoved) setState(() {});
                  _showTapError('❌ 半休の登録に失敗しました: $e');
                  return;
                }
                if (!mounted) return;
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                  final dateKey = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
                  _vacationMap[dateKey] = 0.5;
                  _vacationStatsVersion++;
                });
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ ${pattern.patternName}を登録しました'),
                    duration: const Duration(seconds: 2),
                  ),
                );
                print('[ShiftManagementScreen] ✅ 半休を登録: ${selectedDay.month}月${selectedDay.day}日');
                return;
              } else if (_selectedPattern?.patternType == ShiftType.vacation) {
                // N93：await のあいだにパターンの選択が変わっても、押したときのパターンで続ける
                final pattern = _selectedPattern!;
                try {
                  await _vacationRepository.recordVacationUsage(
                    'test_user',
                    selectedDay,
                    1.0,
                    'カレンダーから登録（有休）',
                  );
                } catch (e) {
                  // N93：有休の行が入らなかったので、_vacationMap・_shiftMap はそのまま（その日は元のまま）
                  debugPrint('Error recording vacation: $e');
                  if (!mounted) return;
                  _showTapError('❌ 有休の登録に失敗しました: $e');
                  return;
                }
                if (!mounted) return;
                // N78：置き換える前のシフト（出勤のシフトなら、保存でアラームが取り消されることを知らせる）
                final previousPattern = _shiftMap[selectedDate]?.pattern;
                final replacedWork = previousPattern?.patternType == ShiftType.work;
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                  final dateKey = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
                  _vacationMap[dateKey] = 1.0;
                  _vacationStatsVersion++;
                  // N78：期間指定の有休と同じく、その日のシフトも「有休」にする
                  _shiftMap[dateKey] = ShiftData(date: dateKey, pattern: pattern);
                });
                if (previousPattern != null && previousPattern.id != pattern.id) {
                  debugPrint('🔁 N78: ${selectedDate.month}/${selectedDate.day} の ${previousPattern.patternName} を${pattern.patternName}に置き換え');
                }
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      vacationPlacedMessage(
                        pattern.patternName,
                        pending: _liveDraft().entries.containsKey(selectedDate),
                        replacedWork: replacedWork,
                      ),
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
                print('[ShiftManagementScreen] ✅ 有休を登録: ${selectedDay.month}月${selectedDay.day}日');
                return;
              }

              final pattern = _selectedPattern;
              if (pattern == null) {
                // パターンを選んでいなければ、日を選ぶだけ
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                return;
              }

              // N77：有休（1.0）の日なら有休を消す
              final bool removedVacation;
              try {
                removedVacation = await _removeFullVacationIfOverwritten(selectedDate, pattern);
              } catch (e) {
                // N93：有休を消せなかったので、有休も _shiftMap もそのまま（その日は元のまま）
                debugPrint('Error removing vacation: $e');
                if (!mounted) return;
                _showTapError('❌ 有休の削除に失敗しました: $e');
                return;
              }
              if (!mounted) return;

              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
                if (removedVacation) _vacationStatsVersion++;
                _shiftMap[selectedDate] = ShiftData(
                  date: selectedDay,
                  pattern: pattern,
                  customStartTime: null,
                  customEndTime: null,
                );
              });
              // N93：SnackBar は setState の外で出す
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    shiftPlacedMessage(
                      pattern.patternName,
                      pending: _liveDraft().entries.containsKey(selectedDate),
                    ),
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),  // N67：見出しの「○月 ○年」も更新する
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
              // N71：選択・今日・通常のマスを同じ中身で描く（今日のマスも数字を上に、シフト名・有休・イベントを表示）
              selectedBuilder: (context, date, focusedDay) =>
                  _buildDayCell(date, isSelected: true, isToday: isSameDay(date, DateTime.now())),
              todayBuilder: (context, date, focusedDay) =>
                  _buildDayCell(date, isSelected: false, isToday: true),
              defaultBuilder: (context, date, focusedDay) =>
                  _buildDayCell(date, isSelected: false, isToday: false),
            ),
            ),
          ),
        ),

        const SizedBox(height: AppDimensions.paddingLarge),
        Text(
          'パターン選択',
          style: AppTextStyles.bodyTextStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: AppDimensions.paddingSmall),

        Text(
          'パターン選択後、日付をタップ',
          style: AppTextStyles.bodyTextStyle.copyWith(
            fontSize: 13,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppDimensions.paddingMedium),


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
        const SizedBox(height: AppDimensions.paddingMedium),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canProceed
                ? () {
                    if (!_ensureLoaded()) return;  // N118
                    if (!_ensureBaseLoaded()) return;  // N140
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
              backgroundColor: canProceed
                  ? AppColors.primaryGradientStart
                  : AppColors.borderDefault,
              padding: EdgeInsets.symmetric(vertical: AppDimensions.paddingMedium),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
              ),
            ),
            child: Text(
              '確認へ進む',
              style: AppTextStyles.bodyTextStyle.copyWith(
                color: canProceed ? Colors.white : AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ),

         Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 12.0,
          ),
          child: VacationStatsWidget(key: ValueKey(_vacationStatsVersion), userId: 'test_user'),
        ),

        
        const SizedBox(height: AppDimensions.paddingMedium),
        if (canProceed)
          Container(
            padding: const EdgeInsets.all(AppDimensions.paddingSmall),
            decoration: BoxDecoration(
              color: AppColors.cardBgGray,
              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shiftListHeader(_shiftMap.length, draft), style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w600, fontSize: 12)),
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
                              '${entry.key.month}/${entry.key.day}: ${entry.value.pattern?.patternName ?? ''}'
                              '${draft.entries.containsKey(entry.key) ? ' 📝未確定' : ''}',
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

  /// N71：カレンダーの 1 マス（選択・今日・通常で共通）
  Widget _buildDayCell(DateTime date, {required bool isSelected, required bool isToday}) {
    final dateKey = DateTime(date.year, date.month, date.day);
    final shift = _shiftMap[dateKey];
    final vacationDays = _vacationMap[dateKey];
    final dayEvents = _calendarEvents.where((e) {
      final eventDate = e.eventDate is String
          ? DateTime.parse(e.eventDate as String)
          : e.eventDate as DateTime;
      return isSameDay(eventDate, date);
    }).take(2).toList();

    final cell = Container(
      // マスいっぱいの幅にそろえる（上下の margin は入れず rowHeight 75 に収める）
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      // 枠線は foregroundDecoration で描き、中身の寸法を変えない
      decoration: BoxDecoration(
        color: isToday ? AppColors.primaryGradientStart.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
      ),
      // 選んだ日は青（Wong 2011: Blue）の 2px、選んでいない今日は薄い紫の 1px
      foregroundDecoration: isSelected || isToday
          ? BoxDecoration(
              border: Border.all(
                color: isSelected
                    ? AppColors.calendarSelectedBorder
                    : AppColors.primaryGradientStart.withValues(alpha: 0.5),
                width: isSelected ? 2.0 : 1.0,
              ),
              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
            )
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3.0),
            child: Text(
              '${date.day}',
              style: TextStyle(
                color: isToday ? AppColors.primaryGradientStart : Colors.black87,
                fontWeight: isToday ? FontWeight.w900 : FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 2.0),
          SizedBox(
            height: 20,
            child: shift != null
                ? Container(
                    decoration: BoxDecoration(
                      color: shift.pattern?.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 1.0),
                    child: Text(
                      shift.pattern?.patternName ?? '',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: shift.pattern?.color ?? Colors.black54,
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
            child: vacationDays != null
                ? Text(
                    vacationDays == 0.5 ? '🌤️ 半休' : '🏖️ 有休',
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  )
                : const SizedBox.shrink(),
          ),
          if (dayEvents.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: dayEvents
                  .map((e) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.0),
                        child: Text(
                          _getEventEmoji(e.eventType),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );

    // 長押しで削除するのは、これまでどおり選んだマスだけ
    return isSelected
        ? GestureDetector(onLongPress: () => _showDeleteDialog(date), child: cell)
        : cell;
  }

  Widget _buildRangeInputMethod(ShiftDraft draft) {
    final canProceed = canProceedToConfirm(totalDays: _shiftMap.length, pendingDays: draft.length);  // N140 2/4
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
                    initialDate: CalendarRange.clamp(_rangeStartDate ?? DateTime.now()),  // N67
                    firstDate: CalendarRange.firstDate,
                    lastDate: CalendarRange.lastDate,
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: AppColors.primaryGradientStart)),
                      child: child!,
                    ),
                  );
                  if (picked == null) return;
                  setState(() {
                    _rangeStartDate = picked;
                    // N102：終了日が新しい開始日より前なら、終了日を開始日に合わせる
                    if (_rangeEndDate != null && DateUtils.dateOnly(_rangeEndDate!).isBefore(DateUtils.dateOnly(picked))) {
                      _rangeEndDate = picked;
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: AppDimensions.paddingSmall),
            Expanded(
              child: _buildDateField(
                label: '終了',
                date: _rangeEndDate,
                onTap: () async {
                  // N102：開始日より前は選べなくする。initialDate は「開始日・終了日（未設定なら今日）の遅いほう」
                  final endInitial = _rangeEndDate ?? DateTime.now();
                  final initialDate = _rangeStartDate != null && endInitial.isBefore(_rangeStartDate!)
                      ? _rangeStartDate!
                      : endInitial;
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: CalendarRange.clamp(initialDate),  // N67
                    firstDate: _rangeStartDate ?? CalendarRange.firstDate,
                    lastDate: CalendarRange.lastDate,
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
        const SizedBox(height: AppDimensions.paddingMedium),   // Line 660 の上
        SingleChildScrollView(                                  // Line 647
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
        ), // SingleChildScrollView                            // Line 659
        const SizedBox(height: AppDimensions.paddingMedium),   // Line 660
        
        const SizedBox(height: AppDimensions.paddingMedium),
        

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            // N93：処理中は押せない
            onPressed: _rangeStartDate != null && _rangeEndDate != null && _selectedPattern != null && !_isApplyingRange
                ? _applyRangeShift
                : null,
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

          SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canProceed
                ? () async {
                    if (!_ensureLoaded()) return;  // N118
                    if (!_ensureBaseLoaded()) return;  // N140
                    if (widget.onNavigateToDetails != null) {
                      final result = await widget.onNavigateToDetails!(_shiftMap, widget.patterns);
                      if (result is Future) {
                        result.then((value) {
                          if (value == true) {
                            loadShifts();
                            setState(() {
                              _selectedInputMethod = 0;  // ← カレンダーに戻る
                            });
                          }
                        });
                      }
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: canProceed
                  ? AppColors.primaryGradientStart
                  : AppColors.borderDefault,
              padding: EdgeInsets.symmetric(vertical: AppDimensions.paddingMedium),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
              ),
            ),
            child: Text(
              '確認へ進む',
              style: AppTextStyles.bodyTextStyle.copyWith(
                color: canProceed ? Colors.white : AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
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
      if (_isApplyingRange) return;
      if (_rangeStartDate == null || _rangeEndDate == null || _selectedPattern == null) return;
      if (!_ensureLoaded()) return;  // N118
      // N102：開始日 > 終了日なら止める（ピッカーでも選べないが念のため。日付だけで比べる）
      if (DateUtils.dateOnly(_rangeStartDate!).isAfter(DateUtils.dateOnly(_rangeEndDate!))) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ 終了日は開始日以降を選んでください'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      // N93：await のあいだにパターン・日付の選択が変わっても、押したときの値で続ける
      final pattern = _selectedPattern!;
      final rangeStart = _rangeStartDate!;
      final rangeEnd = _rangeEndDate!;

      setState(() => _isApplyingRange = true);
      try {
        await _applyRangeDays(pattern, rangeStart, rangeEnd);
      } finally {
        if (mounted) setState(() => _isApplyingRange = false);
      }
    }

  /// N93：期間の日を 1 日ずつ登録する
  /// その日の DB への書き込みが済んでから _shiftMap・_vacationMap を書き換え、失敗した日で止める
  /// それまでの日は残す（N68 で同じ日は上書きなので、同じ期間を登録し直せば続きが入る）
  Future<void> _applyRangeDays(
      ShiftPatternModel pattern, DateTime rangeStart, DateTime rangeEnd) async {
    final draftStore = widget.draftStore;  // N140：途中で State が消えても預けられるように
    DateTime current = rangeStart;
    DateTime? lastSucceeded;
    var vacationChanged = false;  // 有休・半休の行を 1 日でも書き換えたら true
    // N100：有休で置き換えた今日以降の出勤の日数（保存で出勤前アラームが取り消されるので案内する）
    // 半休はシフトと共存させるので置き換えず、数えない
    final isFullVacation = pattern.patternType == ShiftType.vacation;
    final isHalfVacation = pattern.patternType == ShiftType.halfVacation;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var replacedWorkDays = 0;
    try {
      while (!current.isAfter(rangeEnd)) {
        final normalized = DateTime(current.year, current.month, current.day);
        final replacesWork = isFullVacation &&
            !normalized.isBefore(today) &&
            _shiftMap[normalized]?.pattern?.patternType == ShiftType.work;

        if (isFullVacation) {
          await _vacationRepository.recordVacationUsage(
            'test_user',
            normalized,
            1.0,
            'カレンダーから登録（有休）',
          );
          vacationChanged = true;
          _shiftMap[normalized] = ShiftData(date: normalized, pattern: pattern);
          _vacationMap[normalized] = 1.0;  // N69：すぐ 🏖️ が出るように
        } else if (isHalfVacation) {
          // N100（B 案）：半休は出勤・休日などと共存させる（タップの半休と同じ）
          // 有休パターンの日だけ、N99 と同じく有休パターンを外す（シフトなし＋半休にする）
          if (_shiftMap[normalized]?.pattern?.patternType == ShiftType.vacation) {
            await _shiftRepository.deleteShift(normalized);
            _baseShifts?.remove(normalized);  // N140：DB から消したので基準からも外す
            _shiftMap.remove(normalized);
            await AlarmService.cancelPreAlarm(normalized);
          }
          await _vacationRepository.recordVacationUsage(
            'test_user',
            normalized,
            0.5,
            'カレンダーから登録（半休）',
          );
          vacationChanged = true;
          _vacationMap[normalized] = 0.5;  // N69：すぐ 🌤️ が出るように
        } else {
          if (await _removeFullVacationIfOverwritten(normalized, pattern)) {
            vacationChanged = true;  // N77
          }
          _shiftMap[normalized] = ShiftData(date: normalized, pattern: pattern);
        }

        if (replacesWork) replacedWorkDays++;
        lastSucceeded = normalized;
        _syncDraftCount();  // N140 2/4：ループの途中は setState を呼ばないので、ここで伝える
        current = current.add(const Duration(days: 1));
      }
    } catch (e) {
      debugPrint('Error applying range shift: $e');
      if (!mounted) {
        draftStore.addLateEdits(_currentDraft());  // N140：State が消えたあとに入れた分も残す
        return;
      }
      setState(() {
        if (vacationChanged) _vacationStatsVersion++;
      });
      final failed = DateTime(current.year, current.month, current.day);
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(rangeApplyFailureMessage(rangeStart, lastSucceeded, failed, e)),
          backgroundColor: AppColors.warningRed,
          duration: Duration(seconds: lastSucceeded == null ? 4 : 6),
        ),
      );
      // 念のため、有休・半休の表示を DB に合わせ直す
      await _loadVacationData();
      return;
    }
    if (!mounted) {
      draftStore.addLateEdits(_currentDraft());  // N140：State が消えたあとに入れた分も残す
      return;
    }

    setState(() {
      if (vacationChanged) _vacationStatsVersion++;
    });
    final rangeDays = rangeEnd.difference(rangeStart).inDays + 1;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${isHalfVacation ? '半休 $rangeDays日を登録しました' : rangeAddedMessage(rangeDays)}'
          '${replacedWorkDays > 0 ? '\n出勤 $replacedWorkDays日を${pattern.patternName}にしました。「シフトを確定」を押すと、その日の出勤前アラームが取り消されます' : ''}',
        ),
        backgroundColor: AppColors.primaryGradientStart,
        duration: Duration(seconds: replacedWorkDays > 0 ? 4 : 2),
      ),
    );
  }

  /// N93：マスのタップで失敗したときの SnackBar（前の SnackBar は消す。赤・4 秒は N104・N115 とそろえる）
  /// N118：読み込みの失敗もこれで知らせる
  void _showTapError(String message) {
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

  /// N77：有休（1.0）の日に普通のシフト・休日を入れたら、その日の有休を消す
  /// 半休（0.5）は消さない（Week 20 の「半休＋シフト共存」）。消したら true を返す
  Future<bool> _removeFullVacationIfOverwritten(DateTime date, ShiftPatternModel pattern) async {
    final dateKey = DateTime(date.year, date.month, date.day);
    if (_vacationMap[dateKey] != 1.0) return false;
    await _vacationRepository.deleteVacationUsageByDate('test_user', dateKey);
    _vacationMap.remove(dateKey);
    debugPrint('🗑️ N77: ${dateKey.month}/${dateKey.day} の有休 1.0 を削除（${pattern.patternName}で上書き）');
    return true;
  }

  /// N118：失敗したらイベントは消さずに残し、知らせるだけ（登録・保存は止めない）
  Future<void> loadCalendarEvents() async {
    final List<CalendarEvent> events;
    try {
      // N67：カレンダーの範囲全体を読む（来年のイベントも出るように）
      final startDate = CalendarRange.firstDate;
      final endDate = CalendarRange.lastDate;
      events = await _shiftRepository.getCalendarEventsForDateRange(startDate, endDate);
    } catch (e) {
      debugPrint('[ShiftManagementScreen] ❌ Error loading calendar events: $e');
      if (!mounted) return;
      _showTapError('❌ イベントの読み込みに失敗しました: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _calendarEvents.clear();
      _calendarEvents.addAll(events);
    });
  }
  
  /// N95・N96：有休・半休の行はすぐ消し、シフトの DB 行は保存まで残す
  /// 有休の削除に失敗したら、_shiftMap・_vacationMap は残して失敗を知らせる
  Future<void> _deleteShiftEntry(DateTime dateKey) async {
    final shiftData = _shiftMap[dateKey];
    var vacationDeleted = false;

    try {
      if (shiftData?.pattern?.patternType == ShiftType.vacation ||
          shiftData?.pattern?.patternType == ShiftType.halfVacation) {
        await _vacationRepository.deleteVacationUsageByDate(
          'test_user',
          dateKey,
        );
        _vacationMap.remove(dateKey);
        vacationDeleted = true;
        print('[ShiftManagementScreen] ✅ 有休・半休をキャンセル: ${dateKey.month}月${dateKey.day}日');
      }
    } catch (e) {
      debugPrint('Error deleting shift entry: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 削除に失敗しました: $e')),
      );
      return;
    }
    if (!mounted) return;

    setState(() {
      _shiftMap.remove(dateKey);
      if (vacationDeleted) _vacationStatsVersion++;
    });
  }

  /// N118：失敗したら _shiftMap は消さずに残す（空のまま確定してほかの日が消えないように）
  /// 一度読めたあとの再読み込み（再開・タブ切り替え・確定後）が失敗したときも、表示は残す
  /// N140：読めたら DB の内容に未確定の差分を重ねる（失敗したら差分・基準も変えない）
  Future<void> loadShifts() async {
    final Map<DateTime, ShiftPatternModel> loaded;
    try {
      // N67・N72：カレンダーの範囲全体を読む（読んでいない日のシフトが保存で消えないように）
      final startDate = CalendarRange.firstDate;
      final endDate = CalendarRange.lastDate;
      final shiftRecords = await _shiftRepository.getShiftsForDateRange(startDate, endDate);
      // N104：見つからないパターンの日は休日ではなく「削除済み」（元の pattern_id のまま）
      loaded = shiftMapFromRows(shiftRecords, _patterns, _defaultDayOffPattern);
    } catch (e) {
      debugPrint('[ShiftManagementScreen] ❌ Error loading shifts: $e');
      _onLoadFailed(ShiftLoadPart.shifts, e);
      return;
    }
    if (!mounted) return;
    late final ShiftDraftMergeResult mergeResult;
    setState(() {
      _loadFailures.remove(ShiftLoadPart.shifts);
      // await のあいだに入れた変更も入るよう、読めたあとで差分を作る
      final localDraft = _currentDraft();
      // この State で初めて読めたときだけ、預けてある差分を受け取る
      final draft = _baseShifts == null
          ? overlayShiftDraft(widget.draftStore.draft, localDraft)
          : localDraft;
      // パターンを読めていないあいだは、使用中のパターンを「削除された」と誤って判定しないようにする
      final patternsTrusted = _patternsLoaded && !_loadFailures.contains(ShiftLoadPart.patterns);
      mergeResult = mergeShiftDraft(
        db: loaded,
        draft: draft,
        patterns: patternsTrusted ? _patterns : null,
      );
      _baseShifts = loaded;
      _shiftMap.clear();
      mergeResult.merged.forEach((date, pattern) {
        _shiftMap[date] = ShiftData(date: date, pattern: pattern);
      });
    });
    debugPrint('[ShiftDraft] 読み込み：差分 ${_currentDraft().length} 件'
        '（衝突 ${mergeResult.conflictDates.length}・外した ${mergeResult.removedDates.length}）');
    final notice = draftMergeNotice(mergeResult);
    if (notice != null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(notice),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }
    print("DEBUG: _shiftMap loaded with ${_shiftMap.length} entries");
    _shiftMap.forEach((key, value) {
      print("  ${key.toString()}: ${value.pattern?.patternName}");
    });
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

  /// N98：シフトが有休の行と対になっている日か（有休パターン＋1.0、半休パターン＋0.5）
  /// この日は削除ダイアログで有休・半休の 1 行だけにし、消すときはシフトも一緒に消す
  bool _isPairedVacationShift(DateTime normalizedDate) {
    final patternType = _shiftMap[normalizedDate]?.pattern?.patternType;
    final daysUsed = _vacationMap[normalizedDate];
    return (patternType == ShiftType.vacation && daysUsed == 1.0) ||
        (patternType == ShiftType.halfVacation && daysUsed == 0.5);
  }

  Map<String, dynamic> _getDeleteTargetsForDate(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final targets = <String, dynamic>{};

    // N98：有休・半休と対になったシフトは、有休・半休の行にまとめる
    if (_shiftMap.containsKey(normalizedDate) && !_isPairedVacationShift(normalizedDate)) {
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
      // N76：その日のイベントをすべて「名前 絵文字」にして 1 行にまとめる（削除は日付でまとめて行う）
      final dayEvents = _calendarEvents.where((e) {
        final eventDate = DateTime.parse(e.eventDate);
        return isSameDay(eventDate, normalizedDate);
      }).toList();

      if (dayEvents.isNotEmpty) {
        final labels = dayEvents.map((e) {
          final typeName = eventTypes.where((t) => t.id == e.eventType).firstOrNull?.name;
          final name = (e.eventName?.isNotEmpty ?? false) ? e.eventName! : (typeName ?? '無題');
          return '$name ${_getEventEmoji(e.eventType)}';
        });
        targets['event'] = 'イベント：${labels.join('、')}';
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
                          final deleted = await _deleteSelectedItems(selectedDate, selectedItems);
                          if (mounted) {
                            Navigator.pop(context);
                            setState(() {});
                            // N74：失敗したときは _deleteSelectedItems が失敗の SnackBar を出すので、ここでは出さない
                            if (deleted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('削除しました')),
                              );
                            }
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

  /// N74：全部消せたら true、途中で失敗したら false を返す
  Future<bool> _deleteSelectedItems(DateTime date, Set<String> selectedItems) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    const userId = 'test_user';
    var vacationDeleted = false;  // N95：有休の行を消せたら統計を読み直す（途中で失敗しても）

    final deleteVacation =
        (selectedItems.contains('vacation_full') || selectedItems.contains('vacation_half')) &&
            _vacationMap.containsKey(normalizedDate);
    // N98：有休・半休と対になったシフトは、有休・半休と一緒に消す（'shift' と両方選ばれても 1 回だけ）
    final deleteShift = _shiftMap.containsKey(normalizedDate) &&
        (selectedItems.contains('shift') ||
            (deleteVacation && _isPairedVacationShift(normalizedDate)));

    try {
      // N98：シフトを先に消す（有休の削除で失敗しても 🏖️／🌤️ だけ残る状態になるように）
      if (deleteShift) {
        await _shiftRepository.deleteShift(normalizedDate);
        // ✅ H3: 削除した日の出勤前アラーム（pre）だけをキャンセル（起床アラーム main は残す）
        await AlarmService.cancelPreAlarm(normalizedDate);
        _baseShifts?.remove(normalizedDate);  // N140：DB から消したので基準からも外す
        _shiftMap.remove(normalizedDate);
      }

      if (deleteVacation) {
        await _vacationRepository.deleteVacationUsageByDate(userId, normalizedDate);
        _vacationMap.remove(normalizedDate);
        vacationDeleted = true;
      }
      
      if (selectedItems.contains('event')) {
        await _shiftRepository.deleteCalendarEventByDate(normalizedDate);
        _calendarEvents.removeWhere((e) {
          final eventDate = DateTime.parse(e.eventDate);
          return isSameDay(eventDate, normalizedDate);
        });
      }

      if (mounted) {
        setState(() {
          if (vacationDeleted) _vacationStatsVersion++;
        });
      }
      return true;
    } catch (e) {
      debugPrint('Error deleting items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除に失敗しました: $e')),
        );
      }
      if (mounted) {
        setState(() {
          if (vacationDeleted) _vacationStatsVersion++;
        });
      }
      return false;
    }
  }
}