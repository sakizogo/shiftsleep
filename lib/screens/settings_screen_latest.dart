import 'package:flutter/cupertino.dart';  // ← CupertinoSwitch 用
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
import 'package:shiftsleep/services/pre_alarm_reschedule_service.dart';
import 'package:shiftsleep/services/premium_service.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
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
    _loadDailyWakeUpSetting();  // ✅ N11: 毎日使用フラグと今夜の手動起床の有無を反映
    _loadAlarmEnabledSetting();  // ✅ H4: 保存済みの ON/OFF をスイッチに反映
    // ============================================================
  }

  /// DB から設定を読み込む
  Future<void> _loadSettings() async {
    try {
      final settings = await _shiftRepository.getAppSettings('test_user');

      if (settings != null && mounted) {
        print('✅ 設定を読み込み: 起床時刻=${settings.wakeUpTime}, アラーム時間=${settings.alarmTimeBeforeShift}分前, 音=${settings.selectedAlarmSound}, promoVisible=${settings.advicePromoVisible}, isPremium=${settings.isPremiumUser}');

        // ✨ ここを追加：wakeUpTime を "07:00" 形式から TimeOfDay に変換
        final timeParts = settings.wakeUpTime.split(':');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);

        setState(() {
          _currentSettings = settings;  // ← 追加：現在の設定を保存
          _wakeUpTime = TimeOfDay(hour: hour, minute: minute);
          _alarmTimeBeforeShift = settings.alarmTimeBeforeShift;
          _selectedAlarmSound = settings.selectedAlarmSound;
          _advicePromoVisible = settings.advicePromoVisible;
          _isPremiumUser = settings.isPremiumUser;
          // isAlarmEnabled は削除
        });
      }
    } catch (e) {
      print('⚠️ 設定読み込みエラー: $e');
    }
  }

  /// ✅ N10/N11: 毎日使用フラグと、今夜の手動起床が有効かを読み込む
  Future<void> _loadDailyWakeUpSetting() async {
    final isDaily = await ManualWakeService.isDaily();
    final hasTonight = (await ManualWakeService.getActive()) != null;
    if (!mounted) return;
    setState(() {
      _useDailyWakeUpSetting = isDaily;
      _hasManualWakeTonight = hasTonight;
    });
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
          await _cancelAllAlarmsForOff();
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
    Future<void> _cancelAllAlarmsForOff() async {
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
        if (shiftsReadFailed && mounted) {
          final messenger = ScaffoldMessenger.of(context);
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
      if (_isAlarmBusy) return;
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
            SnackBar(
              content: Text('❌ 保存に失敗しました: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
          print('❌ [Error] 保存エラー: $e');
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
        body: SingleChildScrollView(
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
                          Switch(
                            value: _advicePromoVisible,
                            onChanged: (value) {
                              setState(() {
                                _advicePromoVisible = value;
                              });
                            },
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
                              ElevatedButton(
                                onPressed: _isAlarmBusy ? null : () => _selectWakeUpTime(context),
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
                          onChanged: (bool? value) async {
                            if (value != null) {
                              setState(() {
                                _useDailyWakeUpSetting = value;
                              });
                              // ✅ N11: SharedPreferences に保存（ON は画面に表示中の時刻を毎日使う時刻にする）
                              final displayTime = context.read<SleepProvider>().autoWakeUpTimeOfDay ?? _wakeUpTime;
                              final timeStr = '${displayTime.hour.toString().padLeft(2, '0')}:${displayTime.minute.toString().padLeft(2, '0')}';
                              final messenger = ScaffoldMessenger.of(context);  // await 前に取得
                              if (value) {
                                await ManualWakeService.setDaily(true, time: displayTime);
                              } else {
                                await ManualWakeService.setDaily(false);
                              }
                              await _loadDailyWakeUpSetting();

                              print('[SettingsScreen] 📌 毎日設定チェックボックス: ${value ? "✅ ON" : "❌ OFF"}');

                              // ユーザーに通知
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(value
                                        ? '✅ 毎晩 $timeStr に起こします（出勤前アラームの方が早い日はそちらを優先）'
                                        : '⬜ 「変更」で選んだ夜だけこの時刻を使います'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
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
                        onChanged: (value) {
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
                        onChanged: (value) {
                          setState(() {
                            _selectedAlarmSound = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // ✅ アラーム音保存ボタン（単独）
                      // N124：アラームの処理中（ON/OFF・音の保存）は押せない
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isAlarmBusy ? null : _saveAlarmSound,
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isAlarmBusy ? null : _saveSettings,
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
      print('[SettingsScreen] ❌ 有料版確認エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('確認エラー: $e'),
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
    if (_isAlarmBusy) return;
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
    if (picked != null) {
      setState(() {
        _wakeUpTime = picked;
      });
      
      // ✅ N4: 手動起床時刻を「今夜だけ有効」として保存（「今から寝る」で使う）
      await ManualWakeService.save(picked);
      // ✅ N11: 毎日 ON なら毎日使う時刻も更新
      if (_useDailyWakeUpSetting) {
        await ManualWakeService.setDaily(true, time: picked);
      }
      if (mounted) {
        setState(() {
          _hasManualWakeTonight = true;
        });
      }

      // ========== 🆕 修正：DB 保存 → プロバイダー更新 → アラーム再登録（就寝中の場合） ==========
      await _saveSettings();
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

  // ========== 🆕 Week 26+ Step 6：完全な _saveSettings() 実装 ==========
  // N125：処理中はスイッチ・音の保存・設定の保存・起床時刻の変更を押せない（_isAlarmBusy）
  Future<void> _saveSettings() async {
    if (_isAlarmBusy) return;
    if (mounted) setState(() => _isAlarmBusy = true);
    try {
      await _saveSettingsSteps();
    } finally {
      if (mounted) setState(() => _isAlarmBusy = false);
    }
  }

  // N125：保存の直前に DB を読み直し、分数・起床時刻・案内表示だけを変える（音は「アラーム音の保存」ボタンだけで保存する）
  //    分数が変わっていてアラームが ON なら、pre を取り消して新しい分数で登録し直す（0 なら取り消すだけ）
  Future<void> _saveSettingsSteps() async {
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ 設定が読み込まれていません')),
          );
        }
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
      print('❌ Step 1-3 実行エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // N125：保存できたら _currentSettings を保存した値にする（N124 にそろえる）
    if (mounted) setState(() => _currentSettings = savedSettings);

    // ========== Step 3.5：分数が変わったら pre を合わせる（画面が閉じられていても続ける） ==========
    final preResult = await _applyPreMinutesChange(oldMinutes, savedSettings.alarmTimeBeforeShift);

    if (!mounted) return;  // ✅ N12: await 後に画面が閉じられていたら Provider に触らない
    try {
      // ========== Step 4️⃣：SleepProvider に起床時刻を更新 ==========
      print('[Settings] 🔄 Step 4️⃣ プロバイダーを更新...');
      
      final sleepProvider = Provider.of<SleepProvider>(context, listen: false);
      
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
      print('❌ Step 4 実行エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ プロバイダー更新エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
    String? alarmError;  // ✅ N22: アラーム再登録の失敗文言（null=成功／起床中）
    try {
      // ========== Step 5️⃣：就寝中の場合、アラーム再登録 ==========
      print('[Settings] 🔍 Step 5️⃣ 就寝状態を確認...');
      
      final sleepProvider = Provider.of<SleepProvider>(context, listen: false);
            print('[Settings] 🔍 isSleepingNow = ${sleepProvider.isSleepingNow}');
      
      if (sleepProvider.isSleepingNow) {
        print('[Settings] 🔗 就寝中です。アラーム再登録を開始...');
        alarmError = await _rescheduleAlarmDuringSleep(sleepProvider, savedSettings);
      } else {
        print('[Settings] 🛑 起床中のため、アラーム登録をスキップします');
        
        // 🟠 起床中の警告メッセージを表示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ 起床中のため、アラームは登録されません。今から寝るボタンを押さないとアラームはなりません'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
      
    } catch (e) {
      print('❌ Step 5 実行エラー: $e');
      // ここではユーザーに通知しない（アラーム再登録は非同期タスク）
    }
    
    // ========== Step 6️⃣：ユーザーに成功を通知 ==========
    // ✅ N22: アラーム登録に失敗したときはオレンジだけを出す（緑の「更新されました」は出さない）
    // N125：pre の結果を成功の文言の括弧、または続けて出すオレンジで知らせる（前を消さない）
    if (mounted) {
      final messages = settingsSaveMessages(
        savedText: '✅ 起床時刻 ${_wakeUpTime.hour}:${_wakeUpTime.minute.toString().padLeft(2, '0')} に更新されました',
        mainAlarmError: alarmError,
        preAction: preResult.action,
        preCount: preResult.count,
        preErrorMessage: AlarmService.alarmErrorMessage(preResult.errorCode),
        preReadFailed: preResult.readFailed,
      );
      final messenger = ScaffoldMessenger.of(context);
      for (final message in messages) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(message.text),
            backgroundColor: message.color,
            duration: Duration(seconds: message.color == Colors.orange ? 6 : 2),
          ),
        );
      }
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
      print('❌ 起床時刻更新エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('起床時刻計算エラー: $e'),
            backgroundColor: AppColors.warningRed,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
    /// 就寝中のアラーム再登録（古いアラーム削除→新規登録）
  // ✅ N22: 戻り値 null=成功 / 文字列=オレンジで表示する文言（表示は _saveSettings で行う）
  // N125：音は画面の _selectedAlarmSound ではなく、保存した設定（DB）の音を使う
  Future<String?> _rescheduleAlarmDuringSleep(SleepProvider sleepProvider, AppSettings savedSettings) async {
    try {
      print('[Settings] 🔄 アラーム再登録処理を開始...');

      final now = DateTime.now();
      final alarmTime = _wakeUpTime;
      final alarmTimeBeforeShift = _currentSettings?.alarmTimeBeforeShift ?? 30;
      final selectedAlarmSound = savedSettings.selectedAlarmSound;

      final hour = alarmTime.hour;
      final minute = alarmTime.minute;

      final todayWakeUp = DateTime(now.year, now.month, now.day, hour, minute);
      final shiftDate = todayWakeUp.isAfter(now)
          ? DateTime(now.year, now.month, now.day)
          : DateTime(now.year, now.month, now.day + 1);

      print('[Settings] 🛑 古いアラームをキャンセル中...');
      // ✅ H1: 起床アラーム（main）だけをキャンセル。同じ日の出勤前アラーム（pre）は残す
      // ✅ N17: 前回が別の日付で登録されていても残らないよう、今日と明日の main をキャンセル
      await ManualWakeService.cancelTodayAndTomorrow();
      print('[Settings] ✅ 古いアラームキャンセル完了');

      print('[Settings] 📞 新しいアラーム再登録: $shiftDate ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}');
      final errorCode = await AlarmService.scheduleAlarmForShift(
        shiftDate: shiftDate,
        alarmTime: alarmTime,
        preAlarmEnabled: false,
        preAlarmMinutes: alarmTimeBeforeShift,
        selectedAlarmSound: selectedAlarmSound,
        isManualWake: true,  // ✅ N9: 通知文言を「起床時間です」にする
      );

      // ✅ Step1-B: 過去時刻はスキップされ得るため「完了」と断定しない
      print('[Settings] 📨 新しいアラーム登録処理を実行（起床時刻のみ）※登録/スキップの結果は [AlarmService] ログを参照');

      // ✅ Step2-2: 登録に失敗したときだけユーザーに知らせる（古いアラームは取り消し済みのため重要）
      return AlarmService.alarmErrorMessage(errorCode);
    } catch (e) {
      print('[Settings] ❌ アラーム再登録エラー: $e');
      return '⚠️ 起床時刻は保存しましたが、アラームを設定できませんでした';
    }
  }
}