// ホームの「次のシフトに合わせた睡眠の目安」のカード（A-3 2/3）
//
// - 読み込み（SleepPlanLoader）：initState・アプリに戻ったとき（resume）・［再読み込み］
// - 計算（buildSleepPlanCardModel）：分が変わったときと SleepProvider が変わったときだけ（ホームの 1 秒ごとの描き直しでは計算しない）
// - 無料：見出し・目安・状態・一言・寝方のタイプ。プレミアム：理由・仮眠など・3 日分（たためる。最初は理由だけ開く）
// - 無料の 🔒 を押すと、改善アドバイスと同じダイアログ（showPremiumLockDialog）
// - 色は Wong 2011（夜の目安は青 0072B2、⚠️ はオレンジ E69F00）。色だけに頼らず文字とアイコンも付ける
import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/services/sleep_plan.dart';
import 'package:shiftsleep/services/sleep_plan_card_model.dart';
import 'package:shiftsleep/services/sleep_plan_loader.dart';
import 'package:shiftsleep/services/sleep_style_preference_service.dart';
import 'package:shiftsleep/widgets/premium_lock_dialog.dart';

/// 夜の目安の色（Wong 2011: Blue）
const Color sleepPlanAccentColor = Color(0xFF0072B2);

/// ⚠️ の色（Wong 2011: Orange）
const Color sleepPlanWarningColor = Color(0xFFE69F00);

/// 読み込み中の文
const String sleepPlanLoadingText = '⏳ 準備しています…';

/// カードの見出し（読み込み中・失敗のとき）
const String sleepPlanCardTitle = '睡眠の目安';

/// 🔒 の文字（鍵はアイコンで出すので、文字には付けない。F1）
const String sleepPlanPremiumLabel = 'プレミアム';

/// 寝方のタイプを保存できなかったときの文
const String sleepStyleSaveFailedText = '⚠️ 寝方のタイプを保存できませんでした';

/// D72：未確定のシフトがあるときの一言（カードは確定したシフトだけを使う。アイコンで出すので 📝 は付けない。F2）
const String sleepPlanDraftPendingText = '未確定のシフトがあります。確定すると目安に反映されます';

/// 寝方のタイプのシートの見出し
const String sleepStyleSheetTitle = '寝方のタイプ';

/// たためる部分の見出し
const String sleepPlanReasonsTitle = 'なぜこの目安？';
const String sleepPlanExtrasTitle = '仮眠など';
const String sleepPlanDaysTitle = '3 日分';

/// シートでの寝方のタイプの名前
String sleepStylePreferenceLabel(SleepStylePreference preference) {
  switch (preference) {
    case SleepStylePreference.auto:
      return '自動（これまでの記録から）';
    case SleepStylePreference.immediate:
      return '帰ってすぐ寝る';
    case SleepStylePreference.lastMinute:
      return '出勤ぎりぎりまで寝る';
  }
}

class SleepPlanCard extends StatefulWidget {
  const SleepPlanCard({
    super.key,
    this.loader,
    this.savePreference,
    this.clock,
    this.tick = const Duration(seconds: 20),
    this.pendingDraftCount,
  });

  /// D72：未確定のシフトの日数（home_screen の ShiftDraftStore.pendingCount。シフト管理タブのバッジと同じ値）
  /// 1 以上なら「未確定のシフトがあります」の一言を出す。null なら出さない
  final ValueListenable<int>? pendingDraftCount;

  /// 読み込み（テストで差し替える）。null なら SleepPlanLoader()
  final SleepPlanLoader? loader;

  /// 寝方のタイプの保存（テストで差し替える）。null なら SleepStylePreferenceService.save
  final Future<void> Function(SleepStylePreference preference)? savePreference;

  /// 今の時刻（テストで差し替える）。null なら DateTime.now
  final DateTime Function()? clock;

  /// 分が変わったかを確かめる間隔（null なら確かめない。テスト用）
  final Duration? tick;

  @override
  State<SleepPlanCard> createState() => _SleepPlanCardState();
}

class _SleepPlanCardState extends State<SleepPlanCard> with WidgetsBindingObserver {
  late final SleepPlanLoader _loader = widget.loader ?? SleepPlanLoader();

  SleepPlanInputs? _inputs;
  bool _loading = true;
  int _loadSeq = 0;
  Timer? _ticker;

