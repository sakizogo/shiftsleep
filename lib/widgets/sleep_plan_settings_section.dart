// 設定画面の「😴 睡眠の目安」セクション（A-4 2/3）
//
// - 通勤（片道）・身支度・パターンごとのいつもの残業・寝方のタイプ。どれも任意で、未設定に戻せる
// - 選べる値は D76（sleep_plan_settings_service.dart の choices）。選んだらすぐ保存して SnackBar（保存ボタンはない）
// - 保存できなかったときは「⚠️ …を保存できませんでした」だけを出し、$e は debugPrint にだけ出す
// - 残業は出勤（work）のパターンだけ並べる（休日・有休・半休・削除済みは出さない）
// - 寝方のタイプはホームのカードと同じシート（showSleepStyleSheet）。自動のときは判定結果を出さず「自動」とだけ出す
// - ⓘ アラーム：出勤前アラーム（設定画面で今選んでいる分数）が、通勤・身支度から出した起きる目安より遅いときだけ
// - 色は Wong 2011（ⓘ は青 0072B2、⚠️ はオレンジ E69F00）。色だけに頼らずアイコンと文字も付ける
import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/services/sleep_plan.dart';
import 'package:shiftsleep/services/sleep_plan_settings_service.dart';
import 'package:shiftsleep/services/sleep_style_preference_service.dart';
import 'package:shiftsleep/widgets/sleep_plan_card.dart';

/// セクションの見出し
const String sleepPlanSettingsTitle = '😴 睡眠の目安';

/// 但し書き
const String sleepPlanSettingsNote = '登録すると、睡眠の目安がより実際に近くなります。どれも未設定のままで使えます';

/// ⓘ 残業（D79 C）
const String sleepPlanOvertimeInfo = '残業は勤務の終わりを延ばさず、帰ってから寝られるまでの時間に足して目安を出します';

/// 出勤のパターンがないときの文
const String sleepPlanNoWorkPatternText = '出勤のパターンがまだありません';

/// パターンを読めなかったときの文（⚠️ はアイコンで出すので、文字には付けない）
const String sleepPlanPatternsLoadFailedText = 'パターンを読めなかったため、残業は設定できません';

/// 通勤・身支度の未設定の名前
const String sleepPlanUnsetLabel = '未設定';

/// 残業の未設定の名前
const String sleepPlanNoOvertimeLabel = 'なし';

/// ドロップダウンで「未設定・なし」を表す値（D76 の選べる値に 0 はない）
const int _unsetMinutes = 0;

/// 分の表示（例：30 分・1 時間・1 時間 30 分）
String sleepPlanMinutesLabel(Duration duration) {
  final hours = duration.inMinutes ~/ 60;
  final minutes = duration.inMinutes % 60;
  if (hours == 0) return '$minutes 分';
  if (minutes == 0) return '$hours 時間';
  return '$hours 時間 $minutes 分';
}

/// 設定画面での寝方のタイプの表示（自動のときは判定結果を出さず「自動」とだけ）
String sleepStyleSettingLabel(SleepStylePreference preference) =>
    preference == SleepStylePreference.auto ? '自動' : sleepStylePreferenceLabel(preference);

/// 残業を設定できるパターン（出勤のパターンだけ。休日・有休・半休・削除済みは外す）
List<ShiftPatternModel> overtimeTargetPatterns(List<ShiftPatternModel> patterns) =>
    [for (final pattern in patterns) if (!pattern.isDeleted && pattern.patternType == ShiftType.work) pattern];

/// ⓘ アラームを出すか（判定は SleepPlanOptions.wakesBeforeAlarm。理由の文と同じ判定）
/// - 起きる目安は「出勤 − 前置き L」（通勤・身支度の合計）、出勤前アラームは「出勤 − 分数」
/// - アラームのほうが遅いときだけ出す。同じ時刻・未設定・アラームが無効なら出さない
bool shouldShowSleepPlanAlarmInfo({
  required int alarmMinutesBefore,
  required Duration? commute,
  required Duration? prep,
}) =>
    SleepPlanOptions(alarmMinutesBefore: alarmMinutesBefore, commute: commute, prep: prep).wakesBeforeAlarm;

/// ⓘ アラームの文
String sleepPlanAlarmInfoText({required Duration? commute, required Duration? prep}) {
  final lead = (commute ?? Duration.zero) + (prep ?? Duration.zero);
  return '出勤前アラームが、通勤と身支度から出した起きる目安（出勤の ${sleepPlanMinutesLabel(lead)}前ごろ）より遅く鳴ります';
}

