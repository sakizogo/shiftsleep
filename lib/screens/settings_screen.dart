// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/models/alarm_config.dart';
import 'package:shiftsleep/repositories/alarm_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:uuid/uuid.dart';

class SettingsScreen extends StatefulWidget {
  final String userId;

  const SettingsScreen({
    Key? key,
    this.userId = 'test_user', // デフォルト値
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AlarmRepository _alarmRepository;
  late AlarmService _alarmService;

  // UI 状態
  late AlarmMode _selectedMode;
  late AlarmSound _selectedSound;
  late int _volume;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _alarmRepository = AlarmRepository();
    _alarmService = AlarmService();
    _loadAlarmConfig();
  }

  /// DB からアラーム設定を読み込む
  Future<void> _loadAlarmConfig() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final config = await _alarmRepository.getAlarmConfigByUserId(widget.userId);

      if (config != null) {
        setState(() {
          _selectedMode = config.alarmMode;
          _selectedSound = config.alarmSound;
          _volume = config.volume;
          _isLoading = false;
        });
      } else {
        // デフォルト設定を使用
        setState(() {
          _selectedMode = AlarmMode.oneTime;
          _selectedSound = AlarmSound.defaultSound;
          _volume = 70;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'アラーム設定の読み込みに失敗しました: $e';
        _isLoading = false;
      });
      print('[SettingsScreen] ❌ Error loading config: $e');
    }
  }

  /// アラーム設定を保存
  Future<void> _saveAlarmConfig() async {
    try {
      final existingConfig = await _alarmRepository.getAlarmConfigByUserId(widget.userId);

      final newConfig = AlarmConfig(
        id: existingConfig?.id ?? const Uuid().v4(),
        userId: widget.userId,
        alarmMode: _selectedMode,
        alarmSound: _selectedSound,
        volume: _volume,
        createdAt: existingConfig?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (existingConfig != null) {
        // 更新
        await _alarmRepository.updateAlarmConfig(newConfig);
      } else {
        // 新規作成
        await _alarmRepository.insertAlarmConfig(newConfig);
      }

      // ✅ 重要！ここにアラームのスケジュール処理を追加
      // DB に保存した設定で実際のアラームを再スケジュール
      try {
        await _alarmService.scheduleAlarm(
          sleepTime: DateTime.now().toIso8601String(),
          wakeupTime: '07:00',
          config: newConfig,
        );
        print('[SettingsScreen] ✅ Alarm re-scheduled with new config');
      } catch (e) {
        print('[SettingsScreen] ⚠️ Failed to re-schedule alarm: $e');
        // アラームスケジュール失敗しても DB 保存は成功しているので、続行
      }

      print('[SettingsScreen] ✅ Alarm config saved');

      // スナックバー表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ アラーム設定を保存しました')),
        );
      }

      // ホーム画面に戻る
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('[SettingsScreen] ❌ Error saving config: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 保存に失敗しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: AppColors.backgroundLight,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadAlarmConfig,
                        child: const Text('再度読み込む'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // === アラーム設定セクション ===
                        Text(
                          '⚙️ アラーム設定',
                          style: AppTextStyles.sectionTitleStyle,
                        ),
                        const SizedBox(height: 16),

                        // --- 事前アラーム選択 ---
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.borderDefault),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '事前アラーム',
                                style: AppTextStyles.bodyTextStyle,
                              ),
                              const SizedBox(height: 12),
                              RadioListTile<AlarmMode>(
                                title: const Text('なし'),
                                subtitle: const Text('アラーム通知を使用しない'),
                                value: AlarmMode.none,
                                groupValue: _selectedMode,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedMode = value!;
                                  });
                                },
                              ),
                              RadioListTile<AlarmMode>(
                                title: const Text('1 回（メインのみ）'),
                                subtitle: const Text('起床予定時刻（07:00）に1回通知'),
                                value: AlarmMode.oneTime,
                                groupValue: _selectedMode,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedMode = value!;
                                  });
                                },
                              ),
                              RadioListTile<AlarmMode>(
                                title: const Text('2 回（事前+メイン）'),
                                subtitle: const Text('5分前と起床時刻に2回通知'),
                                value: AlarmMode.twoTimes,
                                groupValue: _selectedMode,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedMode = value!;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // --- アラーム音選択 ---
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.borderDefault),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'アラーム音',
                                style: AppTextStyles.bodyTextStyle,
                              ),
                              const SizedBox(height: 12),
                              DropdownButton<AlarmSound>(
                                value: _selectedSound,
                                isExpanded: true,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedSound = value!;
                                 });
                                },
                                items: AlarmSound.values.map((sound) {
                                  return DropdownMenuItem(
                                  value: sound,
                                  child: Row(
                                    children: [
                                      Text(_getAlarmSoundLabel(sound)),
                                      const SizedBox(width: 12),
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.play_arrow, size: 16),
                                        label: const Text('試聴'),
                                        onPressed: () {
                                          // ✅ 音量パラメータなし
                                          _alarmService.playAlarmSoundPreview(sound);
                                        },
                                       ),
                                     ],
                                    ),
                                   );
                                 }).toList(),
                               ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // --- 音量調整 ---
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.borderDefault),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '音量',
                                style: AppTextStyles.bodyTextStyle,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Slider(
                                      value: _volume.toDouble(),
                                      min: 0,
                                      max: 100,
                                      divisions: 10,
                                      onChanged: (value) {
                                        setState(() {
                                          _volume = value.toInt();
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    '$_volume%',
                                    style: AppTextStyles.sectionTitleStyle,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // --- ボタン ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.borderDefault,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 12,
                                ),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text(
                                'キャンセル',
                                style: TextStyle(color: AppColors.textPrimary),
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGradientStart,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 48,
                                  vertical: 12,
                                ),
                              ),
                              onPressed: _saveAlarmConfig,
                              child: const Text(
                                '保存',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  /// AlarmSound を表示用ラベルに変換
  String _getAlarmSoundLabel(AlarmSound sound) {
    switch (sound) {
      case AlarmSound.harsh:
        return '🔊 キツイ音';
      case AlarmSound.gentle:
        return '🎵 緩やかな音';
      case AlarmSound.defaultSound:
        return '📢 デフォルト音';
    }
  }
}