  /// 計算の結果と、そのときの材料（材料が同じなら計算し直さない）
  Object? _modelKey;
  SleepPlanCardModel? _model;
  int? _shownMinute;

  bool _reasonsOpen = true;
  bool _extrasOpen = false;
  bool _daysOpen = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  static int _minuteKey(DateTime time) =>
      DateTime(time.year, time.month, time.day, time.hour, time.minute).millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.pendingDraftCount?.addListener(_onDraftCountChanged);
    _load(initial: true);
    final tick = widget.tick;
    if (tick != null) {
      _ticker = Timer.periodic(tick, (_) {
        if (mounted && _minuteKey(_now()) != _shownMinute) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(SleepPlanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pendingDraftCount != widget.pendingDraftCount) {
      oldWidget.pendingDraftCount?.removeListener(_onDraftCountChanged);
      widget.pendingDraftCount?.addListener(_onDraftCountChanged);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.pendingDraftCount?.removeListener(_onDraftCountChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onDraftCountChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasPendingDraft => (widget.pendingDraftCount?.value ?? 0) > 0;

  Widget _draftPendingRow() {
    return const Padding(
      padding: EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.edit_note, color: sleepPlanAccentColor, size: 18),
          SizedBox(width: 6),
          Expanded(child: Text(sleepPlanDraftPendingText, style: TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  Future<void> _load({bool initial = false}) async {
    final seq = ++_loadSeq;
    if (!initial) setState(() => _loading = true);
    SleepPlanInputs inputs;
    try {
      inputs = await _loader.load(_now());
    } catch (e) {
      debugPrint('❌ [SleepPlanCard] 睡眠の目安の材料を読めませんでした: $e');
      inputs = const SleepPlanInputs(
        shifts: null,
        alarmMinutesBefore: defaultAlarmMinutesBefore,
        settingsFailed: false,
        preference: SleepStylePreference.auto,
      );
    }
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _inputs = inputs;
      _loading = false;
    });
  }

  SleepPlanCardModel? _modelFor(SleepProvider provider, SleepPlanInputs? inputs) {
    if (inputs == null) return null;
    final now = _now();
    final minute = _minuteKey(now);
    final sleepingSince = provider.isSleepingNow ? provider.sleepStartTime : null;
    final key = (
      inputs,
      minute,
      provider.last30DaysRecords,
      provider.sleepDataLoadFailed,
      provider.isPremiumUser,
      provider.advicePromoVisible,
      sleepingSince,
    );
    if (key != _modelKey || _model == null) {
      _model = buildSleepPlanCardModel(
        inputs: inputs,
        records: provider.last30DaysRecords,
        recordsFailed: provider.sleepDataLoadFailed,
        now: now,
        isPremium: provider.isPremiumUser,
        advicePromoVisible: provider.advicePromoVisible,
        sleepingSince: sleepingSince,
      );
      _modelKey = key;
    }
    _shownMinute = minute;
    return _model;
  }

  Future<void> _changeStyle() async {
    final inputs = _inputs;
    if (inputs == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showModalBottomSheet<SleepStylePreference>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(sleepStyleSheetTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            for (final preference in SleepStylePreference.values)
              ListTile(
                leading: Icon(
                  preference == inputs.preference ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: sleepPlanAccentColor,
                ),
                title: Text(sleepStylePreferenceLabel(preference)),
                onTap: () => Navigator.of(sheetContext).pop(preference),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      await (widget.savePreference ?? SleepStylePreferenceService.save)(choice);
    } catch (e) {
      debugPrint('❌ [SleepPlanCard] 寝方のタイプを保存できませんでした: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text(sleepStyleSaveFailedText), backgroundColor: Colors.orange),
      );
      return;
    }
    if (!mounted) return;
    final current = _inputs;
    if (current == null) return;
    setState(() {
      _inputs = SleepPlanInputs(
        shifts: current.shifts,
        alarmMinutesBefore: current.alarmMinutesBefore,
        settingsFailed: current.settingsFailed,
        preference: choice,
      );
    });
  }

  void _showPremiumLock() {
    showPremiumLockDialog(
      context,
      title: sleepPlanCardTitle,
      message: sleepPlanPremiumTeaserText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SleepProvider>();
    final model = _loading && _inputs == null ? null : _modelFor(provider, _inputs);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: sleepPlanAccentColor.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _loading || model == null ? _buildLoading() : _buildBody(model),
    );
  }

  Widget _buildLoading() {
    return const Row(
      children: [
        Icon(Icons.bedtime, color: sleepPlanAccentColor, size: 20),
        SizedBox(width: 8),
        Text(sleepPlanCardTitle, style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(width: 12),
        Expanded(child: Text(sleepPlanLoadingText, style: TextStyle(color: Colors.black54))),
      ],
    );
  }

  Widget _warningRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: sleepPlanWarningColor, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildBody(SleepPlanCardModel model) {
    switch (model.state) {
      case SleepPlanCardState.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bedtime, color: sleepPlanAccentColor, size: 20),
                SizedBox(width: 8),
                Text(sleepPlanCardTitle, style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            for (final warning in model.warnings) _warningRow(warning),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('再読み込み'),
              ),
            ),
          ],
        );
      case SleepPlanCardState.noShift:
        final text = model.text!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_available, color: sleepPlanAccentColor, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('${text.headline}。${text.subline ?? ''}', style: const TextStyle(fontSize: 13))),
              ],
            ),
            for (final warning in model.warnings) _warningRow(warning),
            if (_hasPendingDraft) _draftPendingRow(),
          ],
        );
      case SleepPlanCardState.ready:
        return _buildReady(model);
    }
  }