class SleepPlanSettingsSection extends StatefulWidget {
  const SleepPlanSettingsSection({
    super.key,
    required this.alarmMinutesBefore,
    this.loadSettings,
    this.loadPatterns,
    this.loadPreference,
    this.saveCommute,
    this.savePrep,
    this.saveOvertime,
    this.savePreference,
  });

  /// 設定画面で今選んでいる出勤前アラームの分数（_alarmTimeBeforeShift。0 は無効）
  final int alarmMinutesBefore;

  /// テストで差し替える。null なら各サービス・ShiftRepository
  final Future<SleepPlanSettings> Function()? loadSettings;
  final Future<List<ShiftPatternModel>> Function()? loadPatterns;
  final Future<SleepStylePreference> Function()? loadPreference;
  final Future<void> Function(Duration? commute)? saveCommute;
  final Future<void> Function(Duration? prep)? savePrep;
  final Future<void> Function(String patternId, Duration? overtime)? saveOvertime;
  final Future<void> Function(SleepStylePreference preference)? savePreference;

  @override
  State<SleepPlanSettingsSection> createState() => _SleepPlanSettingsSectionState();
}

class _SleepPlanSettingsSectionState extends State<SleepPlanSettingsSection> {
  bool _loading = true;
  bool _saving = false;
  bool _patternsFailed = false;
  Duration? _commute;
  Duration? _prep;
  Map<String, Duration> _overtime = const {};
  List<ShiftPatternModel> _patterns = const [];
  SleepStylePreference _preference = SleepStylePreference.auto;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var settings = SleepPlanSettings.none;
    try {
      settings = await (widget.loadSettings ?? SleepPlanSettingsService.load)();
    } catch (e) {
      debugPrint('❌ [SleepPlanSettingsSection] 通勤・身支度・残業の設定を読めなかったため、未設定で出します: $e');
    }
    var patterns = <ShiftPatternModel>[];
    var patternsFailed = false;
    try {
      patterns = overtimeTargetPatterns(await (widget.loadPatterns ?? ShiftRepository().getAllPatterns)());
    } catch (e) {
      debugPrint('❌ [SleepPlanSettingsSection] パターンを読めませんでした: $e');
      patternsFailed = true;
    }
    var preference = SleepStylePreference.auto;
    try {
      preference = await (widget.loadPreference ?? SleepStylePreferenceService.load)();
    } catch (e) {
      debugPrint('❌ [SleepPlanSettingsSection] 寝方のタイプを読めなかったため、自動で出します: $e');
    }
    if (!mounted) return;
    setState(() {
      _commute = settings.commute;
      _prep = settings.prep;
      _overtime = settings.overtimeByPattern;
      _patterns = patterns;
      _patternsFailed = patternsFailed;
      _preference = preference;
      _loading = false;
    });
  }

  /// 保存して SnackBar を出す。保存できたら true
  Future<bool> _save(String label, Future<void> Function() save) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await save();
    } catch (e) {
      debugPrint('❌ [SleepPlanSettingsSection] $labelを保存できませんでした: $e');
      if (mounted) setState(() => _saving = false);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('⚠️ $labelを保存できませんでした'), backgroundColor: sleepPlanWarningColor),
      );
      return false;
    }
    if (mounted) setState(() => _saving = false);
    // 続けて選んだとき、前の SnackBar が残って新しいものが待たされないように閉じる
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('✅ $labelを保存しました')));
    return true;
  }

  Future<void> _changeCommute(int minutes) async {
    final value = minutes == _unsetMinutes ? null : Duration(minutes: minutes);
    if (await _save('通勤', () => (widget.saveCommute ?? SleepPlanSettingsService.saveCommute)(value)) && mounted) {
      setState(() => _commute = value);
    }
  }

  Future<void> _changePrep(int minutes) async {
    final value = minutes == _unsetMinutes ? null : Duration(minutes: minutes);
    if (await _save('身支度', () => (widget.savePrep ?? SleepPlanSettingsService.savePrep)(value)) && mounted) {
      setState(() => _prep = value);
    }
  }

  Future<void> _changeOvertime(ShiftPatternModel pattern, int minutes) async {
    final value = minutes == _unsetMinutes ? null : Duration(minutes: minutes);
    final saved = await _save(
      '残業（${pattern.patternName}）',
      () => (widget.saveOvertime ?? SleepPlanSettingsService.saveOvertime)(pattern.id, value),
    );
    if (saved && mounted) {
      setState(() {
        final next = Map<String, Duration>.of(_overtime);
        if (value == null) {
          next.remove(pattern.id);
        } else {
          next[pattern.id] = value;
        }
        _overtime = next;
      });
    }
  }

  Future<void> _changeStyle() async {
    final choice = await showSleepStyleSheet(context, _preference);
    if (choice == null || !mounted) return;
    if (await _save('寝方のタイプ', () => (widget.savePreference ?? SleepStylePreferenceService.save)(choice)) &&
        mounted) {
      setState(() => _preference = choice);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(sleepPlanSettingsTitle, style: AppTextStyles.sectionTitleStyle),
        const SizedBox(height: AppDimensions.paddingMedium),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDimensions.paddingMedium),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.borderDefault),
            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
          ),
          child: _loading ? const Text(sleepPlanLoadingText) : _buildBody(),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sleepPlanSettingsNote,
          style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: AppDimensions.paddingMedium),
        _itemTitle('通勤（片道）'),
        _minutesDropdown(
          key: const ValueKey('sleepPlanCommute'),
          current: _commute,
          choices: commuteMinuteChoices,
          unsetLabel: sleepPlanUnsetLabel,
          onChanged: _changeCommute,
        ),
        const SizedBox(height: AppDimensions.paddingMedium),
        _itemTitle('身支度'),
        _minutesDropdown(
          key: const ValueKey('sleepPlanPrep'),
          current: _prep,
          choices: prepMinuteChoices,
          unsetLabel: sleepPlanUnsetLabel,
          onChanged: _changePrep,
        ),
        if (shouldShowSleepPlanAlarmInfo(alarmMinutesBefore: widget.alarmMinutesBefore, commute: _commute, prep: _prep))
          _infoRow(sleepPlanAlarmInfoText(commute: _commute, prep: _prep), key: const ValueKey('sleepPlanAlarmInfo')),
        const SizedBox(height: AppDimensions.paddingLarge),
        _itemTitle('いつもの残業'),
        _infoRow(sleepPlanOvertimeInfo),
        if (_patternsFailed)
          _warningRow(sleepPlanPatternsLoadFailedText)
        else if (_patterns.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(sleepPlanNoWorkPatternText, style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 12)),
          )
        else
          for (final pattern in _patterns)
            Row(
              children: [
                Expanded(child: Text(pattern.patternName, style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 13))),
                const SizedBox(width: AppDimensions.paddingSmall),
                Expanded(
                  child: _minutesDropdown(
                    key: ValueKey('sleepPlanOvertime_${pattern.id}'),
                    current: _overtime[pattern.id],
                    choices: overtimeMinuteChoices,
                    unsetLabel: sleepPlanNoOvertimeLabel,
                    onChanged: (minutes) => _changeOvertime(pattern, minutes),
                  ),
                ),
              ],
            ),
        const SizedBox(height: AppDimensions.paddingLarge),
        _itemTitle(sleepStyleSheetTitle),
        Row(
          children: [
            Expanded(
              child: Text(
                sleepStyleSettingLabel(_preference),
                key: const ValueKey('sleepPlanStyleLabel'),
                style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 13),
              ),
            ),
            TextButton(onPressed: _saving ? null : _changeStyle, child: const Text('変える ›')),
          ],
        ),
      ],
    );
  }

  Widget _itemTitle(String text) {
    return Text(text, style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w600, fontSize: 14));
  }

  Widget _minutesDropdown({
    required Key key,
    required Duration? current,
    required List<int> choices,
    required String unsetLabel,
    required ValueChanged<int> onChanged,
  }) {
    final value = current?.inMinutes ?? _unsetMinutes;
    return DropdownButton<int>(
      key: key,
      value: choices.contains(value) ? value : _unsetMinutes,
      isExpanded: true,
      items: [
        DropdownMenuItem(value: _unsetMinutes, child: Text(unsetLabel)),
        for (final minutes in choices)
          DropdownMenuItem(value: minutes, child: Text(sleepPlanMinutesLabel(Duration(minutes: minutes)))),
      ],
      onChanged: _saving
          ? null
          : (minutes) {
              if (minutes != null && minutes != value) onChanged(minutes);
            },
    );
  }

  Widget _infoRow(String text, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: sleepPlanAccentColor, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
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
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
