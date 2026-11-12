import 'package:flutter/cupertino.dart';  // ← CupertinoSwitch 用
import 'package:flutter/foundation.dart' show kDebugMode;  // N129 2/2 D2
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';  // ========== Week 25+ 追加 ==========
import 'package:shiftsleep/constants/calendar_range.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/screens/vacation_settings_screen.dart';
import 'package:shiftsleep/screens/vacation_usage_screen.dart';
import 'package:shiftsleep/services/alarm_reschedule.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/daily_wake_toggle.dart';  // N147
import 'package:shiftsleep/services/pre_alarm_reschedule_service.dart';
import 'package:shiftsleep/services/premium_service.dart';
import 'package:shiftsleep/services/settings_load_state.dart';  // N118 2/4 2c
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/services/wake_alarm_choice.dart';  // N19
import 'package:shiftsleep/services/wake_alarm_registration_service.dart';  // N19
import 'package:shiftsleep/services/wake_time_change.dart';  // N166
import '../services/manual_wake_service.dart';

class SettingsScreen extends StatefulWidget {
  final String userId;

  const SettingsScreen({
    super.key,
    required this.userId,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TimeOfDay _wakeUpTime = const TimeOfDay(hour: 7, minute: 0);
  AlarmMode _alarmMode = AlarmMode.once;
  String _selectedAlarmSound = 'default';
  double _soundVolume = 1.0;
  int _alarmTimeBeforeShift = 30;
  bool _advicePromoVisible = true;
  bool _isPremiumUser = false;
  bool _isAlarmEnabled = true;  // ✨ 🆕 追加：デフォルト true
  // N123：ON の登録し直し・OFF の取り消しの処理中はスイッチを押せない
  // N124：アラーム音の保存（登録し直し）とも共通の「アラーム処理中」フラグ。立っている間はスイッチと保存ボタンの両方を押せない
  bool _isAlarmBusy = false;
  // N118 2/4 2c：設定を読み込めたか（行がなかったときも true）。false のあいだ（読み込み中・失敗中）は
  //    画面の値を変える・保存する操作を押せない（既定値で DB を上書きしないため）
  bool _settingsLoaded = false;
  // N118 2/4 2c：読み込みに失敗した（バナーと［再読み込み］を出す。読み込み中は出さない）
  bool _settingsLoadFailed = false;
  // N118 2/4 2c：再読み込み中（二度押し防止）
  bool _isReloadingSettings = false;
  bool _isLoading = false;
  String? _vacationAccrualDate;
  // ========== Week 25+ 新規追加：毎日設定チェックボックス ==========
  bool _useDailyWakeUpSetting = false;  // チェックボックスの状態
  bool _hasManualWakeTonight = false;  // ✅ N10: 今夜の手動起床が有効か（予約 or 毎日設定）
  // ================================================================

  final ShiftRepository _shiftRepository = ShiftRepository();
  final PremiumService _premiumService = PremiumService();
  // N128：休日パターン（_dayOffPattern）は PreAlarmRescheduleService.dayOffPattern に移した
  AppSettings? _currentSettings;  // ← 追加：現在の設定を保持

  /// _currentSettings を デフォルト値で初期化
  void _initializeCurrentSettings() {
    _currentSettings ??= AppSettings(
      id: 1,
      userId: 'test_user',
      alarmTimeBeforeShift: 30,
      wakeUpTime: '07:00',
      selectedAlarmSound: 'default',
      advicePromoVisible: true,
      isPremiumUser: false,
      isAlarmEnabled: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeCurrentSettings();  // ← 追加
    _loadSettings();
    // ========== Week 25+ 新規追加：SharedPreferences からチェックボックス状態を読み込み ==========
    // N154：毎日使用フラグと今夜の手動起床の有無は _loadSettings の中で読む（読めなければバナー）
    _loadAlarmEnabledSetting();  // ✅ H4: 保存済みの ON/OFF をスイッチに反映
    // ============================================================
  }

  /// DB から設定を読み込む
  /// N118 2/4 2c：読めたら（行がなかったときも）true。読めなければ _settingsLoadFailed を立てて false
  Future<bool> _loadSettings() async {
    try {
      final settings = await _shiftRepository.getAppSettings('test_user');
      // N26：RevenueCat が configure されていないときは、DB の値によらず無料版として表示する
      final isPremium = (settings?.isPremiumUser ?? false) &&
          await _premiumService.isRevenueCatConfigured();
      // N154：毎日使用フラグと今夜の手動起床の有無も同じ try で読む（読めなければ既定の表示のまま押せなくする）
      final isDaily = await ManualWakeService.isDaily();
      final hasTonight = (await ManualWakeService.getActive()) != null;

      // N118 2/4 2c：起床時刻を読めない値も「読み込めなかった」に含めるため、setState の前に変換する
      TimeOfDay? wakeUpTime;
      if (settings != null) {
        print('✅ 設定を読み込み: 起床時刻=${settings.wakeUpTime}, アラーム時間=${settings.alarmTimeBeforeShift}分前, 音=${settings.selectedAlarmSound}, promoVisible=${settings.advicePromoVisible}, isPremium=${settings.isPremiumUser}');

        // ✨ ここを追加：wakeUpTime を "07:00" 形式から TimeOfDay に変換
        final timeParts = settings.wakeUpTime.split(':');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        wakeUpTime = TimeOfDay(hour: hour, minute: minute);
      }

      if (!mounted) return false;
      setState(() {
        if (settings != null) {
          _currentSettings = settings;  // ← 追加：現在の設定を保存
          _wakeUpTime = wakeUpTime!;
          _alarmTimeBeforeShift = settings.alarmTimeBeforeShift;
          _selectedAlarmSound = settings.selectedAlarmSound;
          _advicePromoVisible = settings.advicePromoVisible;
          _isPremiumUser = isPremium;
          // isAlarmEnabled は削除
        }
        _useDailyWakeUpSetting = isDaily;  // N154
        _hasManualWakeTonight = hasTonight;  // N154
        // N118 2/4 2c：行がなければ既定値のまま（今と同じ）。どちらも読み込めたので操作を押せるようにする
        _settingsLoaded = true;
        _settingsLoadFailed = false;
      });
      return true;
    } catch (e) {
      print('⚠️ 設定読み込みエラー: $e');
      // N118 2/4 2c：既定値を表示したまま保存しないよう、操作を押せなくしてバナーを出す
      if (mounted) {
        setState(() {
          _settingsLoaded = false;
          _settingsLoadFailed = true;
        });
      }
      return false;
    }
  }

  /// N118 2/4 2c：［再読み込み］。成功したらバナーが消える。結果は SnackBar でも知らせる
  Future<void> _reloadSettings() async {
    if (!canReloadSettings(reloading: _isReloadingSettings)) return;
    final messenger = ScaffoldMessenger.of(context);  // await 前に取得
    setState(() => _isReloadingSettings = true);
    final bool succeeded;
    try {
      succeeded = await _loadSettings();
    } finally {
      if (mounted) setState(() => _isReloadingSettings = false);
    }
    final message = settingsReloadMessage(succeeded: succeeded);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message.text),
        backgroundColor: message.color,
        duration: Duration(seconds: message.color == Colors.orange ? 6 : 2),
      ),
    );
  }