  Widget _buildReady(SleepPlanCardModel model) {
    final text = model.text!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bedtime, color: sleepPlanAccentColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text.headline, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
        if (text.subline != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 28),
            child: Text(text.subline!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
        for (final warning in model.warnings) _warningRow(warning),
        if (_hasPendingDraft) _draftPendingRow(),
        if (text.mainLine != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(text.mainLine!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        if (text.freeNapLine != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('💤 ${text.freeNapLine!}', style: const TextStyle(fontSize: 13)),
          ),
        for (final line in text.statusLines)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(line, style: const TextStyle(fontSize: 13)),
          ),
        if (text.styleNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(child: Text(text.styleNote!, style: const TextStyle(fontSize: 12, color: Colors.black54))),
                TextButton(onPressed: _changeStyle, child: const Text('変える ›')),
              ],
            ),
          ),
        if (model.fewRecordsLine != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(model.fewRecordsLine!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(text.reassurance, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ),
        if (!model.premiumLocked) ..._buildPremium(model),
        if (model.premiumLocked && model.showPremiumTeaser) _buildTeaser(),
      ],
    );
  }

  List<Widget> _buildPremium(SleepPlanCardModel model) {
    return [
      if (model.premiumReasonLines.isNotEmpty)
        _section(
          title: sleepPlanReasonsTitle,
          open: _reasonsOpen,
          onToggle: () => setState(() => _reasonsOpen = !_reasonsOpen),
          children: [for (final line in model.premiumReasonLines) Text('・$line', style: const TextStyle(fontSize: 12))],
        ),
      if (model.premiumExtraLines.isNotEmpty)
        _section(
          title: sleepPlanExtrasTitle,
          open: _extrasOpen,
          onToggle: () => setState(() => _extrasOpen = !_extrasOpen),
          children: [for (final line in model.premiumExtraLines) Text(line, style: const TextStyle(fontSize: 12))],
        ),
      if (model.premiumDays.isNotEmpty)
        _section(
          title: sleepPlanDaysTitle,
          open: _daysOpen,
          onToggle: () => setState(() => _daysOpen = !_daysOpen),
          children: [
            for (final day in model.premiumDays) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(day.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              for (final line in day.lines)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(line, style: const TextStyle(fontSize: 12)),
                ),
            ],
          ],
        ),
    ];
  }

  Widget _section({
    required String title,
    required bool open,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              children: [
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 20, color: sleepPlanAccentColor),
                const SizedBox(width: 4),
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
        ],
      ),
    );
  }

  Widget _buildTeaser() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: _showPremiumLock,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock, size: 18, color: Colors.grey),
                  SizedBox(width: 6),
                  Text(sleepPlanPremiumLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              SizedBox(height: 4),
              Text(sleepPlanPremiumTeaserText, style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
