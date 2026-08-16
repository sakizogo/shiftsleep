import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/app_settings.dart';  // ← 小文字
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';  // ← 小文字
// ========== Week 6 Fix E: 設定画面のシフト体系登録削除 ==========
// 削除済み: import 'shift_pattern_screen.dart';
// 理由: ホーム → シフト詳細確認 → シフト体系登録 に統一（重複排除）
// ================================================================

class SettingsScreen extends StatefulWidget {
  final String userId;

  const SettingsScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TimeOfDay _wakeUpTime = const TimeOfDay(hour: 7, minute: 0);
  AlarmMode _alarmMode = AlarmMode.once;
  String _selectedAlarmSound = 'default';
  double _soundVolume = 1.0;
  int _alarmTimeBeforeShift = 30;  // デフォルト：出勤30分前
  bool _advicePromoVisible = true;  // ← 新規追加：改善アドバイスの有料版表示フラグ
  final ShiftRepository _shiftRepository = ShiftRepository();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// DB から設定を読み込む
 Future<void> _loadSettings() async {
   try {
     final settings = await _shiftRepository.getAppSettings('test_user');
    
     if (settings != null && mounted) {
       print('✅ 設定を読み込み: 起床時刻=${settings.wakeUpTime}, アラーム時間=${settings.alarmTimeBeforeShift}分前, 音=${settings.selectedAlarmSound}, promoVisible=${settings.advicePromoVisible}');
      
       // wakeUpTime を "07:00" 形式から TimeOfDay に変換
       final timeParts = settings.wakeUpTime.split(':');
       final hour = int.parse(timeParts[0]);
       final minute = int.parse(timeParts[1]);
      
       setState(() {
         _wakeUpTime = TimeOfDay(hour: hour, minute: minute);
         _alarmTimeBeforeShift = settings.alarmTimeBeforeShift;
         _selectedAlarmSound = settings.selectedAlarmSound;
         _advicePromoVisible = settings.advicePromoVisible;  // ← 新規追加
       });
     }
   } catch (e) {
     print('⚠️ 設定読み込みエラー: $e');
   }
 }
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          backgroundColor: AppColors.backgroundLight,
          elevation: 0,
          centerTitle: true,
          // leading: IconButton(...) ← この部分を削除
          title: Text(
            '設定',
            style: AppTextStyles.headerStyle,
          ),
          foregroundColor: AppColors.textPrimary,
          bottom: PreferredSize(
          // ... 以下はそのまま
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
                    // 起床時刻設定
                    Text(
                      '起床時刻',
                      style: AppTextStyles.bodyTextStyle.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    Row(
                      children: [
                        Text(
                          '${_wakeUpTime.hour.toString().padLeft(2, '0')}:${_wakeUpTime.minute.toString().padLeft(2, '0')}',
                          style: AppTextStyles.largeNumberStyle.copyWith(
                            fontSize: 32,
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () => _selectWakeUpTime(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                AppColors.primaryGradientStart,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDimensions.borderRadiusSmall,
                              ),
                            ),
                          ),
                          child: Text(
                            '変更',
                            style: AppTextStyles.bodyTextStyle.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                        }
                      },
                    ),
                    const SizedBox(height: AppDimensions.paddingLarge),
                    const SizedBox(height: AppDimensions.paddingLarge),

                    // ========================
                    // 改善アドバイス表示設定セクション
                    // ========================
                    Text(
                      '💡 改善アドバイス表示設定',
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
                      child: Row(
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
                            activeColor: AppColors.primaryGradientStart,
                          ),
                        ],
                      ),
                    ),
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
                        print('🔊 ドロップダウン選択: $value');  // ← デバッグ追加
                        setState(() {
                          _selectedAlarmSound = value!;
                          print('🔊 _selectedAlarmSound 更新: $_selectedAlarmSound');  // ← デバッグ追加
                        });
                      },
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
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.paddingLarge),

              // ========================
              // テストセクション
              // ========================
              Text(
                'テスト',
                style: AppTextStyles.bodyTextStyle.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8.0),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _testAlarmSound,  // ← これが必須！
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warningRed,
                  ),
                  child: Text(
                    '🔊 3分後にテストアラーム',
                    style: AppTextStyles.bodyTextStyle.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              // ========== Week 6 Fix E: 設定画面のシフト体系設定セクション削除 ==========
              // 削除済み：シフト体系設定セクション全体（登録、編集、削除機能）
              // 理由：ホーム → シフト詳細確認 → シフト体系登録 に統一（重複排除）
              // =========================================================================

              // ========================
              // 保存ボタン
              // ========================
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveSettings,
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
      ),    // ← Scaffold を閉じる括弧を追加
    );
  }

  /// アラームモード選択ボタン
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
                ? AppColors.primaryGradientStart.withOpacity(0.1)
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

  // ========== Week 6 Fix E: 削除済みメソッド ==========
  // _buildPatternItem, _registerNewPattern, _editPattern, _deletePattern
  // 理由：ホーム → シフト詳細確認 → シフト体系登録 に統一（重複排除）
  // ================================================

  /// 起床時刻選択
  Future<void> _selectWakeUpTime(BuildContext context) async {
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
    }
  }

  // ========== Week 6 Fix E: 削除済みメソッド ==========
  // _registerNewPattern, _editPattern, _deletePattern
  // 理由：ホーム → シフト詳細確認 → シフト体系登録 に統一（重複排除）
  // ================================================

  /// テストアラーム（即座通知）
  Future<void> _testAlarmSound() async {
    print('🔊 テストアラーム開始...');
    print('🔊 テスト時点の _selectedAlarmSound: $_selectedAlarmSound');  // ← デバッグ追加
    // 即座に通知を表示（音が選択値で鳴る）
    await AlarmService.showTestNotification(
      selectedAlarmSound: _selectedAlarmSound,  // ← 音を渡す
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('今すぐテスト通知が鳴ります！'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
  /// 設定を保存
  Future<void> _saveSettings() async {
    try {
      final shiftRepository = ShiftRepository();
    
      // TimeOfDay を "HH:mm" 形式の文字列に変換
      final wakeUpTimeStr = '${_wakeUpTime.hour.toString().padLeft(2, '0')}:${_wakeUpTime.minute.toString().padLeft(2, '0')}';
    
      // AppSettings オブジェクトを作成して保存
      final app_settings = AppSettings(
        id: 1,
        userId: 'test_user',
        alarmTimeBeforeShift: _alarmTimeBeforeShift,
        wakeUpTime: wakeUpTimeStr,
        selectedAlarmSound: _selectedAlarmSound,  // ← この1行を追加
        advicePromoVisible: _advicePromoVisible,  // ← 新規追加
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    
      await shiftRepository.createOrUpdateAppSettings(app_settings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('設定を保存しました'),
            backgroundColor: AppColors.primaryGradientStart,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      print('✅ 設定を保存: 起床時刻=$wakeUpTimeStr, アラーム時間=$_alarmTimeBeforeShift分前, promoVisible=$_advicePromoVisible');
    } catch (e) {
      print('❌ 設定保存エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラー: $e'),
            backgroundColor: AppColors.warningRed,
          ),
        );
      }
    }
  }
}