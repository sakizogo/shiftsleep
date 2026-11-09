import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shiftsleep/models/vacation_model.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';
import 'package:shiftsleep/services/vacation_load_state.dart';  // N118 3/4 3b

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
  ({DateTime date, int days})? _nextAccrual;  // N63：次の付与日と付与日数（初回付与日が未登録なら null）
  DateTime? _carriedOverBaseDate;  // N80：持ち越しの基準日（対象の付与が有効なあいだだけ。説明に添える）
  // N118 3/4 3b：読み込みの状態。loaded 以外（読み込み中・失敗中）は値を変える・保存する操作を押せない
  VacationLoadState _loadState = VacationLoadState.loading;
  // N118 3/4 3b：再読み込み中（二度押し防止）
  bool _isReloading = false;

  bool get _canEdit => canEditVacationSettings(_loadState);

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
  /// N118 3/4 3b：読めたら（行がなかったときも）true。どれか 1 つでも読めなければ、画面全体を ❌ にして false
  /// （一部だけ読めた値は出さない。保存などのあとの読み直しで失敗したときも ❌ にする）
  Future<bool> _loadSettings() async {
    try {
      final settings = await _repository.getVacationSettings(widget.userId);
      final summary = await _repository.getAccrualSummary(widget.userId);

      // ========== Week 13追加: 持ち越し有休数を読み込む ==========
      final carriedOverDays = await _repository.getCarriedOverDays(widget.userId);
      // ===============================================================================

      // N80：持ち越しの基準日と、持ち越しの対象の付与が失効しているか
      final carryOver = await _repository.getCarryOver(widget.userId);
      final balance = await _repository.getVacationBalance(widget.userId);
      final carryOverTargets = balance.accruals.where((a) => a.isCarryOverTarget);
      final carryOverExpired = carryOverTargets.isNotEmpty && carryOverTargets.first.isExpired;

      // ========== Week 16追加: 初回付与日を読み込む ==========
      final firstAccrualDate = await _repository.getFirstAccrualDate(widget.userId);
      // ===============================================================================

      // N63：次の付与予定（DB の初回付与日から 1 年ごと）
      final nextAccrual = await _repository.getNextAccrual(widget.userId);

      // N118 3/4 3b（P8）：vacation_settings の行がなくても、持ち越し・初回付与日は欄に入れる
      final form = vacationFormValues(
        settings: settings,
        carriedOverDays: carriedOverDays,
        carryOver: carryOver,
        hasCarryOverTarget: carryOverTargets.isNotEmpty,
        carryOverExpired: carryOverExpired,
        firstAccrualDate: firstAccrualDate,
      );

      if (!mounted) return false;
      setState(() {
        _settings = settings;
        _summary = summary;
        _nextAccrual = nextAccrual;
        final hiredDate = form.hiredDate;
        final annualDaysText = form.annualDaysText;
        if (hiredDate != null) _selectedHiredDate = hiredDate;
        if (annualDaysText != null) _annualDaysController.text = annualDaysText;
        // N80：対象の付与が失効していたら空で表示する（画面を開いただけでは DB に書かない）
        _carriedOverBaseDate = form.carriedOverBaseDate;
        _carriedOverDaysController.text = form.carriedOverText;
        final firstAccrualDateText = form.firstAccrualDateText;
        if (firstAccrualDateText != null) _firstAccrualDateController.text = firstAccrualDateText;
        _loadState = VacationLoadState.loaded;
      });
      return true;
    } catch (e) {
      debugPrint('❌ N118 3/4 3b: 有給設定の読み込みに失敗: $e');
      if (mounted) {
        setState(() => _loadState = VacationLoadState.failed);
      }
      return false;
    }
  }

  /// N118 3/4 3b：［再読み込み］。成功したら通常の画面に戻る。結果は SnackBar でも知らせる（2c と同じ）
  Future<void> _reloadSettings() async {
    if (!canReloadVacationSettings(reloading: _isReloading)) return;
    final messenger = ScaffoldMessenger.of(context);  // await 前に取得
    setState(() => _isReloading = true);
    final bool succeeded;
    try {
      succeeded = await _loadSettings();
    } finally {
      if (mounted) setState(() => _isReloading = false);
    }
    if (!mounted) return;
    final message = vacationSettingsReloadMessage(succeeded: succeeded);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message.text),
        backgroundColor: message.color,
        duration: Duration(seconds: message.color == Colors.orange ? 6 : 2),
      ),
    );
  }

  /// N118 3/4 3b：読み込めなかったときの画面（AppBar の戻るボタンはそのまま使える）
  Widget _buildLoadFailedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              vacationSettingsLoadFailedTitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              vacationSettingsLoadFailedBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: canReloadVacationSettings(reloading: _isReloading) ? _reloadSettings : null,
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

  // 入社日をピッカーで選択
  Future<void> _selectHiredDate() async {
    if (!_canEdit) return;  // N118 3/4 3b
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedHiredDate ?? DateTime.now(),
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
    );

    if (!mounted) return;  // N118 3/4 3b
    if (pickedDate != null) {
      setState(() {
        _selectedHiredDate = pickedDate;
      });
    }
  }

  // 🌟 付与スケジュールを自動計算して DB に保存
