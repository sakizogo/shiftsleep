import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsleep/services/alarm_permission.dart';
import 'package:shiftsleep/services/alarm_ringing.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/manual_wake_service.dart';
import 'package:shiftsleep/services/pre_alarm_reschedule_service.dart';
import 'package:shiftsleep/services/shift_draft.dart';
import 'package:shiftsleep/services/sleep_preference_service.dart';
import 'package:shiftsleep/services/sleep_advisory_service.dart';  // N186
import 'package:shiftsleep/services/sleep_debt.dart';  // N198 2/2
import 'package:shiftsleep/services/sleep_record_kind.dart';  // N199：formatSleepDuration
import 'package:shiftsleep/services/medical_consult_dismiss_store.dart';  // N202
import 'package:shiftsleep/services/tab_snackbar.dart';  // N190
import '../constants/colors.dart';
import '../constants/text_styles.dart';
import '../constants/dimensions.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/screens/advice_detail_screen.dart';
import 'package:shiftsleep/services/wake_up_service.dart';
import 'package:shiftsleep/screens/settings_screen_latest.dart';
import 'package:shiftsleep/screens/edit_sleep_record_screen.dart';
import 'package:shiftsleep/screens/shift_management_screen.dart';
import 'package:shiftsleep/screens/shift_pattern_screen.dart';
import 'package:shiftsleep/screens/sleep_records_screen.dart';
import 'package:shiftsleep/screens/shift_detail_screen.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/widgets/action_tip_locked_label.dart';  // P1
import 'package:shiftsleep/widgets/sleep_button.dart';
import 'package:shiftsleep/widgets/sleep_plan_card.dart';  // A-3 3/3

// Week 3 Day 5: シフト管理画面内の詳細状態管理
enum ShiftManagementView { calendar, details }

/// N198 2/2：睡眠負債のカードの色（背景・枠・文字）
class SleepDebtCardColors {
  final Color background;
  final Color border;
  final Color text;

  const SleepDebtCardColors({required this.background, required this.border, required this.text});
}

/// N198 2/2：段階ごとの色。1 型色覚でも区別できるよう赤と緑は使わず、明るさも変える（Wong 2011）
/// - 要注意：朱色系（枠 #D55E00）、改善推奨：オレンジ系（枠 #E69F00）、少し不足・十分・判定できない：灰色系
/// - 文字は背景との明るさの差を 4.5:1 以上にする（評価の文字と必ず一緒に出す）
SleepDebtCardColors sleepDebtCardColors(SleepDebtLevel level) {
  switch (level) {
    case SleepDebtLevel.alert:
      return const SleepDebtCardColors(
        background: Color(0xFFFDF0E6),
        border: Color(0xFFD55E00),
        text: Color(0xFF9A3F00),
      );
    case SleepDebtLevel.improve:
      return const SleepDebtCardColors(
        background: Color(0xFFFFF7E6),
        border: Color(0xFFE69F00),
        text: Color(0xFF7A4F00),
      );
    case SleepDebtLevel.slight:
    case SleepDebtLevel.enough:
    case SleepDebtLevel.notJudgeable:
      return const SleepDebtCardColors(
        background: Color(0xFFF5F5F5),
        border: Color(0xFF9E9E9E),
        text: AppColors.textPrimary,
      );
  }
}

/// N198 2/2：睡眠負債を計算できないときの理由（0 日・1〜6 日）
String sleepDebtUnavailableText(int recordedDays) => recordedDays == 0
    ? '直近4週間の記録がないため、睡眠負債を計算できません。'
    : '記録のある日が $sleepDebtMinDays 日以上になると計算できます（いまは $recordedDays 日）。';

/// N198 2/2：上限（1 日 +1 時間）を当てたときの一言
const String sleepDebtCapNote = '※寝すぎた日の分は 1 日 1 時間までしか差し引いていません';

/// N198 2/2：目標の表示（7h 00m の形。N199：共通の formatSleepDuration）
String formatSleepDebtTarget(Duration target) => formatSleepDuration(target);

/// N196 A 2/2：「あなたの体内時計」の文（SJL だけで判定。SRI は見ない）
/// - SJL が null：記録が足りない・時刻がばらばら・5 時間未満に分けて寝ている（メイン睡眠がない）
String bodyClockMessage(double? sjl) {
  if (sjl == null) {
    return '記録が足りないか、寝る時刻がばらばらなため、体内時計のズレ（SJL）を計算できません。'
        '5時間未満に分けて寝ている場合も計算できません。';
  }
  if (sjl >= 2) return 'SJLが2時間以上あるため、体内時計が大きく乱れています。定期的な就寝時間の調整が効果的です。';
  if (sjl >= 1) return 'SJLが1時間以上あるため、体内時計がやや乱れています。';
  return '体内時計は正常範囲です。良好な睡眠リズムを維持してください。';
}

/// N202：医師への相談のすすめの文言（病名は出さない）
const String medicalConsultMessage =
    'ここ 2 週間、睡眠が目安（1日7時間）より 1 日平均 1 時間以上少ない状態が続いています。'
    '眠気や体調の不調が続くときは、産業医やかかりつけの医師に相談してみるのもひとつの方法です。';

/// N202：小さい文字で添える一言
const String medicalConsultDisclaimer = '※このアプリは病気の診断をするものではありません。';

/// N202：カードの色（青系。Wong 2011 の Blue。赤と緑は使わず、文字は背景との明るさの差を 4.5:1 以上）
const Color medicalConsultBg = Color(0xFFE3F2FD);
const Color medicalConsultBorder = Color(0xFF0072B2);
const Color medicalConsultText = AppColors.textPrimary;
const Color medicalConsultSubText = Color(0xFF555555);
const Color medicalConsultAction = Color(0xFF01579B);

/// N202：医師への相談をすすめる小さなカード（睡眠負債のカードのすぐ下）
/// - 出すかどうか（2 週続けて要注意）は呼び出し側（SleepProvider.suggestsMedicalConsult）
/// - ［閉じる］で閉じた日時を保存し、14 日間は出さない（MedicalConsultDismissStore）
class MedicalConsultCard extends StatefulWidget {
  const MedicalConsultCard({super.key});

  @override
  State<MedicalConsultCard> createState() => _MedicalConsultCardState();
}

