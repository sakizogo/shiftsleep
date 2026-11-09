import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/vacation_load_state.dart';  // N118 3/4 3c

class VacationUsageScreen extends StatefulWidget {
  final String userId;

  const VacationUsageScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<VacationUsageScreen> createState() => _VacationUsageScreenState();
}

class _VacationUsageScreenState extends State<VacationUsageScreen> {
  late VacationRepository _repository;
  final ShiftRepository _shiftRepository = ShiftRepository();  // N101
  late TextEditingController _reasonController;

  DateTime? _selectedUsageDate;
  double? _selectedDaysUsed;  // ========== Week 14 追加：選択された使用日数（1.0 or 0.5） ==========
  bool _showAddForm = false;
  // N118 3/4 3c：読み込みの状態。loaded 以外（読み込み中・失敗中）は追加・削除・使用日の選択を押せない
  VacationLoadState _loadState = VacationLoadState.loading;
  // N118 3/4 3c：再読み込み中（二度押し防止）
  bool _isReloading = false;

  bool get _canEdit => canAddVacationUsage(_loadState);

  double _totalRemainingDays = 0.0;
  VacationSummary? _summary;
  List<VacationUsage> _usageList = [];

  @override
  void initState() {
    super.initState();
    _repository = VacationRepository();
    _reasonController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  // データを読み込む
  /// N118 3/4 3c：読めたら true。どれか 1 つでも読めなければ、画面全体を ❌ にして false
  /// （一部だけ読めた値は出さない。記録・削除のあとの読み直しで失敗したときも ❌ にする）
  Future<bool> _loadData() async {
    try {
      final remaining = await _repository.calculateRemainingDays(widget.userId);
      final summary = await _repository.getAccrualSummary(widget.userId);
      
      // N66：一覧は付与年度（今日より後の予定も含む）。求まらなければ暦年
      final fiscalYear = await _repository.getCurrentFiscalYear(widget.userId);
      final usageList = await _repository.getVacationUsageInFiscalYear(
        widget.userId,
        fiscalYear,
      );

      if (!mounted) return false;
      setState(() {
        _totalRemainingDays = remaining;
        _summary = summary;
        _usageList = usageList;
        _loadState = VacationLoadState.loaded;
      });
      return true;
    } catch (e) {
      debugPrint('❌ N118 3/4 3c: 有給使用記録の読み込みに失敗: $e');
      if (mounted) {
        setState(() => _loadState = VacationLoadState.failed);
      }
      return false;
    }
  }

  /// N118 3/4 3c：［再読み込み］。成功したら通常の画面に戻る。結果は SnackBar でも知らせる（3b と同じ）
  Future<void> _reloadData() async {
    if (!canReloadVacationSettings(reloading: _isReloading)) return;
    final messenger = ScaffoldMessenger.of(context);  // await 前に取得
    setState(() => _isReloading = true);
    final bool succeeded;
    try {
      succeeded = await _loadData();
    } finally {
      if (mounted) setState(() => _isReloading = false);
    }
    if (!mounted) return;
    final message = vacationUsageReloadMessage(succeeded: succeeded);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message.text),
        backgroundColor: message.color,
        duration: Duration(seconds: message.color == Colors.orange ? 6 : 2),
      ),
    );
  }

  /// N118 3/4 3c：読み込めなかったときの画面（AppBar の戻るボタンはそのまま使える）
  Widget _buildLoadFailedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              vacationUsageLoadFailedTitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              vacationUsageLoadFailedBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: canReloadVacationSettings(reloading: _isReloading) ? _reloadData : null,
              icon: _isReloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isReloading ? '読み込み中…' : '再読み込み'),
            ),
          ],
        ),
      ),
    );
  }

  // 使用日をピッカーで選択
  Future<void> _selectUsageDate() async {
    if (!_canEdit) return;  // N118 3/4 3c
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedUsageDate ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 3, 1, 1),
      lastDate: DateTime.now(),
    );

    if (!mounted) return;  // N118 3/4 3c
    if (pickedDate != null) {
      setState(() {
        _selectedUsageDate = pickedDate;
      });
    }
  }

  // 有給使用を記録
  Future<void> _recordVacationUsage() async {
    if (!_canEdit) return;  // N118 3/4 3c
    if (_selectedUsageDate == null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 使用日を選択してください')),
      );
      return;
    }

    // ========== Week 14 修正：_selectedDaysUsed をチェック ==========
    if (_selectedDaysUsed == null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 使用日数を選択してください')),
      );
      return;
    }

    final usageDate = _selectedUsageDate!;
    final day = DateTime(usageDate.year, usageDate.month, usageDate.day);
    final daysUsed = _selectedDaysUsed!;  // ボタンで選択した 1.0 or 0.5 を使う
    // N118 3/4 3c：失敗の ❌ は画面を閉じたあとでも出す（await 前に取得）
    final messenger = ScaffoldMessenger.of(context);

    try {
      // N101：有休パターンの日に半休を入れたら、N99 と同じく有休パターンを外す（シフトなし＋半休にする）
      // 出勤・休日などは残す（N77 の共存）。1.0 はシフトに触らない
      if (daysUsed == 0.5 && await _shiftTypeOn(day) == ShiftType.vacation) {
        await _shiftRepository.deleteShift(day);
        await AlarmService.cancelPreAlarm(day);
      }
      await _repository.recordVacationUsage(
        widget.userId,
        usageDate,
        daysUsed,
        _reasonController.text.isEmpty ? null : _reasonController.text,
      );
    } catch (e) {
      debugPrint('Error recording vacation usage: $e');
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('❌ 有給使用の記録に失敗しました: $e')),
      );
      if (!mounted) return;
      // シフトだけ消えて行が入らなかった場合もあるので、画面を DB に合わせる
      _loadData();
      return;
    }
    if (!mounted) return;

    setState(() {
      _reasonController.clear();
      _selectedDaysUsed = null;  // ========== Week 14 修正：リセット ==========
      _selectedUsageDate = null;
      _showAddForm = false;
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 有給使用を記録しました')),
    );
    _loadData();
  }

  /// N101：その日のシフトのパターンの種類（シフトがない・読めないときは null ＝シフトなし扱い）
  Future<ShiftType?> _shiftTypeOn(DateTime day) async {
    final shifts = await _shiftRepository.getShiftsForDateRange(day, day);
    if (shifts.isEmpty) return null;
    final patternId = shifts.first['pattern_id'] as String?;
    if (patternId == null) return null;
    final pattern = await _shiftRepository.getPatternById(patternId);
    return pattern?.patternType;
  }

  // 使用履歴を削除
  Future<void> _deleteVacationUsage(VacationUsage usage) async {
    if (!_canEdit) return;  // N118 3/4 3c
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認'),
        content: const Text('この使用履歴を削除してもよろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;  // N118 3/4 3c
    // N118 3/4 3c：失敗の ❌ は画面を閉じたあとでも出す（await 前に取得）
    final messenger = ScaffoldMessenger.of(context);

    // 年・月・日の数字をそのまま使う（Z つきの行も toLocal() は通さない）
    final day = DateTime(usage.usageDate.year, usage.usageDate.month, usage.usageDate.day);
    try {
      // N101：有休パターン＋1.0／半休パターン＋0.5 の日は、N98 と同じくシフトも一緒に消す
      // シフトを先に消す（行の削除で失敗しても 🏖️／🌤️ の行だけ残る状態になるように）
      final shiftType = await _shiftTypeOn(day);
      final removeShift = (usage.daysUsed == 1.0 && shiftType == ShiftType.vacation) ||
          (usage.daysUsed == 0.5 && shiftType == ShiftType.halfVacation);
      if (removeShift) {
        await _shiftRepository.deleteShift(day);
        await AlarmService.cancelPreAlarm(day);
      }
      await _repository.deleteVacationUsage(usage.id);
    } catch (e) {
      debugPrint('Error deleting vacation usage: $e');
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('❌ 削除に失敗しました: $e')),
      );
      if (!mounted) return;
      // シフトだけ消えて行が残った場合もあるので、画面を DB に合わせる
      _loadData();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 使用履歴を削除しました')),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadState == VacationLoadState.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('有給使用記録')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    // N118 3/4 3c（D6）：読み込めなかったら画面全体を ❌ と［再読み込み］にする
    // 統計・一覧（削除ボタン）・［使用記録を追加］は出さない。追加フォームの入力は消さずに残す
    if (_loadState == VacationLoadState.failed) {
      return Scaffold(
        appBar: AppBar(title: const Text('有給使用記録')),
        body: _buildLoadFailedView(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('有給使用記録'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 📊 統計情報（上部固定）
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📊 有給統計',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // メインの残日数表示
                    // N66：ラベルが長くなったので、各列を Expanded にして折り返せるようにする（横にはみ出さない）
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('有効な付与日数（持ち越し含む）',
                                  style: TextStyle(color: Colors.grey)),
                              Text(
                                '${_summary?.totalGranted ?? 0}日',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('うち使用（予定含む）',
                                  style: TextStyle(color: Colors.grey)),
                              Text(
                                '${_summary?.totalUsed.toStringAsFixed(1) ?? '0'}日',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('残日数',
                                  style: TextStyle(color: Colors.grey)),
                              Text(
                                '${_totalRemainingDays.toStringAsFixed(1)}日',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 失効予定の警告セクション
          if (_summary != null && _summary!.expiryWarningMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _summary!.expiryWarningMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // ➕ フォーム（展開可能）
          if (_showAddForm)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📝 使用記録を追加',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '💡 過去の有給使用も登録できます（けが・病欠など）',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _selectUsageDate,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          _selectedUsageDate == null
                              ? '使用日を選択'
                              : DateFormat('yyyy年M月d日')
                                  .format(_selectedUsageDate!),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // ========== Week 14 追加：ボタングループで使用日数を選択 ==========
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '使用日数を選択',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // 「1日」ボタン
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedDaysUsed = 1.0;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _selectedDaysUsed == 1.0
                                        ? Colors.blue
                                        : Colors.grey[300],
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    '🏖️ 1日',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _selectedDaysUsed == 1.0
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 「半休」ボタン
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedDaysUsed = 0.5;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _selectedDaysUsed == 0.5
                                        ? Colors.blue
                                        : Colors.grey[300],
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    '🌤️ 半休',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _selectedDaysUsed == 0.5
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // ========== Week 14 追加ここまで ==========

                      const SizedBox(height: 12),
                      TextField(
                        controller: _reasonController,
                        decoration: InputDecoration(
                          labelText: '使用理由（任意）',
                          hintText: '例: 個人の用事、医者の予約、けが',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          suffixIcon: const Icon(Icons.note),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _recordVacationUsage,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          backgroundColor: Colors.green,
                        ),
                        child: const Text(
                          '💾 記録を保存',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 16),

          // 📝 使用履歴一覧
          Expanded(
            child: _usageList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '有給使用記録がありません',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: _usageList.length,
                    itemBuilder: (context, index) {
                      final usage = _usageList[index];
                      // N66：今日より後の使用は「予定」。色だけでなく文字でも分かるようにする
                      final now = DateTime.now();
                      final isPlanned = DateTime(usage.usageDate.year, usage.usageDate.month, usage.usageDate.day)
                          .isAfter(DateTime(now.year, now.month, now.day));
                      return Card(
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                usage.daysUsed == 0.5 ? '🌤️' : '🏖️',
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                DateFormat('M月d日(E)', 'ja_JP')
                                    .format(usage.usageDate),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (isPlanned) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade600),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '予定',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                isPlanned
                                    ? '${usage.daysUsed.toStringAsFixed(1)}日使用（予定）'
                                    : '${usage.daysUsed.toStringAsFixed(1)}日使用',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              if (usage.reason != null &&
                                  usage.reason!.isNotEmpty)
                                Text(
                                  usage.reason!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () =>
                                _deleteVacationUsage(usage),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: !_showAddForm
          ? FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  _showAddForm = true;
                  _selectedUsageDate = null;
                  _selectedDaysUsed = null;  // ========== Week 14 修正：リセット ==========
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('使用記録を追加'),
            )
          : FloatingActionButton(
              onPressed: () {
                setState(() {
                  _showAddForm = false;
                  _reasonController.clear();
                  _selectedDaysUsed = null;  // ========== Week 14 修正：リセット ==========
                  _selectedUsageDate = null;
                });
              },
              backgroundColor: Colors.red,
              child: const Icon(Icons.close),
            ),
    );
  }
}