  /// N118 2/4 2c：設定を読み込めなかったときのバナー（画面の上に固定）
  Widget _buildLoadFailedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(
        color: AppColors.settingsLoadFailedBg,
        border: Border(left: BorderSide(color: AppColors.settingsLoadFailedAccent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            settingsLoadFailedTitle,
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            settingsLoadFailedBody,
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontSize: 12,
              color: AppColors.textPrimary,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: canReloadSettings(reloading: _isReloadingSettings) ? _reloadSettings : null,
              icon: _isReloadingSettings
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isReloadingSettings ? '読み込み中…' : '再読み込み'),
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ N10/N11: 毎日使用フラグと、今夜の手動起床が有効かを読み込む
  /// N154：「毎日」チェックのあとの読み直し用（最初の読み込みと［再読み込み］は _loadSettings）。
  ///    読めたら true。読めなければ表示は変えずに false（知らせは呼び出し元）
  Future<bool> _loadDailyWakeUpSetting() async {
    final bool isDaily;
    final bool hasTonight;
    try {
      isDaily = await ManualWakeService.isDaily();
      hasTonight = (await ManualWakeService.getActive()) != null;
    } catch (e) {
      debugPrint('❌ N154: 毎日使用フラグ・今夜の手動起床を読み直せませんでした: $e');
      return false;
    }
    if (!mounted) return true;
    setState(() {
      _useDailyWakeUpSetting = isDaily;
      _hasManualWakeTonight = hasTonight;
    });
    return true;
  }

  /// 「この設定を毎日使用する」のチェック
  /// ✅ N11: SharedPreferences に保存（ON は画面に表示中の時刻を毎日使う時刻にする）
  /// N147：睡眠中に ON にしたら、「今から寝る」と同じ判定で起床アラームを登録し直す（OFF はこれまでどおり setDaily が取り消す）
  /// 処理中は _isAlarmBusy を立て、ほかのアラームの操作と重ならないようにする
  /// N166：保存できなかったら ⚠️ で知らせ、「✅ 毎晩…」は出さない
  Future<void> _toggleDailyWakeUp(bool value) async {
    // await の前に取得（画面が閉じられても登録と知らせを続ける）
    final messenger = ScaffoldMessenger.of(context);
    final sleepProvider = context.read<SleepProvider>();
    final displayTime = sleepProvider.autoWakeUpTimeOfDay ?? _wakeUpTime;
    final timeStr = '${displayTime.hour.toString().padLeft(2, '0')}:${displayTime.minute.toString().padLeft(2, '0')}';
    final settings = _currentSettings;
    setState(() {
      _useDailyWakeUpSetting = value;
      _isAlarmBusy = true;
    });
    try {
      var saveFailed = false;
      try {
        if (value) {
          await ManualWakeService.setDaily(true, time: displayTime);
        } else {
          await ManualWakeService.setDaily(false);
        }
      } catch (e) {
        debugPrint('❌ N166: 毎日の設定を保存できませんでした: $e');
        saveFailed = true;
      }
      // 保存できなかったときも、実際に保存されている状態をチェックに出す
      final reloaded = await _loadDailyWakeUpSetting();
      if (saveFailed && !reloaded && mounted) {
        setState(() => _useDailyWakeUpSetting = !value);
      }

      print('[SettingsScreen] 📌 毎日設定チェックボックス: ${value ? "✅ ON" : "❌ OFF"}（保存の失敗: $saveFailed）');

      WakeAlarmRegistrationResult? alarmResult;
      var alarmError = false;
      if (!saveFailed && value && sleepProvider.isSleepingNow && settings != null) {
        try {
          alarmResult = await WakeAlarmRegistrationService.register(
            now: DateTime.now(),
            settings: settings,
            vibrateOnMain: false,
          );
        } catch (e) {
          debugPrint('❌ N147: 毎日 ON のあと、起床アラームを登録できませんでした: $e');
          alarmError = true;
        }
      }

      // N154：読み直せなかったときは成功の知らせの代わりに ⚠️（バナーは出さない）
      final messages = dailyWakeToggleMessages(
        enabled: value,
        timeText: timeStr,
        saveFailed: saveFailed,
        reloadFailed: !reloaded,
        alarmResult: alarmResult,
        alarmError: alarmError,
      );
      messenger.hideCurrentSnackBar();
      for (final message in messages) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(message.text),
            backgroundColor: message.color,
            duration: Duration(seconds: message.seconds),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAlarmBusy = false);
    }
  }

    // ========== 🆕 新規追加：SharedPreferences から アラーム有効フラグを読み込み ==========
    /// SharedPreferences から「アラーム有効」フラグを読み込み
    Future<void> _loadAlarmEnabledSetting() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;  // ✅ H4: 読み込み中に画面が破棄された場合は反映しない
        setState(() {
          _isAlarmEnabled = prefs.getBool('is_alarm_enabled') ?? true;
          // ✅ N49: 保存した音量を読み込む（保存していなければ 100%）
          _soundVolume = (prefs.getInt('alarm_volume_percent') ?? 100).clamp(0, 100) / 100.0;
        });
        print('✅ アラーム有効フラグを読み込み: $_isAlarmEnabled');
      } catch (e) {
        print('⚠️ アラーム有効フラグ読み込みエラー: $e');
      }
    }

    /// SharedPreferences にアラーム有効フラグを保存
    /// N123：保存できたら true（ON の保存に失敗したら登録し直さないため）
    Future<bool> _saveAlarmEnabledSetting(bool value) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = await prefs.setBool('is_alarm_enabled', value);
        print('✅ アラーム有効フラグを保存: $value');
        return saved;
      } catch (e) {
        print('⚠️ アラーム有効フラグ保存エラー: $e');
        return false;
      }
    }

    // ✅ H4: 先に保存（以降の新規登録を止める）→ OFF なら既存の main / pre をキャンセル
    // N123：ON なら DB のシフトから出勤前アラーム（pre）を登録し直す。処理中はスイッチを押せない
    Future<void> _onAlarmEnabledChanged(bool value) async {
      if (_isAlarmBusy) return;
      final messenger = ScaffoldMessenger.of(context);  // await 前に取得
      final sleepProvider = context.read<SleepProvider>();
      setState(() {
        _isAlarmEnabled = value;
        _isAlarmBusy = true;
      });
      try {
        final saved = await _saveAlarmEnabledSetting(value);  // 保存
        print('[Settings] アラーム有効: $value');
        if (!value) {
          await _cancelAllAlarmsForOff(messenger);
        } else if (!saved) {
          // N123：ON を保存できなかったら登録し直さず、スイッチを OFF に戻す
          if (mounted) setState(() => _isAlarmEnabled = false);
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            const SnackBar(
              content: Text('⚠️ アラームの設定を保存できませんでした。もう一度お試しください'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 6),
            ),
          );
        } else {
          await _rescheduleAlarmsForOn(messenger, sleepProvider.isSleepingNow);
        }
      } finally {
        if (mounted) setState(() => _isAlarmBusy = false);
      }
    }

    // N123：アラーム ON 時に、DB の今日〜CalendarRange の終わりの出勤日の pre を登録し直す
    //    分数・音は DB の設定（行がなければ確定と同じく 30 分・'default'）。手動起床（main）は戻さない
    Future<void> _rescheduleAlarmsForOn(ScaffoldMessengerState messenger, bool isSleepingNow) async {
      final result = await PreAlarmRescheduleService.reschedule();

      final message = rescheduleMessage(
        count: result.count,
        errorMessage: AlarmService.alarmErrorMessage(result.errorCode),
        readFailed: result.readFailed,
        alarmDisabled: result.alarmDisabled,
      );
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message.text),
          backgroundColor: message.color,
          duration: Duration(seconds: message.color == Colors.orange ? 6 : 3),
        ),
      );

      // N123：睡眠中で手動起床が有効なら、起床アラーム（main）は戻らないことを知らせる
      if (isSleepingNow) {
        DateTime? manualWakeAt;
        try {
          manualWakeAt = await ManualWakeService.getActive();
        } catch (e) {
          debugPrint('❌ [Settings] アラームON：手動起床を読めませんでした: $e');
        }
        if (manualWakeAt != null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(manualWakeNotRestoredText),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 6),
            ),
          );
        }
      }
    }

    // N128：pre の登録し直し（N124 の _reschedulePreAlarms）は PreAlarmRescheduleService.reschedule に移した

    // ✅ H4: アラームOFF時に、登録済みの main / pre をすべてキャンセル
    //    対象：今日・明日 ＋ DB に存在する今日〜CalendarRange の終わりのシフト日（Set で重複排除）
    //    N123：範囲の終わりを確定の登録（CalendarRange.lastDate）にそろえる
    //    N118 2/4 2c：知らせは呼び出し元が await 前に取った messenger で出す（N133 と同じ。画面が閉じられても飛ばさない）
    Future<void> _cancelAllAlarmsForOff(ScaffoldMessengerState messenger) async {
      try {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final targetDates = <DateTime>{
          today,
          today.add(const Duration(days: 1)),
        };
        // N118：シフトを読めなくても今日・明日の分は取り消し、スイッチは OFF のままで知らせる
        var shiftsReadFailed = false;
        try {
          final shifts = await _shiftRepository.getShiftsForDateRange(
            today,
            CalendarRange.lastDate,
          );
          for (final shift in shifts) {
            final shiftDate = DateTime.tryParse(shift['shift_date'] as String? ?? '');
            if (shiftDate != null) {
              targetDates.add(DateTime(shiftDate.year, shiftDate.month, shiftDate.day));
            }
          }
        } catch (e) {
          debugPrint('❌ [Settings] アラームOFF：シフトを読めませんでした: $e');
          shiftsReadFailed = true;
        }
        for (final date in targetDates) {
          await AlarmService.cancelMainAlarm(date);
          await AlarmService.cancelPreAlarm(date);
        }
        print('🔕 [Settings] アラームOFF: ${targetDates.length}日分の main / pre をキャンセルしました');
        if (shiftsReadFailed) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            const SnackBar(
              content: Text('⚠️ 一部のアラームを取り消せませんでした。もう一度 OFF にしてください'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 6),
            ),
          );
        }
      } catch (e) {
        print('❌ [Settings] アラームOFF時のキャンセルエラー: $e');
      }
    }

    // N124：アラーム音を保存し、アラームが ON なら登録済みの pre を新しい音で登録し直す
    //    保存の直前に DB を読み直し、音だけを変える（画面を開いたときの分数・起床時刻などで上書きしない）
    //    処理中はスイッチと保存ボタンを押せない（_isAlarmBusy）
    Future<void> _saveAlarmSound() async {
      // N118 2/4 2c：設定を読み込めるまでは保存しない（画面の既定の音で DB を上書きしない）
      if (!canEditSettings(loaded: _settingsLoaded, alarmBusy: _isAlarmBusy)) return;
      final messenger = ScaffoldMessenger.of(context);  // await 前に取得
      setState(() => _isAlarmBusy = true);
      try {
        final AppSettings updatedSettings;
        try {
          // 行がなければ今の _currentSettings を元にする（今と同じ）。読めなければ保存しない
          final base = await _shiftRepository.getAppSettings('test_user') ?? _currentSettings;
          if (base == null) {
            messenger.showSnackBar(
              const SnackBar(content: Text('❌ 設定が読み込まれていません')),
            );
            return;
          }

          // selectedAlarmSound のみ更新
          updatedSettings = base.copyWith(selectedAlarmSound: _selectedAlarmSound);

          await _shiftRepository.createOrUpdateAppSettings(updatedSettings);
          // ✅ N49: 音量も一緒に保存する（0〜100。アラームが鳴るときにネイティブ側が読む）
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('alarm_volume_percent', (_soundVolume * 100).round());
        } catch (e) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('❌ アラーム音を保存できませんでした。もう一度お試しください'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          debugPrint('❌ [Error] 保存エラー: $e');
          return;
        }

        // ✅ N12: 画面が閉じられていたら setState しない（登録し直しは続ける）
        if (mounted) setState(() => _currentSettings = updatedSettings);

        // OFF なら登録し直さない（scheduleAlarmForShift は OFF だと成功扱いの null を返し、件数を誤って数えるため先に分ける）
        final List<({String text, Color? color})> messages;
        if (await AlarmService.isAlarmEnabled()) {
          final result = await PreAlarmRescheduleService.reschedule();
          messages = soundSaveMessages(
            count: result.count,
            errorMessage: AlarmService.alarmErrorMessage(result.errorCode),
            readFailed: result.readFailed,
            alarmDisabled: result.alarmDisabled,
          );
        } else {
          debugPrint('🔕 [Settings] アラームOFFのため、音の保存で pre は登録し直しません');
          messages = [(text: soundSavedText, color: null)];
        }

        // ✅ と ⚠️ は前を消さずに続けて出す（両方読めるように）
        messenger.hideCurrentSnackBar();
        for (final message in messages) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(message.text),
              backgroundColor: message.color,
              duration: Duration(seconds: message.color == Colors.orange ? 6 : 2),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isAlarmBusy = false);
      }
    }
    // ===========================================================================================================================================

  @override
  Widget build(BuildContext context) {
    // N118 2/4 2c：読み込めるまで（読み込み中・失敗中）とアラームの処理中は、値を変える・保存する操作を押せない
    final canEdit = canEditSettings(loaded: _settingsLoaded, alarmBusy: _isAlarmBusy);
    return Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          backgroundColor: AppColors.backgroundLight,
          elevation: 0,
          centerTitle: true,
          title: Text(
            '設定',
            style: AppTextStyles.headerStyle,
          ),
          foregroundColor: AppColors.textPrimary,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(
              color: AppColors.borderDefault,
              height: 1.0,
            ),
          ),
        ),
        // N118 2/4 2c：読み込めなかったときはバナーを上に固定（スクロールしても消えない）
        body: Column(
          children: [
            if (_settingsLoadFailed) _buildLoadFailedBanner(),
            Expanded(
              child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppDimensions.sectionPaddingVertical,
              horizontal: AppDimensions.sectionPaddingHorizontal,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ========== プレミアム版ステータスセクション ==========
                Text(
                  '💳 プレミアム版ステータス',
                  style: AppTextStyles.sectionTitleStyle,
                ),
                const SizedBox(height: AppDimensions.paddingMedium),

                Container(
                  padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                  decoration: BoxDecoration(
                    color: _isPremiumUser
                        ? Colors.green.withValues(alpha: 0.05)
                        : Colors.grey.withValues(alpha: 0.05),
                    border: Border.all(
                      color: _isPremiumUser
                          ? Colors.green
                          : AppColors.borderDefault,
                    ),
                    borderRadius: BorderRadius.circular(
                      AppDimensions.borderRadiusMedium,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'あなたのプラン',
                                style: AppTextStyles.bodyTextStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8.0),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12.0,
                                  vertical: 4.0,
                                ),
                                decoration: BoxDecoration(
                                  color: _isPremiumUser
                                      ? Colors.green
                                      : AppColors.textMuted,
                                  borderRadius: BorderRadius.circular(12.0),
                                ),
                                child: Text(
                                  _isPremiumUser ? 'プレミアム版 ✨' : '無料版',
                                  style: AppTextStyles.bodyTextStyle.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            _isPremiumUser ? Icons.check_circle : Icons.info,
                            color: _isPremiumUser ? Colors.green : AppColors.textMuted,
                            size: 40,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.paddingMedium),

                      if (!_isPremiumUser) ...[
                        Text(
                          'プレミアム版でできることは：',
                          style: AppTextStyles.bodyTextStyle.copyWith(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8.0),
                        _buildBenefitItem('📊 詳細なアドバイスを取得'),
                        _buildBenefitItem('🎯 最大5つの改善提案'),
                        _buildBenefitItem('💾 すべての睡眠データを保存'),
                        const SizedBox(height: AppDimensions.paddingMedium),
                      ],

                      if (!_isPremiumUser)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _showPaywall,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGradientStart,
                              disabledBackgroundColor: AppColors.textMuted,
                              padding: EdgeInsets.symmetric(
                                vertical: AppDimensions.paddingMedium,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppDimensions.borderRadiusMedium,
                                ),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    '✨ プレミアム版にアップグレード（¥980/月）',
                                    style: AppTextStyles.bodyTextStyle.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            vertical: AppDimensions.paddingMedium,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                              AppDimensions.borderRadiusMedium,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '✅ プレミアム版をご利用中です',
                              style: AppTextStyles.bodyTextStyle.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      Text(
                        '💡 改善アドバイス表示設定',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'プレミアム版案内を表示',
                                style: AppTextStyles.bodyTextStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4.0),
                              Text(
                                'アドバイス詳細画面で有料版の\nプロモーション表示を ON/OFF',
                                style: AppTextStyles.bodyTextStyle.copyWith(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          // N118 2/4 2c：読み込めるまでとアラームの処理中は押せない
                          Switch(
                            value: _advicePromoVisible,
                            onChanged: canEdit
                                ? (value) {
                                    setState(() {
                                      _advicePromoVisible = value;
                                    });
                                  }
                                : null,
                            activeThumbColor: AppColors.primaryGradientStart,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppDimensions.paddingLarge),
                const SizedBox(height: AppDimensions.paddingLarge),

                // ========================
                // アラーム設定セクション
                // ========================
                Text(
                  '🔔 アラーム設定',
                  style: AppTextStyles.sectionTitleStyle,
                ),
                const SizedBox(height: AppDimensions.paddingMedium),

                Container(
                  padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.borderDefault),
                    borderRadius: BorderRadius.circular(
                      AppDimensions.borderRadiusMedium,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ========== Week 25+ 修正：起床時刻セクション ==========
                      Text(
                        '起床時刻',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Consumer<SleepProvider>(
                        builder: (context, sleepProvider, _) {
                          final displayWakeUpTime = sleepProvider.autoWakeUpTimeOfDay ?? _wakeUpTime;
                          // ✅ N10: 毎日 OFF で今夜の予約がないときはグレー表示＋文字で説明
                          final isUnsetTonight = !_useDailyWakeUpSetting && !_hasManualWakeTonight;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(
                            children: [
                              // ✨ 🆕 追加：Toggle Switch
                              CupertinoSwitch(
                                value: _isAlarmEnabled,
                                // N123：処理中は押せない（null で無効表示）
                                onChanged: _isAlarmBusy ? null : _onAlarmEnabledChanged,
                              ),
                              const SizedBox(width: 12),
                              
                              // 時刻表示
                              Text(
                                '${displayWakeUpTime.hour.toString().padLeft(2, '0')}:${displayWakeUpTime.minute.toString().padLeft(2, '0')}',
                                style: isUnsetTonight
                                    ? AppTextStyles.largeNumberStyle.copyWith(fontSize: 32, color: AppColors.textMuted)
                                    : AppTextStyles.largeNumberStyle.copyWith(fontSize: 32),
                              ),
                              const Spacer(),
                              
                              // 変更ボタン
                              // N125：アラームの処理中は押せない
                              // N118 2/4 2c：設定を読み込めるまでも押せない
                              ElevatedButton(
                                onPressed: canEdit ? () => _selectWakeUpTime(context) : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryGradientStart,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
                                  ),
                                ),
                                child: const Text(
                                  '変更',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                              if (isUnsetTonight)
                                Text(
                                  '今夜は未設定（「変更」で予約）',
                                  style: AppTextStyles.bodyTextStyle.copyWith(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: AppDimensions.paddingMedium),

                      // ========== Week 25+ 新規追加：チェックボックス「毎日この設定を使用する」==========
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.cardBgGray,
                          borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
                        ),
                        child: CheckboxListTile(
                          title: Text(
                            '□ この設定を毎日使用する',
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            'ON：毎晩この時刻で起こします\nOFF：「変更」で選んだ夜だけ使います\n※出勤前アラームの方が早い日はそちらを優先します',
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          value: _useDailyWakeUpSetting,
                          // N118 2/4 2c：読み込めるまでとアラームの処理中は押せない（表示中の既定の時刻を毎日の時刻にしない）
                          onChanged: !canEdit ? null : (bool? value) async {
                            if (value != null) await _toggleDailyWakeUp(value);
                          },
                          activeColor: AppColors.primaryGradientStart,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppDimensions.paddingSmall,
                            vertical: AppDimensions.paddingSmall,
                          ),
                        ),
                      ),
                      // ================================================================

                      const SizedBox(height: AppDimensions.paddingLarge),

                      // 出勤前アラーム設定
                      Text(
                        '出勤前アラーム',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        'シフト出勤予定時刻の何分前に通知します',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      DropdownButton<int>(
                        value: _alarmTimeBeforeShift,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('無効（アラームなし）'),
                          ),
                          ...List.generate(
                            (180 - 30) ~/ 10 + 1,
                            (index) {
                              final minutes = 30 + (index * 10);
                              return DropdownMenuItem(
                                value: minutes,
                                child: Text('$minutes分前'),
                              );
                            },
                          ),
                        ],
                        // N118 2/4 2c：読み込めるまでとアラームの処理中は押せない
                        onChanged: !canEdit ? null : (value) {
                          if (value != null) {
                            setState(() {
                              _alarmTimeBeforeShift = value;
                            });
                            _updateWakeUpTimeInProvider();
                          }
                        },
                      ),
                      const SizedBox(height: AppDimensions.paddingLarge),

                      // アラームモード選択
                      Text(
                        'アラームモード',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        children: [
                          Expanded(
                            child: _buildAlarmModeButton(AlarmMode.none),
                          ),
                          const SizedBox(width: AppDimensions.paddingSmall),
                          Expanded(
                            child: _buildAlarmModeButton(AlarmMode.once),
                          ),
                          const SizedBox(width: AppDimensions.paddingSmall),
                          Expanded(
                            child: _buildAlarmModeButton(AlarmMode.twice),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.paddingLarge),

                      // アラーム音選択
                      Text(
                        'アラーム音',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      DropdownButton<String>(
                        value: _selectedAlarmSound,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'default', child: Text('デフォルト音')),
                          DropdownMenuItem(value: 'gentle', child: Text('やさしい音')),
                          DropdownMenuItem(value: 'harsh', child: Text('強めの音')),
                        ],
                        // N118 2/4 2c：読み込めるまでとアラームの処理中は押せない
                        onChanged: !canEdit ? null : (value) {
                          setState(() {
                            _selectedAlarmSound = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // ✅ アラーム音保存ボタン（単独）
                      // N124：アラームの処理中（ON/OFF・音の保存）は押せない
                      // N118 2/4 2c：設定を読み込めるまでも押せない
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: canEdit ? _saveAlarmSound : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGradientStart,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            '🔊 アラーム音を保存',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDimensions.paddingLarge),

                      // 音量調整
                      Text(
                        '音量',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        children: [
                          Icon(
                            Icons.volume_down,
                            color: AppColors.textMuted,
                          ),
                          Expanded(
                            child: Slider(
                              value: _soundVolume,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (value) {
                                setState(() {
                                  _soundVolume = value;
                                });
                              },
                              activeColor:
                                  AppColors.primaryGradientStart,
                              inactiveColor: AppColors.borderDefault,
                            ),
                          ),
                          Icon(
                            Icons.volume_up,
                            color: AppColors.primaryGradientStart,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.paddingLarge),

                      // テストアラームボタン
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _testAlarmSound,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.warningRed,
                          ),
                          child: Text(
                            '🔊 テストアラーム',
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      // N129 2/2 D2：シフトを使わずに本番の経路で鳴らす（デバッグのときだけ）
                      if (kDebugMode) ...[
                        const SizedBox(height: AppDimensions.paddingSmall),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _scheduleDebugAlarm,
                            child: const Text('🧪 10 秒後に鳴らす（デバッグ）'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: AppDimensions.paddingLarge),
                const SizedBox(height: AppDimensions.paddingLarge),

                // ========================
                // 有給管理セクション
                // ========================
                Text(
                  '💼 有給管理',
                  style: AppTextStyles.sectionTitleStyle,
                ),
                const SizedBox(height: AppDimensions.paddingMedium),

                Container(
                  padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.borderDefault),
                    borderRadius: BorderRadius.circular(
                      AppDimensions.borderRadiusMedium,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      

                      // 
                      const SizedBox(height: 20),
                      // ========================
                      // ⚙️ 有給設定ボタン（入社日・付与日数）
                      // ========================
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VacationSettingsScreen(
                                  userId: widget.userId,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGradientStart,
                            padding: EdgeInsets.symmetric(vertical: AppDimensions.paddingMedium),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
                            ),
                          ),
                          child: Text(
                            '⚙️ 有給設定（入社日・付与日数）',
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),

                      
                      // 
                      const SizedBox(height: 20),

                      // ========================
                      // 📝 有給使用記録ボタン
                      // ========================
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VacationUsageScreen(
                                  userId: widget.userId,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGradientStart,
                            padding: EdgeInsets.symmetric(vertical: AppDimensions.paddingMedium),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
                            ),
                          ),
                          // ========================
                          // 📝 有給使用記録ボタン
                          // ========================
                          child: Text(
                            '📝 有給使用記録',
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),

                      Text(
                        '付与日の設定',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        '有給休暇が付与される日付を設定します（月/日）',
                        style: AppTextStyles.bodyTextStyle.copyWith(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      TextFormField(
                        initialValue: _vacationAccrualDate ?? '10/01',
                        decoration: InputDecoration(
                          hintText: '月/日 例: 10/01',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _vacationAccrualDate = value;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) return '月/日を入力してください';
                          final parts = value.split('/');
                          if (parts.length != 2) return '月/日の形式で入力してください';
                          final month = int.tryParse(parts[0]);
                          final day = int.tryParse(parts[1]);
                          if (month == null || day == null) return '数字を入力してください';
                          if (month < 1 || month > 12) return '月は1～12で入力してください';
                          if (day < 1 || day > 31) return '日は1～31で入力してください';
                          return null;
                        },
                      ),
                      
                    ],
                  ),
                ),

                // ========================
                // 保存ボタン
                // ========================
                // N125：アラームの処理中は押せない
                // N118 2/4 2c：設定を読み込めるまでも押せない
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canEdit ? _saveSettings : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGradientStart,
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
                      '設定を保存',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppDimensions.paddingLarge),
              ],
            ),
          ),
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildBenefitItem(String benefit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(
        benefit,
        style: AppTextStyles.bodyTextStyle.copyWith(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Future<void> _showPaywall() async {
    try {
      setState(() {
        _isLoading = true;
      });

      print('[SettingsScreen] 💳 有料版ステータスを確認中...');

      final isPremium = await _premiumService.checkPremiumStatus(userId: 'test_user');

      print('[SettingsScreen] ✅ 有料版ステータス確認完了: $isPremium');

      if (mounted) {
        setState(() {
          _isPremiumUser = isPremium;
        });

        if (context.mounted) {
          final sleepProvider = context.read<SleepProvider>();
          sleepProvider.setPremiumStatus(isPremium);
        }

        if (isPremium) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✨ プレミアム版をご利用中です！'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('無料版をご利用中です。プレミアム版でさらに多くの機能をご利用いただけます。'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[SettingsScreen] ❌ 有料版確認エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ プレミアム版の状態を確認できませんでした。しばらくしてからもう一度お試しください'),
            backgroundColor: AppColors.warningRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildAlarmModeButton(AlarmMode mode) {
    final isSelected = _alarmMode == mode;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _alarmMode = mode;
          });
        },
        borderRadius:
            BorderRadius.circular(AppDimensions.borderRadiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 10.0,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryGradientStart.withValues(alpha: 0.1)
                : AppColors.cardBgGray,
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryGradientStart
                  : AppColors.borderDefault,
              width: isSelected ? 2.0 : 1.0,
            ),
            borderRadius: BorderRadius.circular(
              AppDimensions.borderRadiusSmall,
            ),
          ),
          child: Text(
            mode.displayName,
            style: AppTextStyles.bodyTextStyle.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? AppColors.primaryGradientStart
                  : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Future<void> _selectWakeUpTime(BuildContext context) async {
    // N125：処理中は何もしない（ManualWakeService.save だけ先に動かないように）
    // N118 2/4 2c：設定を読み込めるまでも何もしない（画面の既定の分数で DB を上書きしない）
    if (!canEditSettings(loaded: _settingsLoaded, alarmBusy: _isAlarmBusy)) return;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _wakeUpTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primaryGradientStart,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && context.mounted) {
      // N19：保存の途中でタブを切り替えても再登録と知らせを続けられるよう、最初の await より前に取得
      final messenger = ScaffoldMessenger.of(context);
      final sleepProvider = context.read<SleepProvider>();
      final previousWakeUpTime = _wakeUpTime;  // N166：保存できなかったら戻す
      setState(() {
        _wakeUpTime = picked;
      });

      // ✅ N4: 手動起床時刻を「今夜だけ有効」として保存（「今から寝る」で使う）
      var saveFailed = false;
      try {
        await ManualWakeService.save(picked);
      } catch (e) {
        debugPrint('❌ N166: 起床時刻（今夜だけの予約）を保存できませんでした: $e');
        saveFailed = true;
      }
      // ✅ N11: 毎日 ON なら毎日使う時刻も更新（N166：save が失敗したら書かない。戻した表示と合わなくなるため）
      var dailyFailed = false;
      if (!saveFailed && _useDailyWakeUpSetting) {
        try {
          await ManualWakeService.setDaily(true, time: picked);
        } catch (e) {
          debugPrint('❌ N166: 起床時刻の変更で「毎日」の設定を保存できませんでした: $e');
          dailyFailed = true;
        }
      }
      final messages = wakeTimeChangeMessages(saveFailed: saveFailed, dailyFailed: dailyFailed);

      // N166：save が失敗したら元の時刻に戻し、実際に保存されている状態を読み直して ⚠️。DB の保存へは進まない
      if (!shouldSaveSettingsAfterWakeTimeChange(saveFailed: saveFailed)) {
        if (mounted) setState(() => _wakeUpTime = previousWakeUpTime);
        await _loadDailyWakeUpSetting();
        _showWakeTimeChangeMessages(messenger, messages);
        return;
      }

      if (mounted) {
        setState(() {
          _hasManualWakeTonight = true;
        });
      }
      // N166：「毎日」を書けなかったら、チェックを保存されている状態に読み直す
      if (dailyFailed) await _loadDailyWakeUpSetting();

      // ========== 🆕 修正：DB 保存 → プロバイダー更新 → アラーム再登録（就寝中の場合） ==========
      await _saveSettings(messenger: messenger, sleepProvider: sleepProvider);
      // N166：「毎日」の ⚠️ は _saveSettings の ✅ のあとに出す
      _showWakeTimeChangeMessages(messenger, messages);
    }
  }

  /// N166：起床時刻の［変更］のあとの ⚠️ を順に出す（前の知らせは消さない）
  void _showWakeTimeChangeMessages(
    ScaffoldMessengerState messenger,
    List<({String text, Color? color, int seconds})> messages,
  ) {
    for (final message in messages) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message.text),
          backgroundColor: message.color,
          duration: Duration(seconds: message.seconds),
        ),
      );
    }
  }

  Future<void> _testAlarmSound() async {
    print('🔊 テストアラーム開始...');
    await AlarmService.showTestNotification(
      selectedAlarmSound: _selectedAlarmSound,
      volume: _soundVolume,
    );

    if (mounted) {
      final volumePercent = (_soundVolume * 100).toStringAsFixed(0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('テストアラーム再生中...（音量: $volumePercent%、2秒で停止）'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// N129 2/2 D2：10 秒後に鳴らす（デバッグ）。音は DB の設定（行がない・読めないときは 'default'）
  Future<void> _scheduleDebugAlarm() async {
    final messenger = ScaffoldMessenger.of(context);  // await 前に取得
    var sound = 'default';
    try {
      final settings = await _shiftRepository.getAppSettings('test_user');
      sound = settings?.selectedAlarmSound ?? 'default';
    } catch (e) {
      debugPrint('❌ [Settings] デバッグ用アラームの設定を読めませんでした（default で鳴らします）: $e');
    }

    final errorCode = await AlarmService.scheduleDebugAlarm(selectedAlarmSound: sound);
    final error = AlarmService.alarmErrorMessage(errorCode);
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? '🧪 10 秒後に鳴らします（音: $sound）'),
        backgroundColor: error == null ? null : Colors.orange,
        duration: Duration(seconds: error == null ? 3 : 6),
      ),
    );
  }

  // ========== 🆕 Week 26+ Step 6：完全な _saveSettings() 実装 ==========
  // N125：処理中はスイッチ・音の保存・設定の保存・起床時刻の変更を押せない（_isAlarmBusy）
  // N19：messenger・sleepProvider は await の前に取ったもの（ボタンから呼ぶときは省略でき、ここで取る）
  Future<void> _saveSettings({ScaffoldMessengerState? messenger, SleepProvider? sleepProvider}) async {
    // N118 2/4 2c：設定を読み込めるまでは保存しない（画面の既定値で DB を上書きしない）
    if (!canEditSettings(loaded: _settingsLoaded, alarmBusy: _isAlarmBusy)) return;
    final resolvedMessenger = messenger ?? ScaffoldMessenger.of(context);
    final resolvedProvider = sleepProvider ?? context.read<SleepProvider>();
    if (mounted) setState(() => _isAlarmBusy = true);
    try {
      await _saveSettingsSteps(resolvedMessenger, resolvedProvider);
    } finally {
      if (mounted) setState(() => _isAlarmBusy = false);
    }
  }

  // N125：保存の直前に DB を読み直し、分数・起床時刻・案内表示だけを変える（音は「アラーム音の保存」ボタンだけで保存する）
  //    分数が変わっていてアラームが ON なら、pre を取り消して新しい分数で登録し直す（0 なら取り消すだけ）
  // N19：画面が閉じられていても最後まで進める（知らせは先に取った messenger で出す）
  Future<void> _saveSettingsSteps(ScaffoldMessengerState messenger, SleepProvider sleepProvider) async {
    final AppSettings savedSettings;
    final int oldMinutes;
    try {
      // ========== Step 1️⃣：既存の設定を読み直す（行がなければ _currentSettings を元にする） ==========
      print('[Settings] 💾 Step 1️⃣ 既存設定を読み込み中...');

      final currentSettings = await _shiftRepository.getAppSettings('test_user');

      if (currentSettings == null) {
        print('[Settings] ⚠️ 既存設定が見つかりません。画面の設定を元にします。');
      }
      final base = currentSettings ?? _currentSettings;
      if (base == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('❌ 設定が読み込まれていません')),
        );
        return;
      }
      oldMinutes = currentSettings?.alarmTimeBeforeShift ?? 30;

      // ========== Step 2️⃣：分数・起床時刻・案内表示だけを変える ==========
      print('[Settings] 🔄 Step 2️⃣ 新しい AppSettings を構築中...');
      print('[Settings] 📌 起床時刻=${_wakeUpTime.hour}:${_wakeUpTime.minute.toString().padLeft(2, '0')}');

      final wakeUpTimeStr = '${_wakeUpTime.hour.toString().padLeft(2, '0')}:${_wakeUpTime.minute.toString().padLeft(2, '0')}';

      savedSettings = settingsToSave(
        base,
        alarmTimeBeforeShift: _alarmTimeBeforeShift,
        wakeUpTime: wakeUpTimeStr,
        advicePromoVisible: _advicePromoVisible,
      );

      print('[Settings] 📤 新しい AppSettings: $savedSettings');

      // ========== Step 3️⃣：DB に保存 ==========
      print('[Settings] 💾 Step 3️⃣ DB に保存中...');

      await _shiftRepository.createOrUpdateAppSettings(savedSettings);

      print('✅ Step 3️⃣ DB 保存完了！');

    } catch (e) {
      debugPrint('❌ Step 1-3 実行エラー: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('❌ 設定を保存できませんでした。もう一度お試しください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // N125：保存できたら _currentSettings を保存した値にする（N124 にそろえる）
    if (mounted) setState(() => _currentSettings = savedSettings);

    // ========== Step 3.5：分数が変わったら pre を合わせる（画面が閉じられていても続ける） ==========
    final preResult = await _applyPreMinutesChange(oldMinutes, savedSettings.alarmTimeBeforeShift);

    try {
      // ========== Step 4️⃣：SleepProvider に起床時刻を更新 ==========
      print('[Settings] 🔄 Step 4️⃣ プロバイダーを更新...');

      // 新しい起床時刻の DateTime を作成
      final now = DateTime.now();
      final wakeUpDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        _wakeUpTime.hour,
        _wakeUpTime.minute,
      );
      
      // Provider に設定
      sleepProvider.setAutoWakeUpTime(wakeUpDateTime);
      
      print('✅ Step 4️⃣ プロバイダー更新完了！');
      print('[Settings] 📌 Provider の autoWakeUpTimeOfDay = ${_wakeUpTime.hour}:${_wakeUpTime.minute.toString().padLeft(2, '0')}');
      
    } catch (e) {
      debugPrint('❌ Step 4 実行エラー: $e');
      messenger.showSnackBar(
        const SnackBar(
          content: Text('❌ 設定は保存しましたが、起床時刻を画面に反映できませんでした。もう一度［設定を保存］を押してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    WakeAlarmRegistrationResult? alarmResult;  // N19：睡眠中に登録した結果（起床中は null）
    String? alarmError;  // ✅ N22: アラーム再登録の失敗文言（null=成功／起床中）
    try {
      // ========== Step 5️⃣：就寝中の場合、アラーム再登録 ==========
      print('[Settings] 🔍 Step 5️⃣ 就寝状態を確認...');

            print('[Settings] 🔍 isSleepingNow = ${sleepProvider.isSleepingNow}');

      if (sleepProvider.isSleepingNow) {
        print('[Settings] 🔗 就寝中です。アラーム再登録を開始...');
        // N19：「今から寝る」と同じ判定で登録する。手動起床がなければ main は登録しない
        alarmResult = await WakeAlarmRegistrationService.register(
          now: DateTime.now(),
          settings: savedSettings,
          vibrateOnMain: false,
        );
      } else {
        print('[Settings] 🛑 起床中のため、アラーム登録をスキップします');

        // 🟠 起床中の警告メッセージを表示
        messenger.showSnackBar(
          const SnackBar(
            content: Text('⚠️ 起床中のため、アラームは登録されません。今から寝るボタンを押さないとアラームはなりません'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }

    } catch (e) {
      print('❌ Step 5 実行エラー: $e');
      // N19：登録できていないかもしれないので知らせる
      alarmError = '⚠️ 起床時刻は保存しましたが、アラームを設定できませんでした';
    }

    // ========== Step 6️⃣：ユーザーに成功を通知 ==========
    // ✅ N22: アラーム登録に失敗したときはオレンジだけを出す（緑の「更新されました」は出さない）
    // N125：pre の結果を成功の文言の括弧、または続けて出すオレンジで知らせる（前を消さない）
    // N19：登録の結果の ⚠️ は N22 と同じ扱い、⏰ の案内は最後に出す
    final alarmMessages = alarmResult == null ? const <({String text, Color? color})>[] : wakeAlarmMessages(alarmResult);
    final alarmWarnings = alarmMessages.where((message) => message.color != null).map((message) => message.text);
    // N19：睡眠中で手動起床がないときは main を登録しないので、「起床時刻を更新」とは出さない
    final savedText = alarmResult != null && alarmResult.manualWakeAt == null
        ? '✅ 設定を保存しました'
        : '✅ 起床時刻 ${_wakeUpTime.hour}:${_wakeUpTime.minute.toString().padLeft(2, '0')} に更新されました';
    final messages = [
      ...settingsSaveMessages(
        savedText: savedText,
        mainAlarmError: alarmError ?? (alarmWarnings.isEmpty ? null : alarmWarnings.join('\n')),
        preAction: preResult.action,
        preCount: preResult.count,
        preErrorMessage: AlarmService.alarmErrorMessage(preResult.errorCode),
        preReadFailed: preResult.readFailed,
      ),
      ...alarmMessages.where((message) => message.color == null),
    ];
    for (final message in messages) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message.text),
          backgroundColor: message.color,
          duration: Duration(seconds: message.color == Colors.green ? 2 : 6),
        ),
      );
    }

    print('✅ Step 6️⃣ すべて完了！');
  }

  // N125：分数が変わっていてアラームが ON なら、DB の今日〜CalendarRange の終わりの pre を取り消し、
  //    新しい分数が 1 以上なら登録し直す。main には触らない。分数が同じ・OFF なら none
  //    先にシフトの行を読み、読めなければ何も取り消さない（取り消したのに登録できなかった、を防ぐ）
  Future<({PreMinutesAction action, int count, String? errorCode, bool readFailed})> _applyPreMinutesChange(
    int oldMinutes,
    int newMinutes,
  ) async {
    const none = (action: PreMinutesAction.none, count: 0, errorCode: null, readFailed: false);
    final action = preMinutesAction(oldMinutes, newMinutes);
    if (action == PreMinutesAction.none) return none;
    if (!await AlarmService.isAlarmEnabled()) {
      debugPrint('🔕 [Settings] アラームOFFのため、分数の変更（$oldMinutes→$newMinutes分）で pre は合わせません');
      return none;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final List<DateTime> cancelDates;
    try {
      final rows = await _shiftRepository.getShiftsForDateRange(today, CalendarRange.lastDate);
      cancelDates = preAlarmCancelDates(rows, today, CalendarRange.lastDate);
    } catch (e) {
      debugPrint('❌ [Settings] 分数の変更：シフトを読めなかったため、pre は取り消しません: $e');
      return (action: action, count: 0, errorCode: null, readFailed: true);
    }

    var cancelFailed = false;
    for (final date in cancelDates) {
      try {
        await AlarmService.cancelPreAlarm(date);
      } catch (e) {
        debugPrint('❌ [Settings] 分数の変更：pre を取り消せませんでした ($date): $e');
        cancelFailed = true;
      }
    }
    debugPrint('🔕 [Settings] 分数の変更（$oldMinutes→$newMinutes分）：pre を ${cancelDates.length}日分 取り消しました（失敗あり: $cancelFailed）');

    if (action == PreMinutesAction.cancelOnly) {
      return (action: action, count: 0, errorCode: null, readFailed: cancelFailed);
    }
    final result = await PreAlarmRescheduleService.reschedule();
    return (
      action: action,
      count: result.count,
      errorCode: result.errorCode,
      readFailed: result.readFailed || cancelFailed,
    );
  }
  // ============================================================================
  
  Future<void> _updateWakeUpTimeInProvider() async {
    try {
      // N118：シフトを読めなかったら「シフトが登録されていません」と誤表示しない（ログだけ）
      final List<Map<String, dynamic>> shifts;
      try {
        shifts = await _shiftRepository.getShiftsForDateRange(
          DateTime.now(),
          DateTime.now().add(const Duration(days: 1)),
        );
      } catch (e) {
        debugPrint('❌ 起床時刻の自動計算：シフトを読めませんでした: $e');
        return;
      }

      if (shifts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('シフトが登録されていません'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // ✅ H2: 出勤前アラームが「無効（0）」なら自動計算しない（前回の自動計算値も表示に残さない）
      if (_alarmTimeBeforeShift <= 0) {
        print('ℹ️ 起床時刻の自動計算をスキップ: 出勤前アラームが無効（0）');
        if (mounted) {
          context.read<SleepProvider>().clearAutoWakeUpTime();
        }
        return;
      }

      // ✅ H2: 返却順は保証されないため、shifts.first は使わず shift_date（YYYY-MM-DD）の昇順に並べる
      final sortedShifts = [...shifts]..sort((a, b) =>
          (a['shift_date'] as String? ?? '').compareTo(b['shift_date'] as String? ?? ''));

      // ✅ H2: 起床時刻（シフト日＋開始時刻 − 設定分数）が「今より後」になる最初の出勤シフトを採用する
      //    開始時刻は shifts ではなく pattern_id → getPatternById → startTime から取得（表示用のみ）
      final now = DateTime.now();
      DateTime? wakeUpDateTime;
      for (final shift in sortedShifts) {
        final shiftDate = DateTime.tryParse(shift['shift_date'] as String? ?? '');
        final patternId = shift['pattern_id'] as String?;
        if (shiftDate == null || patternId == null) continue;
        final pattern = await _shiftRepository.getPatternById(patternId);
        final startTime = pattern?.startTime;
        if (startTime == null) continue;  // 休日・有休・削除済みパターン等はスキップ
        final candidate = DateTime(
          shiftDate.year,
          shiftDate.month,
          shiftDate.day,
          startTime.hour,
          startTime.minute,
        ).subtract(Duration(minutes: _alarmTimeBeforeShift));
        if (candidate.isAfter(now)) {
          wakeUpDateTime = candidate;  // 実際のシフト日で計算（明日固定にしない）
          break;
        }
      }

      // ✅ H2: 対象の出勤シフトが見つからなければ、前回の自動計算値を残さずに終了
      if (wakeUpDateTime == null) {
        print('ℹ️ 起床時刻の自動計算をスキップ: 今日〜明日に対象の出勤シフトがありません');
        if (mounted) {
          context.read<SleepProvider>().clearAutoWakeUpTime();
        }
        return;
      }
      
      if (mounted) {
        final sleepProvider = context.read<SleepProvider>();
        sleepProvider.setAutoWakeUpTime(wakeUpDateTime);
      }
    } catch (e) {
      debugPrint('❌ 起床時刻更新エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ 起床時刻を計算できませんでした'),
            backgroundColor: AppColors.warningRed,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}