// lib/services/alarm_service.dart

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:shiftsleep/models/alarm_config.dart';

/// アラーム通知を管理する Service クラス
/// flutter_local_notifications を使用して、指定時刻にアラーム通知を送信
class AlarmService {
  static final AlarmService _instance = AlarmService._internal();
  
  factory AlarmService() {
    return _instance;
  }
  
  AlarmService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// 初期化（アプリ起動時に呼び出す）
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // タイムゾーンデータを初期化
      tz_data.initializeTimeZones();

      // Android 設定
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS 設定（オプション）
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      // 全体設定を統合
      final InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(initSettings);
      _isInitialized = true;

      print('[AlarmService] ✅ Initialized successfully');
    } catch (e) {
      print('[AlarmService] ❌ Initialization error: $e');
      rethrow;
    }
  }

  /// アラームをスケジュール
  /// 
  /// [sleepTime] - 眠った時刻（ISO8601 形式）
  /// [wakeupTime] - 起床予定時刻（毎日 07:00）
  /// [config] - アラーム設定（モード・音・音量）
  /// 
  /// 処理：
  /// 1. AlarmMode に応じて通知をスケジュール
  ///    - None: 何もしない
  ///    - OneTime: 起床予定時刻（07:00）のみ
  ///    - TwoTimes: 05分前（06:55）+ 07:00
  /// 2. 日本時刻（JST）で動作
  Future<void> scheduleAlarm({
    required String sleepTime,
    required String wakeupTime,
    required AlarmConfig config,
  }) async {
    try {
      if (!_isInitialized) {
        print('[AlarmService] ⚠️ Not initialized. Call initialize() first.');
        return;
      }

      // 既存のアラームをキャンセル（重複防止）
      await cancelAllAlarms();

      // AlarmMode が「なし」の場合は何もしない
      if (config.alarmMode == AlarmMode.none) {
        print('[AlarmService] ℹ️ AlarmMode is None. No alarm scheduled.');
        return;
      }

      // 日本のタイムゾーン
      final jst = tz.getLocation('Asia/Tokyo');
      final now = tz.TZDateTime.now(jst);

      // 毎日 07:00 に起床予定
      var mainAlarmTime = tz.TZDateTime(
        jst,
        now.year,
        now.month,
        now.day,
        7,  // 07:00
        0,
      );

      // もし既に 07:00 を過ぎていたら、明日の 07:00 にスケジュール
      if (mainAlarmTime.isBefore(now)) {
        mainAlarmTime = mainAlarmTime.add(const Duration(days: 1));
      }

      // パターン A: 2 回（事前 + メイン）
      if (config.alarmMode == AlarmMode.twoTimes) {
        // 事前アラーム：05分前（06:55）
        final preAlarmTime = mainAlarmTime.subtract(const Duration(minutes: 5));
        await _scheduleNotification(
          id: 1,
          title: '🌙 もうすぐ起床時刻です',
          body: '05分後に起床アラームが鳴ります',
          scheduledTime: preAlarmTime,
          config: config,
        );
        print('[AlarmService] ✅ Pre-alarm scheduled at ${preAlarmTime.hour}:${preAlarmTime.minute.toString().padLeft(2, '0')}');
      }

      // メインアラーム：07:00
      await _scheduleNotification(
        id: 2,
        title: '☀️ 起床時刻です',
        body: '今日も頑張ってください！',
        scheduledTime: mainAlarmTime,
        config: config,
      );
      print('[AlarmService] ✅ Main alarm scheduled at ${mainAlarmTime.hour}:${mainAlarmTime.minute.toString().padLeft(2, '0')}');

    } catch (e) {
      print('[AlarmService] ❌ scheduleAlarm error: $e');
      rethrow;
    }
  }

  /// 通知をスケジュール（内部ヘルパーメソッド）
  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledTime,
    required AlarmConfig config,
  }) async {
    try {
      final soundFileName = _getSoundFileName(config.alarmSound);
      
      // ✅ デバッグログ
      print('[AlarmService] 🔧 DEBUG: Scheduling alarm...');
      print('[AlarmService] 🔧 DEBUG: id=$id, sound=$soundFileName, time=${scheduledTime.toString()}');
      print('[AlarmService] 🔧 DEBUG: AlarmSound=${config.alarmSound}');
      
      // ✅ 音ごとに異なるチャネル ID を使用（キャッシング対策）
      final channelId = 'shiftsleep_alarm_${soundFileName}';
      final channelName = 'ShiftSleep Alarm ($soundFileName)';
      
      // 通知チャネルの設定
      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Notifications for ShiftSleep alarms',
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound(soundFileName),
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
      );

      // ✅ zonedSchedule を試みる（exact alarmが必要）
      try {
        await _notificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          scheduledTime,
          notificationDetails,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time, // 毎日この時刻に繰り返す
        );
        print('[AlarmService] ✅ zonedSchedule succeeded');
      } catch (zoneError) {
        print('[AlarmService] ⚠️ zonedSchedule failed: $zoneError');
        print('[AlarmService] ℹ️ Fallback: Using periodicallyShow instead...');
        
        // ✅ フォールバック: periodicallyShow を使用（exact alarm不要）
        await _notificationsPlugin.periodicallyShow(
          id,
          title,
          body,
          RepeatInterval.daily,
          notificationDetails,
        );
        print('[AlarmService] ✅ periodicallyShow succeeded (fallback)');
      }
    } catch (e) {
      print('[AlarmService] ❌ _scheduleNotification error: $e');
      rethrow;
    }
  }

  /// 全てのアラームをキャンセル
  Future<void> cancelAllAlarms() async {
    try {
      await _notificationsPlugin.cancelAll();
      print('[AlarmService] ✅ All alarms canceled');
    } catch (e) {
      print('[AlarmService] ❌ cancelAllAlarms error: $e');
    }
  }

  /// 特定の ID のアラームをキャンセル
  Future<void> cancelAlarmById(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
      print('[AlarmService] ✅ Alarm $id canceled');
    } catch (e) {
      print('[AlarmService] ❌ cancelAlarmById error: $e');
    }
  }

  /// アラーム音のプレビュー再生（設定画面用）
  /// 
  /// ユーザーが設定画面で音を選択した際に、プレビュー音を再生
  Future<void> playAlarmSoundPreview(AlarmSound sound) async {
    try {
      final soundFileName = _getSoundFileName(sound);
      
      print('[AlarmService] 🔊 DEBUG: playAlarmSoundPreview called');
      print('[AlarmService] 🔊 DEBUG: soundFileName = $soundFileName');
      
      // ✅ 音ごとに異なるチャネル ID を使用（キャッシング対策）
      final channelId = 'shiftsleep_preview_${soundFileName}';
      final channelName = 'ShiftSleep Preview ($soundFileName)';
      
      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          sound: RawResourceAndroidNotificationSound(soundFileName),
        ),
      );

      await _notificationsPlugin.show(
        999, // プレビュー用の ID
        '🔊 アラーム音プレビュー',
        _getSoundDescription(sound),
        notificationDetails,
      );
      print('[AlarmService] ✅ Playing preview for: $sound');
    } catch (e) {
      print('[AlarmService] ❌ playAlarmSoundPreview error: $e');
    }
  }

  /// AlarmSound の説明文を取得
  String _getSoundDescription(AlarmSound sound) {
    switch (sound) {
      case AlarmSound.harsh:
        return 'キツイ音のプレビューです';
      case AlarmSound.gentle:
        return '緩やかな音のプレビューです';
      case AlarmSound.defaultSound:
        return 'デフォルト音のプレビューです';
    }
  }
  
  /// AlarmSound に対応する音ファイル名を取得
  String _getSoundFileName(AlarmSound sound) {
    switch (sound) {
      case AlarmSound.harsh:
        return 'alarm_harsh';
      case AlarmSound.gentle:
        return 'alarm_gentle';
      case AlarmSound.defaultSound:
        return 'alarm_default';
    }
  }

  /// 初期化済みかどうかを確認
  bool get isInitialized => _isInitialized;
}