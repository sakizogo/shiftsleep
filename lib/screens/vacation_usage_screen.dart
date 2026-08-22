import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';

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
  late TextEditingController _reasonController;
  late TextEditingController _daysUsedController;

  DateTime? _selectedUsageDate;
  bool _showAddForm = false;
  bool _isLoading = true;

  double _totalRemainingDays = 0.0;  // 🌟 変更：正確な残日数
  VacationSummary? _summary;         // 🌟 新規：サマリー情報
  List<VacationUsage> _usageList = [];

  @override
  void initState() {
    super.initState();
    _repository = VacationRepository();
    _reasonController = TextEditingController();
    _daysUsedController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _daysUsedController.dispose();
    super.dispose();
  }

  // データを読み込む
  Future<void> _loadData() async {
    try {
      // 🌟 変更：calculateRemainingDays() で正確に計算
      final remaining = await _repository.calculateRemainingDays(widget.userId);
      final summary = await _repository.getAccrualSummary(widget.userId);
      
      final now = DateTime.now();
      final usageList = await _repository.getVacationUsageInRange(
        widget.userId,
        DateTime(now.year, 1, 1),
        now,
      );

      setState(() {
        _totalRemainingDays = remaining;
        _summary = summary;
        _usageList = usageList;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading vacation data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 使用日をピッカーで選択（過去日付も選択可能に）
  Future<void> _selectUsageDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedUsageDate ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 3, 1, 1),  // 🌟 変更：過去3年まで選択可能
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedUsageDate = pickedDate;
      });
    }
  }

  // 有給使用を記録
  Future<void> _recordVacationUsage() async {
    if (_selectedUsageDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 使用日を選択してください')),
      );
      return;
    }

    if (_daysUsedController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 使用日数を入力してください')),
      );
      return;
    }

    final daysUsed = double.tryParse(_daysUsedController.text);
    if (daysUsed == null || daysUsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 使用日数は0より大きい数値を入力してください')),
      );
      return;
    }

    await _repository.recordVacationUsage(
      widget.userId,
      _selectedUsageDate!,
      daysUsed,
      _reasonController.text.isEmpty ? null : _reasonController.text,
    );

    setState(() {
      _reasonController.clear();
      _daysUsedController.clear();
      _selectedUsageDate = null;
      _showAddForm = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 有給使用を記録しました')),
      );
      _loadData();
    }
  }

  // 使用履歴を削除
  Future<void> _deleteVacationUsage(String usageId) async {
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

    if (confirmed == true) {
      await _repository.deleteVacationUsage(usageId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 使用履歴を削除しました')),
        );
        _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('有給使用記録')),
        body: const Center(child: CircularProgressIndicator()),
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
                    
                    // 🌟 メインの残日数表示（新ロジック）
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('累計付与日数',
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('累計使用日数',
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
                        Column(
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
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 🌟 失効予定の警告セクション（新規追加）
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
                      TextField(
                        controller: _daysUsedController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: '使用日数（日）',
                          hintText: '例: 1 または 0.5（半日）',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          suffixIcon: const Icon(Icons.today),
                        ),
                      ),
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
                          title: Text(
                            DateFormat('M月d日(E)', 'ja_JP')
                                .format(usage.usageDate),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                '${usage.daysUsed.toStringAsFixed(1)}日使用',
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
                                _deleteVacationUsage(usage.id),
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
                  _daysUsedController.clear();
                  _selectedUsageDate = null;
                });
              },
              backgroundColor: Colors.red,
              child: const Icon(Icons.close),
            ),
    );
  }
}