class _MedicalConsultCardState extends State<MedicalConsultCard> {
  bool _loaded = false;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dismissedAt = await MedicalConsultDismissStore.load();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _hidden = isMedicalConsultSnoozed(dismissedAt, DateTime.now());
    });
  }

  Future<void> _dismiss() async {
    setState(() => _hidden = true);
    await MedicalConsultDismissStore.save(DateTime.now());  // 保存できなくても、この画面では閉じたまま
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _hidden) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppDimensions.paddingSmall,
        horizontal: AppDimensions.sectionPaddingHorizontal,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
        decoration: BoxDecoration(
          color: medicalConsultBg,
          border: Border.all(color: medicalConsultBorder, width: 2.0),
          borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 20, color: medicalConsultBorder),
                const SizedBox(width: AppDimensions.paddingSmall),
                Expanded(
                  child: Text(
                    medicalConsultMessage,
                    style: AppTextStyles.bodyTextStyle.copyWith(color: medicalConsultText),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.paddingSmall),
            Text(
              medicalConsultDisclaimer,
              // N189：但し書きの形。青い地なので、文字は #666 より濃い medicalConsultSubText のまま
              style: AppTextStyles.noteStyle.copyWith(color: medicalConsultSubText),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _dismiss,
                style: TextButton.styleFrom(foregroundColor: medicalConsultAction),
                child: const Text('閉じる'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  ShiftManagementView _shiftManagementView = ShiftManagementView.calendar;
  Map<DateTime, ShiftData>? _shiftDataMapForDetails;
  List<ShiftPatternModel>? _patternsForDetails;
  // N140：未確定の差分（シフト管理画面の State が作り直されても残るように、ここで持つ）
  final ShiftDraftStore _shiftDraftStore = ShiftDraftStore();

  final ShiftRepository _shiftRepository = ShiftRepository();
  List<ShiftPatternModel> _patterns = [];
  
  // ========== Week 3 Day 6-2 追加: シフト管理画面の state にアクセス ==========
  late GlobalKey<ShiftManagementScreenState> _shiftManagementKey;
  // ========================================================================

  // ========== Week 7 Phase 3: Timer for time update ==========
  Timer? _timeUpdateTimer;
  // ==========================================================

  // 通知停止の停止時刻を確認するまでの秒数カウンター（5秒ごとに確認）
  int _pendingStopCheckSeconds = 0;

  // N128：「アラームとリマインダー」が許可されていないことを知らせるバナー（N129 1/2：通知の許可がないときも）
  AlarmPermissionBannerKind _alarmPermissionBanner = AlarmPermissionBannerKind.none;
  // N128：request() の処理中（ダイアログとバナーから二重に呼ばない）
  bool _isRequestingPermission = false;

  // N129 2/2：鳴っているアラームの［止める］を出すか
  bool _showStopAlarmButton = false;
  // N129 2/2：鳴っているかの確認中（1 秒ごとの確認を重ねない）
  bool _isCheckingAlarmRinging = false;
  // N129 2/2：［止める］の処理中（二度押しを防ぎ、確認でボタンが戻らないようにする）
  bool _isStoppingAlarm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // ========== Week 28 修正: 最新睡眠データをロード ==========
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final sleepProvider = context.read<SleepProvider>();
        await sleepProvider.loadAllSleepData();  // ✅ 変更：loadLatestSleepData() → loadAllSleepData()
        // 2b D20 B：DB の値で表示したあと、裏で RevenueCat に確かめる（await しない）
        unawaited(sleepProvider.refreshPremiumStatus());
      }
    });
    // ====================================================

    // N128：バナーを確かめ、初めてなら説明のダイアログを出す（await しない。ほかの初期化は待たせない）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAlarmPermissionBanner();
      _showAlarmPermissionIntroIfNeeded();
      _refreshStopAlarmButton();  // N129 2/2：開いたときにもう鳴っている場合
    });

    _timeUpdateTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        setState(() {
          // 時刻更新のみ
        });

        // N129 2/2：鳴りはじめ・自動停止・通知からの停止を 1 秒以内に反映する（裏にいる間は呼ばない）
        _refreshStopAlarmButton();

        // 前面表示中の通知停止にも数秒以内で対応する
        _pendingStopCheckSeconds++;
        if (_pendingStopCheckSeconds >= 5) {
          _pendingStopCheckSeconds = 0;
          if (mounted && context.read<SleepProvider>().isSleepingNow) {
            // N142：失敗した同じ停止時刻は、タイマーではやり直さない（起動時・復帰時だけ）
            _handlePendingAlarmStop(retryFailed: false);
          }
        }
      },
    );
    
    _shiftManagementKey = GlobalKey<ShiftManagementScreenState>();

    // N62：今日までに来た付与を自動生成（await しない）
    // N91：失敗はログだけ。ホームでは何も表示しない
    VacationRepository().autoGenerateAccrualsFromSettings('test_user').catchError((e) {
      debugPrint('❌ N91: 起動時の付与の自動生成に失敗: $e');
      return 0;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ========== Week 22+: アプリ再開時にシフトを再ロード ==========
      debugPrint('[HomeScreen] アプリ再開 → シフトを再ロード');
      _shiftManagementKey.currentState?.loadShifts();
      setState(() {});
      // =========================================================

      // 通知の「停止」ボタンで保存された停止時刻で起床処理（await しない）
      _handlePendingAlarmStop();

      // N62：起動したまま付与日をまたいだときも、付与を自動生成（await しない）
      // N91：失敗はログだけ。ホームでは何も表示しない
      VacationRepository().autoGenerateAccrualsFromSettings('test_user').catchError((e) {
        debugPrint('❌ N91: 再開時の付与の自動生成に失敗: $e');
        return 0;
      });

      // N128：端末の設定で許可を変えて戻ってきたときにバナーを確かめ直す（await しない）
      _refreshAlarmPermissionBanner();

      // N129 2/2：裏にいる間に鳴りはじめた・止まった場合（await しない）
      _refreshStopAlarmButton();

      // 2b D20 B：戻ったときも RevenueCat に確かめる（15 分以内は Provider が間引く。await しない）
      unawaited(context.read<SleepProvider>().refreshPremiumStatus());
    }
  }

  /// N129 2/2：［止める］を出すか確かめ直す。前面にいる間だけ確認する
  /// 起動直後の約 500ms は isSleepingNow がまだ復元されていないので、保存値（getSleepStartTime）でも判定する
  /// （wake_up_service.dart の processPendingAlarmStop と同じ考え方）
  Future<void> _refreshStopAlarmButton() async {
    if (_isCheckingAlarmRinging || _isStoppingAlarm) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    _isCheckingAlarmRinging = true;
    try {
      final isRinging = await AlarmService.isAlarmSoundPlaying();
      if (!mounted) return;
      var isSleeping = context.read<SleepProvider>().isSleepingNow;
      if (isRinging && !isSleeping) {
        isSleeping = await SleepPreferenceService.getSleepStartTime() != null;
      }
      // 確認の途中で［止める］が押されたら、この結果は使わない
      if (!mounted || _isStoppingAlarm) return;
      final show = shouldShowStopAlarmButton(isRinging: isRinging, isSleeping: isSleeping);
      if (show != _showStopAlarmButton) {
        setState(() => _showStopAlarmButton = show);
      }
    } finally {
      _isCheckingAlarmRinging = false;
    }
  }

  /// N129 2/2：［止める］。押したらすぐ隠し、失敗したらオレンジの ⚠️ で知らせる
  /// 音を止めるだけで、起床の記録と AlarmManager の予約には触らない
  Future<void> _onStopAlarmPressed() async {
    if (_isStoppingAlarm) return;
    final messenger = ScaffoldMessenger.of(context);  // await 前に取得
    setState(() {
      _isStoppingAlarm = true;
      _showStopAlarmButton = false;
    });
    final stopped = await AlarmService.stopAlarmSound();
    if (stopped) {
      // サービスの onDestroy は少しあとで動く。その前の確認でボタンが一瞬戻らないように待つ
      await Future.delayed(const Duration(milliseconds: 300));
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(stopAlarmFailedText),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 6),
        ),
      );
    }
    _isStoppingAlarm = false;
    if (mounted) await _refreshStopAlarmButton();  // まだ鳴っていれば、もう一度押せるように戻す
  }

  /// N129 2/2：鳴っていることを知らせるバナー（青系。🔔 と文字で意味が分かるようにする）
  Widget _buildStopAlarmBanner() {
    return Material(
      color: AppColors.alarmRingingBanner,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                stopAlarmBannerText,
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton(
              onPressed: _isStoppingAlarm ? null : _onStopAlarmPressed,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.alarmRingingBanner,
              ),
              child: const Text(stopAlarmButtonLabel),
            ),
          ],
        ),
      ),
    );
  }

  /// N128：バナーを出すか確かめ直す（Android・アラーム ON・許可なし のときだけ出す。どれを出すかは alarmPermissionBannerKind）
  Future<void> _refreshAlarmPermissionBanner() async {
    if (!Platform.isAndroid) return;
    try {
      final alarmEnabled = await AlarmService.isAlarmEnabled();
      final exactAlarmGranted = await Permission.scheduleExactAlarm.isGranted;
      // N129 1/2：通知の確認に失敗しても、下の登録し直しは止めない
      var notificationGranted = true;
      try {
        notificationGranted = await Permission.notification.isGranted;
      } catch (e) {
        debugPrint('❌ [HomeScreen] N129：通知の許可の確認に失敗（通知のバナーは出さない）: $e');
      }
      final banner = alarmPermissionBannerKind(
        alarmEnabled: alarmEnabled,
        exactAlarmGranted: exactAlarmGranted,
        notificationGranted: notificationGranted,
      );
      if (mounted && banner != _alarmPermissionBanner) {
        setState(() => _alarmPermissionBanner = banner);
      }
      // N128 2/2：「許可なし → 許可あり」に変わっていたら出勤前アラームを登録し直す
      await _reschedulePreAlarmsIfGranted(exactAlarmGranted: exactAlarmGranted, alarmEnabled: alarmEnabled);
    } catch (e) {
      debugPrint('❌ [HomeScreen] N128：許可の確認に失敗: $e');
    }
  }

  /// N128 2/2：前回の記録が「許可なし」で今回が「許可あり」、かつアラームが ON なら、DB から pre を登録し直して知らせる
  /// 記録がまだないとき・OFF のときは、今の状態を記録するだけ。二重に走らないよう、登録し直す前に記録する
  /// 手動起床（main）は登録し直さない（睡眠中で手動起床が有効なら、戻らないことを知らせる）
  Future<void> _reschedulePreAlarmsIfGranted({required bool exactAlarmGranted, required bool alarmEnabled}) async {
    final prefs = await SharedPreferences.getInstance();
    // 読んでから記録するまでの間に await を挟まない（同時に呼ばれても、登録し直すのは 1 回だけ）
    final previousGranted = prefs.getBool(exactAlarmGrantedLastKey);
    final reschedule = shouldReschedulePreAlarmsOnGrant(
      previousGranted: previousGranted,
      exactAlarmGranted: exactAlarmGranted,
      alarmEnabled: alarmEnabled,
    );
    if (previousGranted != exactAlarmGranted) {
      final saved = prefs.setBool(exactAlarmGrantedLastKey, exactAlarmGranted);
      debugPrint('📝 [HomeScreen] N128：アラームとリマインダーの許可を記録 $previousGranted → $exactAlarmGranted');
      await saved;
    }
    if (!reschedule) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);  // await 前に取得
    final sleepProvider = context.read<SleepProvider>();
    debugPrint('🔔 [HomeScreen] N128：許可されたため出勤前アラームを登録し直します');
    final result = await PreAlarmRescheduleService.reschedule();

    var manualWakeNotRestored = false;
    if (sleepProvider.isSleepingNow) {
      try {
        manualWakeNotRestored = await ManualWakeService.getActive() != null;
      } catch (e) {
        debugPrint('❌ [HomeScreen] N128：手動起床を読めませんでした: $e');
      }
    }

    final messages = alarmPermissionGrantedMessages(
      count: result.count,
      errorMessage: AlarmService.alarmErrorMessage(result.errorCode),
      readFailed: result.readFailed,
      alarmDisabled: result.alarmDisabled,
      manualWakeNotRestored: manualWakeNotRestored,
    );
    // 前を消さずに続けて出す
    for (final message in messages) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message.text),
          backgroundColor: message.color,
          duration: Duration(seconds: message.color == Colors.orange ? 6 : 3),
        ),
      );
    }
  }

  /// N128：初めて開いたときに 1 回だけ、許可の説明のダイアログを出す
  /// どちらも許可済みなら出さずに「出した」にする。出したら、どのボタンでも「出した」にする
  Future<void> _showAlarmPermissionIntroIfNeeded() async {
    if (!Platform.isAndroid) return;
    final bool exactAlarmGranted;
    final bool notificationGranted;
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyShown = prefs.getBool(alarmPermissionIntroShownKey) ?? false;
      if (alreadyShown) return;
      exactAlarmGranted = await Permission.scheduleExactAlarm.isGranted;
      notificationGranted = await Permission.notification.isGranted;
      final show = shouldShowAlarmPermissionIntro(
        alreadyShown: alreadyShown,
        exactAlarmGranted: exactAlarmGranted,
        notificationGranted: notificationGranted,
      );
      // 先に「出した」にする（ダイアログの途中でアプリを閉じても、次からは出さない）
      await prefs.setBool(alarmPermissionIntroShownKey, true);
      if (!show) {
        debugPrint('ℹ️ [HomeScreen] N128：どちらも許可済みのため説明のダイアログは出しません');
        return;
      }
    } catch (e) {
      debugPrint('❌ [HomeScreen] N128：説明のダイアログの確認に失敗: $e');
      return;
    }
    if (!mounted) return;

    final goSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text(alarmPermissionIntroTitle),
        content: const Text(alarmPermissionIntroBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(alarmPermissionIntroLaterLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(alarmPermissionIntroSettingsLabel),
          ),
        ],
      ),
    );
    debugPrint('🔔 [HomeScreen] N128：説明のダイアログ → ${goSettings == true ? '設定する' : 'あとで'}');
    if (goSettings == true) {
      await _requestAlarmPermissions(
        exactAlarm: !exactAlarmGranted,
        notification: !notificationGranted,
      );
    }
  }

  /// N128：許可されていないものだけ、順番に request() する（アラームとリマインダー → 通知）
  /// 2 つを同時に呼ぶと「A request for permissions is already running」になるため、1 つずつ await する
  /// 処理中はもう一度呼ばない。終わったらバナーを確かめ直す
  Future<void> _requestAlarmPermissions({required bool exactAlarm, required bool notification}) async {
    if (_isRequestingPermission) return;
    setState(() => _isRequestingPermission = true);
    try {
      if (exactAlarm) {
        final status = await Permission.scheduleExactAlarm.request();
        debugPrint('📋 [HomeScreen] N128：アラームとリマインダー → $status');
      }
      if (notification) {
        final status = await Permission.notification.request();
        debugPrint('📋 [HomeScreen] N128：通知 → $status');
      }
    } catch (e) {
      debugPrint('❌ [HomeScreen] N128：許可の request() に失敗: $e');
    } finally {
      if (mounted) setState(() => _isRequestingPermission = false);
    }
    await _refreshAlarmPermissionBanner();
  }

  /// N128：バナーの［設定を開く］。ダイアログの［設定する］と同じく、許可されていないものだけを順に求める
  /// （ダイアログで［あとで］を選んだ人にも、通知の許可を求められるようにする）
  Future<void> _onAlarmPermissionBannerPressed() async {
    if (_isRequestingPermission) return;
    var notificationGranted = true;
    try {
      notificationGranted = await Permission.notification.isGranted;
    } catch (e) {
      debugPrint('❌ [HomeScreen] N128：通知の許可の確認に失敗（通知は求めない）: $e');
    }
    await _requestAlarmPermissions(exactAlarm: true, notification: !notificationGranted);
  }

  /// N129 1/2：通知のバナーの［設定を開く］。request() で許可されなければアプリの設定画面を開く
  /// 設定画面から戻ったときは didChangeAppLifecycleState の resumed でバナーを確かめ直す
  Future<void> _onNotificationPermissionBannerPressed() async {
    if (_isRequestingPermission) return;
    setState(() => _isRequestingPermission = true);
    try {
      final status = await Permission.notification.request();
      debugPrint('📋 [HomeScreen] N129：通知 → $status');
      if (!status.isGranted) {
        final opened = await openAppSettings();
        debugPrint('📋 [HomeScreen] N129：アプリの設定画面を開く → $opened');
      }
    } catch (e) {
      debugPrint('❌ [HomeScreen] N129：通知の許可の処理に失敗: $e');
    } finally {
      if (mounted) setState(() => _isRequestingPermission = false);
    }
    await _refreshAlarmPermissionBanner();
  }

  /// N128：許可がないことを知らせるバナー（オレンジ系。⚠️ と文字で意味が分かるようにする）
  Widget _buildAlarmPermissionBanner() {
    final isNotification = _alarmPermissionBanner == AlarmPermissionBannerKind.notification;
    return Material(
      color: Colors.orange.shade100,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Colors.orange, width: 4)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                isNotification ? notificationPermissionBannerText : alarmPermissionBannerText,
                style: const TextStyle(color: Colors.black87, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _isRequestingPermission
                  ? null
                  : (isNotification ? _onNotificationPermissionBannerPressed : _onAlarmPermissionBannerPressed),
              child: const Text(alarmPermissionBannerButtonLabel),
            ),
          ],
        ),
      ),
    );
  }

  /// 通知の「停止」ボタンで保存された停止時刻があれば起床処理を行う
  Future<void> _handlePendingAlarmStop({bool retryFailed = true}) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<SleepProvider>();

    final result = await WakeUpService.processPendingAlarmStop(provider, retryFailed: retryFailed);
    // N142：記録なしの起床では「記録しました」を出さない
    if (result.recordedWake) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('⏰ アラーム停止時刻で起床を記録しました'),
          duration: Duration(seconds: 3),
        ),
      );
    }
    // N19：⏰ のあとに続けて知らせる
    for (final text in result.warningTexts) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  void dispose() {
    // ========== Week 7 Phase 3: Timer をキャンセル（メモリリーク防止） ==========
    _timeUpdateTimer?.cancel();
    // =====================================================================
    _shiftDraftStore.dispose();  // N140 2/4
    WidgetsBinding.instance.removeObserver(this);  // N132
    super.dispose();
  }

  /// N140：詳細確認での編集を未確定として預ける
  void _captureDetailsDraft() {
    final detailsMap = _shiftDataMapForDetails;
    if (_shiftManagementView == ShiftManagementView.details && detailsMap != null) {
      _shiftDraftStore.captureDetails(shiftPatternsOf(detailsMap));
      debugPrint('[ShiftDraft] 詳細確認の編集を預かる：差分 ${_shiftDraftStore.draft.length} 件');
    }
  }

  /// N140 3/4：詳細確認でシフトを変えた・消したとき。その日の有休・半休もカレンダーと同じ規則で変えてから預ける
  void _onDetailsEdited(DateTime date, ShiftPatternModel? oldPattern, ShiftPatternModel? newPattern) {
    final days = vacationDaysAfterShiftEdit(
      currentDays: _shiftDraftStore.vacationDaysOn(date),
      oldPattern: oldPattern,
      newPattern: newPattern,
    );
    _shiftDraftStore.applyDetailVacationEdit(date, days);
    _captureDetailsDraft();
  }

  /// N140 2/4：戻るボタン。アプリの最初の画面なので、そのまま戻るとアプリが閉じる
  Future<void> _onBackPressed() async {
    final pendingCount = _shiftDraftStore.pendingCount.value;
    final action = shiftBackAction(
      isDetails: _shiftManagementView == ShiftManagementView.details && _shiftDataMapForDetails != null,
      pendingCount: pendingCount,
    );
    switch (action) {
      case ShiftBackAction.backToCalendar:
        // 詳細確認は別の画面ではないので、表示を切り替えて戻る（編集は未確定として残す）
        _captureDetailsDraft();
        setState(() => _shiftManagementView = ShiftManagementView.calendar);
        _loadPatterns();
      case ShiftBackAction.close:
        await SystemNavigator.pop();
      case ShiftBackAction.confirmClose:
        final close = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text(draftCloseDialogTitle),
            content: Text(draftCloseDialogBody(pendingCount)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('アプリに戻る'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('閉じる'),
              ),
            ],
          ),
        );
        if (close == true) await SystemNavigator.pop();
    }
  }

  /// N140 2/4：シフト管理タブのアイコン。未確定があれば件数の数字を出す（色だけに頼らない）
  Widget _buildShiftTabIcon() {
    return ValueListenableBuilder<int>(
      valueListenable: _shiftDraftStore.pendingCount,
      builder: (context, count, child) => Badge(
        isLabelVisible: count > 0,
        label: Text(draftBadgeLabel(count)),
        backgroundColor: AppColors.draftAccent,
        textColor: Colors.white,
        child: child,
      ),
      child: const Icon(Icons.calendar_today),
    );
  }

  Future<void> _loadPatterns() async {

    try {
      // N103：colorIndex 0 のパターンを消す処理はなくした（使っていたシフトが休日になるため）
      final patterns = await _shiftRepository.getAllPatterns();
      setState(() {
        _patterns = patterns;
      });
      print('Loaded ${patterns.length} patterns from DB');
    } catch (e) {
      // N118：読めなかったら _patterns は古いまま残す（[] で上書きしない）
      debugPrint('Error loading patterns: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // N140 2/4：戻るボタンは _onBackPressed で判断する（イベント追加などの別の画面・ダイアログには効かない）
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onBackPressed();
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'ShiftSleep',
          style: AppTextStyles.headerStyle,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: AppColors.borderDefault,
            height: 1.0,
          ),
        ),
      ),
      // N128：許可がない間は、どのタブでも上にバナーを出す
      body: Column(
        children: [
          // N129 2/2：鳴っている間は、許可のバナーより上に出す
          if (_showStopAlarmButton) _buildStopAlarmBanner(),
          if (_alarmPermissionBanner != AlarmPermissionBannerKind.none) _buildAlarmPermissionBanner(),
          Expanded(child: _buildPage(_selectedIndex)),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          // N190：設定タブから離れるときだけ、設定タブで出た SnackBar を消す（移った先のタブが出す SnackBar はこのあとに出る）
          if (shouldClearSnackBarsOnTabChange(from: _selectedIndex, to: index)) {
            ScaffoldMessenger.of(context).clearSnackBars();
          }
          // N140：詳細確認の表示中にタブを押したら、詳細確認での編集を未確定として預ける（下でカレンダー表示に戻るため）
          _captureDetailsDraft();
          setState(() {
            _selectedIndex = index;
            // ========== Week 3 Day 6-2 修正: シフト管理タブ切り替え時にリセット ==========
            // タブを切り替える際、常に ShiftManagementView をリセット
            _shiftManagementView = ShiftManagementView.calendar;
            // ========================================================================
          });

          // N128：設定タブでアラームを ON/OFF したあと、タブを切り替えたときにバナーを確かめ直す
          _refreshAlarmPermissionBanner();

          // ========== Week 3 Day 6-2 修正: タブ切り替え時にパターンを読み直す ==========
          if (index == 1) {
            // パターンをリロード（詳細確認へ渡す _patterns）
            _loadPatterns();
            // N118 4/4：シフトはここでは読まない。タブを開くとシフト管理の State が作り直され、initState で
            // 有休・パターン・シフト・イベントをまとめて読み、失敗を 1 つの SnackBar で知らせる。ここで 100ms 後に
            // loadShifts() を呼ぶと、その SnackBar をシフトだけの ❌ で上書きしてしまうため外した
            // （シフト管理タブを表示したまま同じタブを押したときは読み直さない）
          }
          // ============================================================================
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primaryGradientStart,
        unselectedItemColor: AppColors.textMuted,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'ホーム',
          ),
          BottomNavigationBarItem(
            icon: _buildShiftTabIcon(),  // N140 2/4
            label: 'シフト管理',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '設定',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: '詳細',
          ),
        ],
      ),
    );
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return _buildHomeContent();
      case 1:
        if (_shiftManagementView == ShiftManagementView.details &&
            _shiftDataMapForDetails != null &&
            _patternsForDetails != null) {
          return ShiftDetailScreen(
            shiftDataMap: _shiftDataMapForDetails!,
            patterns: _patternsForDetails!,
            onChanged: _onDetailsEdited,  // N140 2/4・3/4
            confirmedDays: () => _shiftDraftStore.confirmedCount,  // N140 2/4
            vacationDraft: () => _shiftDraftStore.vacationDraft,  // N140 3/4
            // N140：DB に書けたら未確定はなくなる
            onConfirmed: () {
              _shiftDraftStore.clear();
              debugPrint('[ShiftDraft] 確定：差分 ${_shiftDraftStore.draft.length} 件');
              // N140 3/4：確定の途中でシフト管理タブへ移っていたら、有休の統計・表示を読み直す
              _shiftManagementKey.currentState?.reloadAfterConfirm();
            },
            onBack: () {
              setState(() {
                _shiftManagementView = ShiftManagementView.calendar;
                _shiftDataMapForDetails = null;
                _patternsForDetails = null;
              });
              // ========== Week 3 Day 6-2 追加: 入力フォームをリセット＆シフトを再ロード ==========
              _loadPatterns();
              _shiftManagementKey.currentState?.clearShiftMap();
              _shiftManagementKey.currentState?.loadShifts();
              // ==============================================================
            },
          );
        } else {
          return ShiftManagementScreen(
            key: _shiftManagementKey,  // ========== Week 3 Day 6-2 修正: GlobalKey に変更 ==========
            patterns: _patterns,
            draftStore: _shiftDraftStore,  // N140
            onNavigateToDetails: (shiftDataMap, patterns) {
              setState(() {
                // N140：_shiftMap とは別の Map にする（読み直し・遅れて終わる期間指定が詳細確認の内容を変えないように）
                _shiftDataMapForDetails = Map.of(shiftDataMap);
                _patternsForDetails = patterns;
                _shiftManagementView = ShiftManagementView.details;
              });
              // N140 3/4：シフト管理画面が有休の差分を預けるのは、このフレームの終わり（dispose）なので、そのあとで描き直す
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            },
          );
        }
      case 2:
        return SettingsScreen(userId: 'test_user');
      case 3:
        return SleepRecordsScreen(userId: 'test_user');
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildHomeContent() {
    return Consumer<SleepProvider>(
      builder: (context, sleepProvider, _) {
        if (sleepProvider.isLoading) {
          return Center(
            child: CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation(AppColors.primaryGradientStart),
            ),
          );
        }

        return SingleChildScrollView(
          child: Column(
            children: [
              // ========================
                      // ========== Week 10: 有給管理セクション ==========
                              
                      // ===================================================
                      // Main Button Section with Gradient
              // ========================
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryGradientStart,
                      AppColors.primaryGradientEnd,
                    ],
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimensions.mainButtonSectionPaddingVertical,
                  horizontal:
                      AppDimensions.mainButtonSectionPaddingHorizontal,
                ),
                child: Column(
                  children: [
                    Text(
                      _getCurrentTime(),
                      style: AppTextStyles.headerStyle.copyWith(
                        fontSize: 32,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.paddingSmall),
                    Text(
                      '現在時刻',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.paddingLarge),
                    SleepButton(
                      onPressed: null,  // または () {} で何もしない
                    ),
                  ],
                ),
              ),

              // A-3 3/3：次のシフトに合わせた睡眠の目安（寝る・起きるボタンのすぐ下。D54）
              // D72：未確定のシフトの日数を渡し、あれば一言を出す（ShiftDraftStore はこの State が持つので const にできない）
              SleepPlanCard(pendingDraftCount: _shiftDraftStore.pendingCount),

              // ========================
              // Yesterday's Sleep Section - Card Style
              // ========================
              Container(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimensions.sectionPaddingVertical,
                  horizontal: AppDimensions.sectionPaddingHorizontal,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.borderDefault,
                      width: AppDimensions.borderWidthThin,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.nights_stay,
                          size: 20,
                          color: AppColors.primaryGradientStart,
                        ),
                        const SizedBox(width: AppDimensions.paddingSmall),
                        // N51 F：大きい文字でもはみ出さないよう Flexible（入らないときは折り返す）
                        Flexible(
                          child: Text(
                            '${DateTime.now().month}/${DateTime.now().day} の睡眠（0:00〜）',
                            style: AppTextStyles.sectionTitleStyle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    if (sleepProvider.latestRecord != null)
                      Container(
                        padding: const EdgeInsets.all(
                          AppDimensions.paddingMedium,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: AppColors.borderDefault,
                            width: AppDimensions.borderWidthThin,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusMedium,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (sleepProvider.todaysSplitSleepDuration.inMinutes >= 1)
                              Text(
                                sleepProvider.todaysSleepDurationFormatted,
                                style: AppTextStyles.largeNumberStyle.copyWith(
                                  fontSize: 42,
                                ),
                              )
                            else ...[
                              Text(
                                'まだ記録がありません',
                                style: AppTextStyles.bodyTextStyle.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                              // N106：押し忘れた睡眠をあとから追加
                              const SizedBox(height: AppDimensions.paddingSmall),
                              _buildAddSleepButton('＋ 睡眠を追加'),
                            ],
                            const SizedBox(
                                height: AppDimensions.paddingMedium),
                                if (sleepProvider.lastSleepDuration.inMinutes < 60 ||
                                    sleepProvider.lastSleepDuration.inHours > 20)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: AppDimensions.paddingMedium),
                                    child: Container(
                                      padding: const EdgeInsets.all(AppDimensions.paddingSmall),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF9E6),
                                        border: Border.all(color: const Color(0xFFF57F17), width: 2.0),
                                        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.warning_amber, color: Color(0xFFF57F17), size: 20),
                                          const SizedBox(width: 12.0),
                                          Expanded(
                                            child: Text(
                                              '昨日、ボタンを押し忘れていませんか？',
                                              style: AppTextStyles.bodyTextStyle.copyWith(
                                                fontSize: 12.0,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                          // N106：入眠日を昨日にして追加画面を開く
                                          _buildAddSleepButton(
                                            '追加する',
                                            initialBedDate: DateTime.now().subtract(const Duration(days: 1)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                            if (sleepProvider.todaysSplitSleepDuration.inMinutes >= 1)
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: List.generate(
                                    5,
                                    (index) => Padding(
                                      padding: const EdgeInsets.only(
                                        right: AppDimensions.gapSmall,
                                      ),
                                      child: Icon(
                                        Icons.star,
                                        size: 20,
                                        color: index <
                                                _getStarCount(sleepProvider)
                                            ? AppColors.starYellow
                                            : AppColors.borderDefault,
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                // N106：記録があっても別の睡眠を追加できる
                                _buildAddSleepButton('＋ 追加'),
                                // N107：睡眠中は進行中の記録が開くことがあるので「修正」を出さない
                                if (!sleepProvider.isSleepingNow) ...[
                                const SizedBox(width: AppDimensions.paddingSmall),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            EditSleepRecordScreen(
                                          record: sleepProvider.latestRecord!,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppDimensions.paddingSmall,
                                      vertical: AppDimensions.paddingXSmall,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryGradientStart
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(
                                        AppDimensions.borderRadiusSmall,
                                      ),
                                    ),
                                    child: Text(
                                      '修正',
                                      style:
                                          AppTextStyles.labelStyle.copyWith(
                                        color: AppColors.primaryGradientStart,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                ],
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(
                          AppDimensions.paddingMedium,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cardBgGray,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusMedium,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'まだ記録がありません',
                              style: AppTextStyles.bodyTextStyle.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            // N106：押し忘れた睡眠をあとから追加
                            const SizedBox(height: AppDimensions.paddingSmall),
                            _buildAddSleepButton('＋ 睡眠を追加'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),


              // ========================
              // Circadian State Section - Compact
              // ========================
              Container(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimensions.sectionPaddingVertical,
                  horizontal: AppDimensions.sectionPaddingHorizontal,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.borderDefault,
                      width: AppDimensions.borderWidthThin,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 20,
                          color: AppColors.primaryGradientStart,
                        ),
                        const SizedBox(width: AppDimensions.paddingSmall),
                        Text(
                          '体内時計の状態',
                          style: AppTextStyles.sectionTitleStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(
                              AppDimensions.paddingSmall,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.cardBgWarning,
                              border: Border.all(
                                color: AppColors.borderWarning,
                                width: AppDimensions.borderWidthThin,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppDimensions.borderRadiusSmall,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'SJL\n(体内時計負担数)',
                                  style: AppTextStyles.labelStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  sleepProvider.sjl == null
                                      ? '—'  // N183：計算できない
                                      : '${sleepProvider.sjl!.toStringAsFixed(1)}h',
                                  style: AppTextStyles.statNumberStyle,
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  sleepProvider.sjlEvaluation,
                                  style: AppTextStyles.labelStyle.copyWith(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AppDimensions.gapMedium),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(
                              AppDimensions.paddingSmall,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.cardBgGray,
                              border: Border.all(
                                color: AppColors.borderDefault,
                                width: AppDimensions.borderWidthThin,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppDimensions.borderRadiusSmall,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'SRI\n(睡眠規則性指数)',
                                  style: AppTextStyles.labelStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  sleepProvider.sri == null
                                      ? '—'  // N197：計算できない
                                      : sleepProvider.sri!.toStringAsFixed(0),
                                  style: AppTextStyles.statNumberStyle,
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  sleepProvider.sriEvaluation,
                                  style: AppTextStyles.labelStyle.copyWith(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    Container(
                      padding: const EdgeInsets.all(
                        AppDimensions.paddingSmall,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cardBgAlert,
                        border: Border.all(
                          color: AppColors.borderDefault,
                          width: AppDimensions.borderWidthThin,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppDimensions.borderRadiusSmall,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'あなたの体内時計:',
                            style: AppTextStyles.subtitleLabelStyle.copyWith(
                              color: AppColors.darkWarning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6.0),
                          Text(
                            bodyClockMessage(sleepProvider.sjl),  // N196 A 2/2：SJL だけで判定
                            style: AppTextStyles.descriptionStyle.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ========== Week 7 A 追加: 分割睡眠セクション ==========
              // 【昨晩の睡眠】メイン睡眠 + 補助睡眠の詳細表示
              Container(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimensions.sectionPaddingVertical,
                  horizontal: AppDimensions.sectionPaddingHorizontal,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.borderDefault,
                      width: AppDimensions.borderWidthThin,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.bedtime,
                          size: 20,
                          color: AppColors.primaryGradientStart,
                        ),
                        const SizedBox(width: AppDimensions.paddingSmall),
                        // N51 F（L8）：大きい文字でもはみ出さないよう Flexible（入らないときは折り返す）
                        Flexible(
                          child: Text(
                            '睡眠の内訳（直近24時間）',  // N184
                            style: AppTextStyles.sectionTitleStyle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // ========== メイン睡眠 + 補助睡眠 の 2列表示 ==========
                    Row(
                      children: [
                        // メイン睡眠
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(
                              AppDimensions.paddingSmall,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: AppColors.borderDefault,
                                width: AppDimensions.borderWidthThin,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppDimensions.borderRadiusSmall,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'メイン睡眠',
                                  style: AppTextStyles.labelStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6.0),
                                Text(
                                  sleepProvider.lastPrimarySleepFormatted,
                                  style: AppTextStyles.statNumberStyle
                                      .copyWith(
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  '（長時間睡眠）',
                                  style: AppTextStyles.descriptionStyle
                                      .copyWith(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AppDimensions.gapMedium),
                        // 補助睡眠
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(
                              AppDimensions.paddingSmall,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: AppColors.borderDefault,
                                width: AppDimensions.borderWidthThin,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppDimensions.borderRadiusSmall,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '補助睡眠',
                                  style: AppTextStyles.labelStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6.0),
                                Text(
                                  sleepProvider.lastSupplementarySleepFormatted,
                                  style: AppTextStyles.statNumberStyle
                                      .copyWith(
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  '（昼寝など）',
                                  style: AppTextStyles.descriptionStyle
                                      .copyWith(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // ========== 総睡眠時間 ==========
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(
                        AppDimensions.paddingSmall,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primaryGradientStart.withValues(alpha: 0.1),
                            AppColors.primaryGradientEnd.withValues(alpha: 0.1),
                          ],
                        ),
                        border: Border.all(
                          color: AppColors.primaryGradientStart
                              .withValues(alpha: 0.3),
                          width: AppDimensions.borderWidthThin,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppDimensions.borderRadiusSmall,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '合計睡眠時間',
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            sleepProvider.lastTotalSleepFormatted,
                            style: AppTextStyles.statNumberStyle.copyWith(
                              fontSize: 16,
                              color: AppColors.primaryGradientStart,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
// ========================================================================
              // ========== Week 7 A 追加: 睡眠改善アドバイスセクション ==========
              // 無料版：最優先アドバイス 1個
              // 有料版：優先度1,2のアドバイス 最大5個
              // N197・N203：出すアドバイスがないときも欄は残し、案内の 1 行を出す
              Container(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppDimensions.sectionPaddingVertical,
                    horizontal: AppDimensions.sectionPaddingHorizontal,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.borderDefault,
                        width: AppDimensions.borderWidthThin,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb,
                            size: 20,
                            color: AppColors.primaryGradientStart,
                          ),
                          const SizedBox(width: AppDimensions.paddingSmall),
                          // N194：アイコンと重なるので文字の絵文字は付けない。大きい文字でもはみ出さないよう Flexible
                          Flexible(
                            child: Text(
                              '改善アドバイス',
                              style: AppTextStyles.sectionTitleStyle,
                            ),
                          ),
                          if (sleepProvider.isPremiumUser)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: AppDimensions.paddingSmall,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                  vertical: 2.0,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGradientStart,
                                  borderRadius: BorderRadius.circular(4.0),
                                ),
                                child: Text(
                                  'プレミアム',
                                  style: AppTextStyles.labelStyle.copyWith(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.paddingMedium),

                      // N197・N203：出すアドバイスがなければ案内の 1 行だけ（記録不足／大きな改善点なし）
                      if (SleepAdvisoryService.emptyAdviceMessage(
                            all: sleepProvider.allAdvice,
                            displayed: sleepProvider.displayedAdvice,
                          ) case final message?)
                        Text(
                          message,
                          style: AppTextStyles.descriptionStyle.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),

                      // ========== メインアドバイス（優先度1） ==========
                      if (sleepProvider.topAdvice != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(
                            AppDimensions.paddingMedium,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.primaryGradientStart.withValues(alpha: 0.15),
                                AppColors.primaryGradientEnd.withValues(alpha: 0.15),
                              ],
                            ),
                            border: Border.all(
                              color: AppColors.primaryGradientStart
                                  .withValues(alpha: 0.5),
                              width: AppDimensions.borderWidthThin,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppDimensions.borderRadiusMedium,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // タイトル
                              Text(
                                sleepProvider.topAdvice!.title,
                                style: AppTextStyles.subtitleLabelStyle
                                    .copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.primaryGradientStart,
                                ),
                              ),
                              const SizedBox(
                                height: AppDimensions.paddingMedium,
                              ),

                              // 説明
                              Text(
                                sleepProvider.topAdvice!.description,
                                style: AppTextStyles.bodyTextStyle.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.5,
                                ),
                              ),

                              // アクションTip（N186：無料は 🔒 の案内だけ。案内が OFF なら出さない）
                              if (actionTipView(
                                    sleepProvider.topAdvice!,
                                    isPremium: sleepProvider.isPremiumUser,
                                    promoVisible:
                                        sleepProvider.advicePromoVisible,
                                  ) ==
                                  ActionTipView.shown)
                                Column(
                                  children: [
                                    const SizedBox(
                                      height: AppDimensions.paddingMedium,
                                    ),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(
                                        AppDimensions.paddingSmall,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(
                                          AppDimensions.borderRadiusSmall,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            '💡 ',
                                            style: AppTextStyles.bodyTextStyle,
                                          ),
                                          Expanded(
                                            child: Text(
                                              sleepProvider
                                                  .topAdvice!.actionTip!,
                                              style: AppTextStyles
                                                  .descriptionStyle
                                                  .copyWith(
                                                color: AppColors
                                                    .primaryGradientStart,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              else if (actionTipView(
                                    sleepProvider.topAdvice!,
                                    isPremium: sleepProvider.isPremiumUser,
                                    promoVisible:
                                        sleepProvider.advicePromoVisible,
                                  ) ==
                                  ActionTipView.locked)
                                Column(
                                  children: [
                                    const SizedBox(
                                      height: AppDimensions.paddingMedium,
                                    ),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(
                                        AppDimensions.paddingSmall,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(
                                          AppDimensions.borderRadiusSmall,
                                        ),
                                      ),
                                      // P1：🔒 と文言は詳細のダイアログと共通の部品（大きい文字でも「解／放」と割れない）
                                      child: const ActionTipLockedLabel(),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),

                      // ========== 追加アドバイス（有料版のみ）==========
                      if (sleepProvider.isPremiumUser &&
                          sleepProvider.displayedAdvice.length > 1)
                        Column(
                          children: [
                            const SizedBox(
                              height: AppDimensions.paddingMedium,
                            ),
                            ...sleepProvider.displayedAdvice
                                .skip(1)
                                .map((advice) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: AppDimensions.paddingSmall,
                                      ),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(
                                          AppDimensions.paddingSmall,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: AppColors.borderDefault,
                                            width: AppDimensions
                                                .borderWidthThin,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(
                                            AppDimensions.borderRadiusSmall,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              advice.title,
                                              style: AppTextStyles
                                                  .labelStyle
                                                  .copyWith(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 4.0),
                                            Text(
                                              advice.description,
                                              style: AppTextStyles
                                                  .descriptionStyle
                                                  .copyWith(
                                                fontSize: 11,
                                                color: AppColors
                                                    .textSecondary,
                                              ),
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    )),
                          ],
                        ),

                      // ========== 「全てのアドバイスを見る」ボタン ==========
                      // N206：アドバイスの間に挟まらないよう、2 件目以降のあと（一番下）に置く
                      if (sleepProvider.hasAdvice)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppDimensions.paddingMedium,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AdviceDetailScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('全てのアドバイスを見る'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    AppColors.primaryGradientStart,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppDimensions.borderRadiusMedium,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
// ====================================================================
              // ========================
              // Sleep Debt Section - Highlighted
              // ========================
              Container(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimensions.sectionPaddingVertical,
                  horizontal: AppDimensions.sectionPaddingHorizontal,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.borderDefault,
                      width: AppDimensions.borderWidthThin,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.trending_down,
                          size: 20,
                          color: AppColors.warningRed,
                        ),
                        const SizedBox(width: AppDimensions.paddingSmall),
                        Text(
                          '睡眠負債',
                          style: AppTextStyles.sectionTitleStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    // N198 2/2：1 日平均の不足を大きく、その下に説明と評価。枠の色は段階ごと（評価の文字と必ず一緒に出す）
                    Builder(builder: (context) {
                      final debtColors = sleepDebtCardColors(sleepProvider.sleepDebtLevel);
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(
                          AppDimensions.paddingMedium,
                        ),
                        decoration: BoxDecoration(
                          color: debtColors.background,
                          border: Border.all(
                            color: debtColors.border,
                            width: 2.0,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppDimensions.borderRadiusMedium,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              sleepProvider.sleepDebtFormatted,
                              style: AppTextStyles.debtNumberStyle.copyWith(
                                color: debtColors.text,
                              ),
                            ),
                            const SizedBox(height: 4.0),
                            Text(
                              '1日平均の不足（直近4週間）',
                              style: AppTextStyles.descriptionStyle.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4.0),
                            Text(
                              sleepProvider.sleepDebtEvaluation,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyTextStyle.copyWith(
                                color: debtColors.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    // N197：計算できないときは理由を出す（N198 2/2：記録のある日が 1〜6 日なら日数も）
                    if (sleepProvider.sleepDebt == null)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: AppDimensions.paddingSmall,
                        ),
                        child: Text(
                          sleepDebtUnavailableText(sleepProvider.sleepDebtRecordedDays),
                          style: AppTextStyles.descriptionStyle.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    const SizedBox(height: AppDimensions.paddingMedium),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // N51 F：大きい文字で右の「目標」を押し出さないように、左だけ幅を譲る（ラベルは折り返す）
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '1日平均（直近4週間）',  // N184
                                style: AppTextStyles.bodyTextStyle,
                              ),
                              const SizedBox(height: 4.0),
                              Text(
                                sleepProvider.recentDailyAverageSleepFormatted,
                                style: AppTextStyles.statNumberStyle,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppDimensions.paddingXSmall),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '目標',
                              style: AppTextStyles.bodyTextStyle,
                            ),
                            const SizedBox(height: 4.0),
                            Text(
                              formatSleepDebtTarget(sleepDebtTarget),  // N198 2/2：定数から
                              style: AppTextStyles.statNumberStyle.copyWith(
                                color: AppColors.primaryGradientStart,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // N198 2/2：上限（+1 時間）のために、大きい数字と「目標 − 1日平均」が違うときだけ
                    if (sleepProvider.showsSleepDebtCapNote)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: AppDimensions.paddingSmall,
                        ),
                        child: Text(
                          sleepDebtCapNote,
                          style: AppTextStyles.noteStyle,  // N189
                        ),
                      ),
                  ],
                ),
              ),
              // N202：2 週続けて睡眠負債が要注意なら、医師への相談をすすめる（無料版でも出す。閉じたら 14 日出さない）
              if (sleepProvider.suggestsMedicalConsult) const MedicalConsultCard(),
                            // ========== Week 9-1 追加: 睡眠集計セクション（当日/今週/今月）==========
                            // Wong 2011 パレット対応（色盲アクセシビリティ）
                            Container(
                              margin: EdgeInsets.zero,
                              padding: const EdgeInsets.symmetric(
                                vertical: AppDimensions.sectionPaddingVertical,
                                horizontal: AppDimensions.sectionPaddingHorizontal,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: AppColors.borderDefault,
                                    width: AppDimensions.borderWidthThin,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.bar_chart,
                                        size: 20,
                                        color: AppColors.primaryGradientStart,
                                      ),
                                      const SizedBox(width: AppDimensions.paddingSmall),
                                      Text(
                                        '睡眠集計',
                                        style: AppTextStyles.sectionTitleStyle,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppDimensions.paddingMedium),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(
                                            AppDimensions.paddingSmall,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.summaryTodayBg,
                                            border: Border.all(
                                              color: AppColors.summaryTodayBorder,
                                              width: AppDimensions.borderWidthThin,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              AppDimensions.borderRadiusSmall,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                '当日',
                                                style: AppTextStyles.labelStyle.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                  color: AppColors.summaryTodayBorder,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 6.0),
                                              // 大きい文字でも数字が折り返さず枠に収まるよう、縮めて 1 行で出す
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  sleepProvider.todaysSleepDurationFormatted,
                                                  style: AppTextStyles.statNumberStyle.copyWith(
                                                    fontSize: 16,
                                                    color: AppColors.summaryTodayText,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              const SizedBox(height: 4.0),
                                              Text(
                                                '今日の合計',
                                                style: AppTextStyles.descriptionStyle.copyWith(
                                                  fontSize: 10,
                                                  color: AppColors.summaryTodayBorder,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: AppDimensions.gapSmall),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(
                                            AppDimensions.paddingSmall,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.summaryWeekBg,
                                            border: Border.all(
                                              color: AppColors.summaryWeekBorder,
                                              width: AppDimensions.borderWidthThin,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              AppDimensions.borderRadiusSmall,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                '今週',
                                                style: AppTextStyles.labelStyle.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                  color: AppColors.summaryWeekBorder,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 6.0),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  sleepProvider.thisWeekTotalSleepFormatted,
                                                  style: AppTextStyles.statNumberStyle.copyWith(
                                                    fontSize: 16,
                                                    color: AppColors.summaryWeekText,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              const SizedBox(height: 4.0),
                                              Text(
                                                '月～日累計',
                                                style: AppTextStyles.descriptionStyle.copyWith(
                                                  fontSize: 10,
                                                  color: AppColors.summaryWeekBorder,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: AppDimensions.gapSmall),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(
                                            AppDimensions.paddingSmall,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.summaryMonthBg,
                                            border: Border.all(
                                              color: AppColors.summaryMonthBorder,
                                              width: AppDimensions.borderWidthThin,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              AppDimensions.borderRadiusSmall,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                '今月',
                                                style: AppTextStyles.labelStyle.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                  color: AppColors.summaryMonthBorder,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 6.0),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  sleepProvider.thisMonthAverageSleepFormatted,
                                                  style: AppTextStyles.statNumberStyle.copyWith(
                                                    fontSize: 16,
                                                    color: AppColors.summaryMonthText,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              const SizedBox(height: 4.0),
                                              Text(
                                                '平均睡眠時間',
                                                style: AppTextStyles.descriptionStyle.copyWith(
                                                  fontSize: 10,
                                                  color: AppColors.summaryMonthBorder,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // ========================================================================
              const SizedBox(height: AppDimensions.paddingLarge),
                            // ========== Week 3 Day 5 修正: シフト体系登録ボタン（移動・スタイル改善） ==========
                            Container(
                              margin: EdgeInsets.zero,
                              padding: const EdgeInsets.symmetric(
                                vertical: AppDimensions.sectionPaddingVertical,
                                horizontal: AppDimensions.sectionPaddingHorizontal,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: AppColors.borderDefault,
                                    width: AppDimensions.borderWidthThin,
                                  ),
                                ),
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ShiftPatternScreen(
                                          mode: ShiftPatternMode.register,
                                          existingPatterns: _patterns,
                                        ),
                                      ),
                                    );
                      
                                    // ========== Fix：戻ってきたパターンを反映 ==========
                                    if (result is List<ShiftPatternModel>) {
                                      setState(() {
                                        _patterns = result;
                                        _selectedIndex = 1;  // シフト管理タブに切り替え
                                      });
                                    } else if (result == 1) {
                                      // 後方互換性のため
                                      setState(() {
                                        _selectedIndex = 1;
                                      });
                                      await _loadPatterns();
                                    }
                                    // ==================================================
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    elevation: 0,
                                    side: BorderSide(
                                      color: AppColors.primaryGradientStart,
                                      width: 2,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      vertical: AppDimensions.paddingMedium,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppDimensions.borderRadiusMedium,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'シフト体系登録',
                                    style: AppTextStyles.bodyTextStyle.copyWith(
                                      color: AppColors.primaryGradientStart,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // ================================================================================================================================================================

            ],
          ),
        );
      },
    );
  }

  /// N106：睡眠の追加画面を開くボタン（「修正」と同じ見た目）
  /// 保存すると addManualSleepRecord が読み直すので、戻ったときにはホームが更新されている
  Widget _buildAddSleepButton(String label, {DateTime? initialBedDate}) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditSleepRecordScreen(
              initialBedDate: initialBedDate,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingSmall,
          vertical: AppDimensions.paddingXSmall,
        ),
        decoration: BoxDecoration(
          color: AppColors.primaryGradientStart.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(
            AppDimensions.borderRadiusSmall,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelStyle.copyWith(
            color: AppColors.primaryGradientStart,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  int _getStarCount(SleepProvider provider) {
    if (provider.latestRecord == null) return 0;

    final duration = provider.latestRecord!.wakeTime.difference(
      provider.latestRecord!.bedtime,
    );

    final adjustedDuration =
        duration.isNegative ? duration + Duration(days: 1) : duration;

    final hours = adjustedDuration.inHours.toDouble();

    if (hours >= 7) return 5;
    if (hours >= 6) return 4;
    if (hours >= 5) return 3;
    if (hours >= 4) return 2;
    return 1;
  }

  String _getCurrentTime() {
    DateTime now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}