import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';
import 'package:shiftsleep/services/vacation_calculation_service.dart';

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
  late GlobalKey<FormState> _formKey;
  late VacationRepository _repository;
  late TextEditingController _annualDaysController;
  late TextEditingController _carriedOverDaysController;  // ========== Week 13 追加 ==========
  late TextEditingController _firstAccrualDateController;  // ========== Week 16 追加 ==========
  
  DateTime? _selectedHiredDate;
  VacationSettings? _settings;
  VacationSummary? _summary;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _formKey = GlobalKey<FormState>();
    _repository = VacationRepository();
    _annualDaysController = TextEditingController();
    _carriedOverDaysController = TextEditingController();  // ========== Week 13 追加 ==========
    _firstAccrualDateController = TextEditingController();  // ========== Week 16 追加 ==========
    _loadSettings();
  }

  @override
  void dispose() {
    _annualDaysController.dispose();
    _carriedOverDaysController.dispose();  // ========== Week 13 追加 ==========
    _firstAccrualDateController.dispose();  // ========== Week 16 追加 ==========
    super.dispose();
  }

  // 設定を読み込む
  Future<void> _loadSettings() async {
    final settings = await _repository.getVacationSettings(widget.userId);
    final summary = await _repository.getAccrualSummary(widget.userId);
    
    // ========== Week 13追加: 持ち越し有休数を読み込む ==========
    final carriedOverDays = await _repository.getCarriedOverDays(widget.userId);
    // ===============================================================================
    
    // ========== Week 16追加: 初回付与日を読み込む ==========
    final firstAccrualDate = await _repository.getFirstAccrualDate(widget.userId);
    // ===============================================================================
    
    setState(() {
      _settings = settings;
      _summary = summary;
      if (settings != null) {
        _selectedHiredDate = settings.hiredDate;
        _annualDaysController.text = settings.annualDays.toString();
        
        // ========== Week 13追加: 持ち越し有休数を入力欄に反映 ==========
        if (carriedOverDays != null && carriedOverDays > 0) {
          _carriedOverDaysController.text = carriedOverDays.toStringAsFixed(0);
        } else {
          _carriedOverDaysController.text = '';  // 持ち越しがなければ空
        }
        // ===============================================================================
        
        // ========== Week 16追加: 初回付与日を入力欄に反映 ==========
        if (firstAccrualDate != null) {
          _firstAccrualDateController.text = DateFormat('yyyy年M月d日').format(firstAccrualDate);
        }
        // ===============================================================================
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

  // 🌟 付与スケジュールを自動計算して DB に保存
Future<void> _generateAccrualSchedule() async {
  if (_selectedHiredDate == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⚠️ 入社日を選択してください')),
    );
    return;
  }

  if (_firstAccrualDateController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⚠️ 初回付与日を入力してください')),
    );
    return;
  }

  try {
    // 初回付与日をパース
    final format = DateFormat('yyyy年M月d日');
    final firstAccrualDate = format.parse(_firstAccrualDateController.text);

    // 付与スケジュール情報を生成（DB保存なし、確認用）
    List<String> scheduleList = [];
    for (int i = 0; i < 5; i++) {
      final accrualDate = DateTime(
        firstAccrualDate.year + i,
        firstAccrualDate.month,
        firstAccrualDate.day,
      );
      
      final daysGranted = VacationRepository.calculateDaysGranted(
        _selectedHiredDate!,
        accrualDate,
      );

      if (daysGranted > 0) {
        scheduleList.add('📅 ${accrualDate.year}年${accrualDate.month}月${accrualDate.day}日に${daysGranted}日付与');
      }
    }

    if (scheduleList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 付与スケジュールが見つかりません')),
      );
      return;
    }

    // ダイアログで確認を取る
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('付与スケジュール自動生成'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '以下の付与スケジュールを生成します：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...scheduleList.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(item, style: const TextStyle(fontSize: 12)),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('生成', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // autoGenerateAccruals() を呼び出して DB に保存
    await _repository.autoGenerateAccruals(
      widget.userId,
      _selectedHiredDate!,
      firstAccrualDate,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ 付与スケジュールを自動生成しました'),
          duration: Duration(seconds: 2),
        ),
      );
      _loadSettings();
    }
  } catch (e) {
    print('❌ Error generating accruals: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ エラー: $e')),
      );
    }
  }
}
  // 設定を保存
  Future<void> _saveVacationSettings() async {
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      return;
    }

    final annualDays = int.tryParse(_annualDaysController.text);

    if (annualDays == null || annualDays < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 付与日数は0以上の整数を入力してください')),
      );
      return;
    }

    // ========== Week 13 追加: 持ち越し有休数を取得 ==========
    final carriedOverDays = int.tryParse(_carriedOverDaysController.text) ?? 0;
    if (carriedOverDays < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 持ち越し有休数は0以上の整数を入力してください')),
      );
      return;
    }
    // ===============================================================================

    await _repository.saveVacationSettings(
      widget.userId,
      _selectedHiredDate!,
      annualDays,
    );

    // ========== Week 13 追加: 持ち越し有休数を DB に保存 ==========
        // ========== Week 13 追加: 持ち越し有休数を DB に保存 ==========
    await _repository.saveCarriedOverDays(widget.userId, carriedOverDays);
    // ===============================================================================

    // ========== Week 16 追加: 初回付与日を DB に保存 ==========
    if (_firstAccrualDateController.text.isNotEmpty) {
      try {
        final firstAccrualDateStr = _firstAccrualDateController.text;
        // 「2026年10月1日」形式から DateTime に変換
        final format = DateFormat('yyyy年M月d日');
        final firstAccrualDate = format.parse(firstAccrualDateStr);
        
        await _repository.saveFirstAccrualDate(widget.userId, firstAccrualDate);
      } catch (e) {
        print('❌ Error parsing first accrual date: $e');
      }
    }
    // ===============================================================================

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
    
    // 次の付与予定日を計算
    final nextAccrualDate = _selectedHiredDate != null
        ? VacationCalculationService.getNextAccrualDate(_selectedHiredDate!)
        : null;
    
    final daysUntilNextAccrual = _selectedHiredDate != null
        ? VacationCalculationService.getDaysUntilNextAccrual(_selectedHiredDate!)
        : null;

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

            // 🌟 次の付与予定を表示（新規追加）
            if (nextAccrualDate != null && daysUntilNextAccrual != null) ...[
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.blue.shade300, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📅 次の付与予定',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        DateFormat('yyyy年M月d日').format(nextAccrualDate),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'あと $daysUntilNextAccrual 日で新しい有給が付与されます',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 🌟 失効予定の警告（新規追加）
            if (_summary != null && _summary!.expiryWarningMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _summary!.expiryWarningMessage!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
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
                    const SizedBox(height: 16),
                    
                    // ========== Week 13 追加: 持ち越し有休数入力欄 ==========
                     TextField(
                      controller: _carriedOverDaysController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '前年度持ち越し有休数（日）',
                        hintText: '例: 5',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixIcon: const Icon(Icons.history),
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      '※ 前年度から持ち越した有休がある場合は入力してください。\n入力しない場合は持ち越し有休は 0 日として計算されます。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    // ===============================================================================
                    
                    // ========== Week 16 追加: 初回付与日入力欄 ==========
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        
                        if (pickedDate != null) {
                          setState(() {
                            _firstAccrualDateController.text = DateFormat('yyyy年M月d日').format(pickedDate);
                          });
                        }
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        _firstAccrualDateController.text.isEmpty
                            ? '初回付与日を選択'
                            : _firstAccrualDateController.text,
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      '※ 入社6ヶ月後の初回付与日を選択してください。\n以降は毎年同月同日に1年ごとに付与されます。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    // ===============================================================================
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
            
            // 🌟 付与スケジュール自動生成ボタン（新規追加）
            if (_selectedHiredDate != null)
              ElevatedButton(
                onPressed: _generateAccrualSchedule,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: Colors.green,
                ),
                child: const Text(
                  '⚡ 付与スケジュールを自動生成',
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