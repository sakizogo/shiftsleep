import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';

class VacationSettingsScreen extends StatefulWidget {
  final String userId;

  const VacationSettingsScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<VacationSettingsScreen> createState() =>
      _VacationSettingsScreenState();
}

class _VacationSettingsScreenState extends State<VacationSettingsScreen> {
  late VacationRepository _repository;
  late TextEditingController _annualDaysController;
  
  DateTime? _selectedHiredDate;
  VacationSettings? _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _repository = VacationRepository();
    _annualDaysController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _annualDaysController.dispose();
    super.dispose();
  }

  // 設定を読み込む
  Future<void> _loadSettings() async {
    final settings = await _repository.getVacationSettings(widget.userId);
    setState(() {
      _settings = settings;
      if (settings != null) {
        _selectedHiredDate = settings.hiredDate;
        _annualDaysController.text = settings.annualDays.toString();
      }
      _isLoading = false;
    });
  }

  // 入社日をピッカーで選択
  Future<void> _selectHiredDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedHiredDate ?? DateTime.now(),
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedHiredDate = pickedDate;
      });
    }
  }

  // 設定を保存
  Future<void> _saveVacationSettings() async {
    if (_selectedHiredDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 入社日を選択してください')),
      );
      return;
    }

    if (_annualDaysController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 付与日数を入力してください')),
      );
      return;
    }

    final annualDays = int.tryParse(_annualDaysController.text);
    if (annualDays == null || annualDays < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 付与日数は0以上の整数を入力してください')),
      );
      return;
    }

    await _repository.saveVacationSettings(
      widget.userId,
      _selectedHiredDate!,
      annualDays,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 有給設定を保存しました')),
      );
      _loadSettings();
    }
  }

  // 付与日数を自動計算で更新
  Future<void> _recalculateAnnualDays() async {
    await _repository.recalculateAnnualDays(widget.userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 付与日数を自動計算しました')),
      );
      _loadSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('有給設定')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final yearsWorked = DateTime.now().year - (_selectedHiredDate?.year ?? 0);
    final autoCalculatedDays =
        VacationSettings.calculateAnnualDays(_selectedHiredDate ?? DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('有給設定'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 📊 現在の有給情報サマリー
            if (_settings != null) ...[
              Card(
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
                        '📊 現在の有給情報',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('入社日',
                                  style: TextStyle(color: Colors.grey)),
                              Text(
                                DateFormat('yyyy年M月d日')
                                    .format(_settings!.hiredDate),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('勤続年数',
                                  style: TextStyle(color: Colors.grey)),
                              Text(
                                '$yearsWorked年',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('今年の付与日数',
                                  style: TextStyle(color: Colors.grey)),
                              Text(
                                '${_settings!.annualDays}日',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('自動計算結果',
                                  style: TextStyle(color: Colors.grey)),
                              Text(
                                '$autoCalculatedDays日',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (_settings!.manualOverride)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '🔧 手入力で修正されています',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 🎨 フォームセクション
            Card(
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
                      '📝 設定を編集',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _selectHiredDate,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        _selectedHiredDate == null
                            ? '入社日を選択'
                            : DateFormat('yyyy年M月d日')
                                .format(_selectedHiredDate!),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _annualDaysController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '付与日数（日）',
                        hintText: '例: 10',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixIcon: const Icon(Icons.today),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 🔘 ボタンセクション
            ElevatedButton(
              onPressed: _saveVacationSettings,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: Colors.blue,
              ),
              child: const Text(
                '💾 設定を保存',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_settings != null && _settings!.manualOverride)
              OutlinedButton(
                onPressed: _recalculateAnnualDays,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text(
                  '🔄 自動計算に戻す',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}