Future<void> _generateAccrualSchedule() async {
  if (!_canEdit) return;  // N118 3/4 3b
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
    // 自動生成と同じく、今日までに来た付与日だけを並べる（N61）
    // 日数も保存と同じく、初回からの回数で法定の表を引く（N62・N63 の accrualsUntilToday）
    List<String> scheduleList = [];
    for (final accrual in VacationRepository.accrualsUntilToday(firstAccrualDate)) {
      final accrualDate = accrual.date;
      scheduleList.add('📅 ${accrualDate.year}年${accrualDate.month}月${accrualDate.day}日に${accrual.days}日付与');
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

    if (!mounted) return;  // N118 3/4 3b
    if (confirmed != true) return;

    // autoGenerateAccruals() を呼び出して DB に保存
    // N91：作った件数で文言を分ける。失敗しても途中まで作られていることがあるので、どの場合も画面を DB に合わせる
    final int createdCount;
    try {
      createdCount = await _repository.autoGenerateAccruals(
        widget.userId,
        _selectedHiredDate!,
        firstAccrualDate,
      );
    } catch (e) {
      debugPrint('❌ N91: 付与の自動生成に失敗: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ 付与の自動生成に失敗しました: $e\nもう一度押すと作ります'),
          duration: const Duration(seconds: 4),
        ),
      );
      _loadSettings();
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(createdCount > 0
            ? '✅ 付与を $createdCount 件作りました'
            : 'ℹ️ 付与はすべて登録済みです'),
        duration: const Duration(seconds: 2),
      ),
    );
    _loadSettings();
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
    if (!_canEdit) return;  // N118 3/4 3b：読み込めていないときは保存しない
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

    // N82：入社日がなければ保存しない（_selectedHiredDate! の例外を防ぐ）
    final hiredDate = _selectedHiredDate;
    if (hiredDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 入社日を選択してください')),
      );
      return;
    }

    // N82：初回付与日は保存の前に変換する（「2026年10月1日」形式。未入力なら保存しない）
    DateTime? firstAccrualDate;
    if (_firstAccrualDateController.text.isNotEmpty) {
      try {
        firstAccrualDate = DateFormat('yyyy年M月d日').parse(_firstAccrualDateController.text);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ 初回付与日を選び直してください')),
        );
        return;
      }
    }

    // N82：どれかが失敗したら成功を出さない。失敗したときは入力をそのまま残す
    // N84：持ち越しの基準日は DB の初回付与日から決まるので、初回付与日を先に保存する
    try {
      await _repository.saveVacationSettings(
        widget.userId,
        hiredDate,
        annualDays,
      );
      if (firstAccrualDate != null) {
        await _repository.saveFirstAccrualDate(widget.userId, firstAccrualDate);
      }
      await _repository.saveCarriedOverDays(widget.userId, carriedOverDays);
    } catch (e) {
      debugPrint('❌ N82: 有給設定の保存に失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 有給設定の保存に失敗しました: $e')),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 有給設定を保存しました')),
      );
      _loadSettings();
    }
  }

  // 付与日数を自動計算で更新
  Future<void> _recalculateAnnualDays() async {
    if (!_canEdit) return;  // N118 3/4 3b
    // N118 3/4 3b（P11）：失敗したら知らせて、画面を DB に合わせる
    try {
      await _repository.recalculateAnnualDays(widget.userId);
    } catch (e) {
      debugPrint('❌ N118 3/4 3b: 付与日数の自動計算に失敗: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 付与日数の自動計算に失敗しました: $e')),
      );
      _loadSettings();
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 付与日数を自動計算しました')),
      );
      _loadSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadState == VacationLoadState.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('有給設定')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    // N118 3/4 3b：読み込めなかったら画面全体を ❌ と［再読み込み］にする（フォームもボタンも出さない）
    if (_loadState == VacationLoadState.failed) {
      return Scaffold(
        appBar: AppBar(title: const Text('有給設定')),
        body: _buildLoadFailedView(),
      );
    }

    final yearsWorked = DateTime.now().year - (_selectedHiredDate?.year ?? 0);
    final autoCalculatedDays =
        VacationSettings.calculateAnnualDays(_selectedHiredDate ?? DateTime.now());
    
    // 次の付与予定日（N63：初回付与日から 1 年ごと。あと何日かは今日の 0 時から数える）
    final nextAccrual = _nextAccrual;
    final now = DateTime.now();
    final daysUntilNextAccrual = nextAccrual?.date
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;

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
            if (nextAccrual != null && daysUntilNextAccrual != null) ...[
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
                        '${DateFormat('yyyy年M月d日').format(nextAccrual.date)}（あと $daysUntilNextAccrual 日）',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${nextAccrual.days}日付与予定',
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
                    // N79：値が入っても何の日付か分かるように、見出しを固定で出す
                    Text(
                      '入社日',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
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
                      '※ 前年度から持ち越した有休がある場合は入力してください。\n入力しない場合は持ち越し有休は 0 日として計算されます。'
                      '${_carriedOverBaseDate != null ? '\nいまの持ち越しは ${DateFormat('yyyy/M/d').format(_carriedOverBaseDate!)} 時点の日数です。' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    // ===============================================================================
                    
                    // ========== Week 16 追加: 初回付与日入力欄 ==========
                    const SizedBox(height: 16),
                    // N79：見出しを固定で出す
                    Text(
                      '初回付与日',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (!_canEdit) return;  // N118 3/4 3b
                        // N79：入社日より前は選べないように。入社日がなければ 1980 年から
                        final firstDate = _selectedHiredDate ?? DateTime(1980);
                        final lastDate = DateTime.now().add(const Duration(days: 365));

                        // 最初に開く日：入力欄の日。なければ入社日の 6 か月後（入社日もなければ今日）
                        DateTime initialDate;
                        try {
                          initialDate = DateFormat('yyyy年M月d日').parse(_firstAccrualDateController.text);
                        } catch (_) {
                          final hired = _selectedHiredDate;
                          initialDate = hired != null
                              ? DateTime(hired.year, hired.month + 6, hired.day)
                              : DateTime.now();
                        }
                        // 範囲外だと showDatePicker が assert で落ちるので、範囲内に収める
                        if (initialDate.isBefore(firstDate)) initialDate = firstDate;
                        if (initialDate.isAfter(lastDate)) initialDate = lastDate;

                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: initialDate,
                          firstDate: firstDate,
                          lastDate: lastDate,
                        );

                        if (!mounted) return;  // N118 3/4 3b
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