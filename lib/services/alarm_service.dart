import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:permission_handler/permission_handler.dart';

class AlarmService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();  

    static Future<void> initialize() async {
      tz_data.initializeTimeZones();
       // ========== Channel を削除（古い設定をリセット） ==========
       if (Platform.isAndroid) {
         final plugin = _notificationsPlugin
             .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
         await plugin?.deleteNotificationChannel('alarm_channel_id');
         print('✅ 古い Notification Channel を削除');
       }
  // ==================================================
      // 実行時権限をリクエスト（Android 12+）
      if (Platform.isAndroid) {
        final statusExactAlarm = await Permission.scheduleExactAlarm.request();
                print('📋 scheduleExactAlarm permission: $statusExactAlarm');
  
        final statusNotification = await Permission.notification.request();
        print('📋 notification permission: $statusNotification');
      }

      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
            requestSoundPermission: true,
            requestBadgePermission: true,
            requestAlertPermission: true,
          );

     final InitializationSettings initSettings = InitializationSettings(
       android: androidSettings,
       iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // デバッグログを有効化
      print('🔊 Notifications plugin initialized');
      print('🔊 Platform-specific implementation: ${_notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()}');

      await _setupAndroidChannel();
    }

  static Future<void> _setupAndroidChannel() async {
    final channels = [
      AndroidNotificationChannel(
        'alarm_channel_default',
        'アラーム通知（デフォルト）',
        description: 'デフォルト音',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('alarm_default'),
      ),
      AndroidNotificationChannel(
        'alarm_channel_gentle',
        'アラーム通知（やさしい音）',
        description: 'やさしい音',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('alarm_gentle'),
      ),
      AndroidNotificationChannel(
        'alarm_channel_harsh',
        'アラーム通知（強めの音）',
        description: '強めの音',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('alarm_harsh'),
      ),
    ];

    try {
      print('🔧 通知チャネル作成開始...');
      final plugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
      for (final channel in channels) {
        await plugin?.createNotificationChannel(channel);
      }
      print('✅ 通知チャネル作成成功');
    } catch (e) {
      print('❌ チャネル作成エラー: $e');
    }
  }

  static Future<void> scheduleAlarmForShift({
    required DateTime shiftDate,
    required TimeOfDay alarmTime,
    bool preAlarmEnabled = true,
    int preAlarmMinutes = 5,
    String selectedAlarmSound = 'default',  // ← このパラメータを追加
  }) async {
    await _scheduleNotification(
      id: _generateNotificationId(shiftDate, 'main'),
      title: '出勤時間です',
      body: '${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')} に出勤します',
      scheduledDate: DateTime(
        shiftDate.year,
        shiftDate.month,
        shiftDate.day,
        alarmTime.hour,
        alarmTime.minute,
      ),
      selectedAlarmSound: selectedAlarmSound,  // ← ここに追加
    );

    if (preAlarmEnabled) {
      final preAlarmDateTime = DateTime(
        shiftDate.year,
        shiftDate.month,
        shiftDate.day,
        alarmTime.hour,
        alarmTime.minute,
      ).subtract(Duration(minutes: preAlarmMinutes));

      await _scheduleNotification(
        id: _generateNotificationId(shiftDate, 'pre'),
        title: '出勤${preAlarmMinutes}分前です',
        body: '準備をお始めください',
        scheduledDate: preAlarmDateTime,
        selectedAlarmSound: selectedAlarmSound,  // ← ここに追加
      );
    }
  }

  static Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String selectedAlarmSound = 'default',  // ← このパラメータを追加
  }) async {
    try {
      print('⏰ 現在時刻: ${DateTime.now()}');
      print('⏰ スケジュール時刻: $scheduledDate');
      print('⏰ 時差計算: ${tz.TZDateTime.from(scheduledDate, tz.local)}');
    
      if (scheduledDate.isBefore(DateTime.now())) {
        print('⚠️ Scheduled time is in the past: $scheduledDate');
        return;
      }
      // ★ ここに追加 ★
      final soundFileName = _getSoundFileName(selectedAlarmSound);
      print('🔊 使用するアラーム音: $selectedAlarmSound → $soundFileName');

      final androidDetails = AndroidNotificationDetails(
        'alarm_channel_id',
        'アラーム通知',
        channelDescription: 'シフト出勤時間のアラーム通知',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(soundFileName),  // ← 動的に変更
        enableLights: true,
        showWhen: true,
      );

      final iosDetails = DarwinNotificationDetails(
        sound: soundFileName,  // ← 動的に変更
        presentSound: true,
        presentAlert: true,
        presentBadge: true,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      print('🔔 zonedSchedule 実行中...');
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exact,  // ← alarmClock から exact に変更
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      print('✓ アラーム設定完了: $title (ID: $id)');
    } catch (e) {
      print('✗ アラーム設定エラー: $e');
      print('✗ エラースタックトレース: ${e.toString()}');
    }
  }

  static int _generateNotificationId(DateTime date, String type) {
    final dateStr =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final typeNum = type == 'main' ? 0 : 1;
    return int.parse('$dateStr$typeNum');
  }

  static Future<void> cancelAlarm(DateTime date) async {
    await _notificationsPlugin.cancel(_generateNotificationId(date, 'main'));
    await _notificationsPlugin.cancel(_generateNotificationId(date, 'pre'));
    print('✓ アラームをキャンセルしました: $date');
  }

  static Future<void> cancelAllAlarms() async {
    await _notificationsPlugin.cancelAll();
    print('✓ すべてのアラームをクリアしました');
  }
  /// selectedAlarmSound から実際のファイル名を取得
  static String _getSoundFileName(String selectedAlarmSound) {
    switch (selectedAlarmSound) {
      case 'gentle':
        return 'alarm_gentle';
      case 'harsh':
        return 'alarm_harsh';
      case 'default':
      default:
        return 'alarm_default';
    }
  }

  static String _getChannelId(String selectedAlarmSound) {
    switch (selectedAlarmSound) {
      case 'gentle':
        return 'alarm_channel_gentle';
      case 'harsh':
        return 'alarm_channel_harsh';
      case 'default':
      default:
        return 'alarm_channel_default';
    }
  }
  static void _onNotificationTapped(
      NotificationResponse notificationResponse) {
    print('通知がタップされました: ${notificationResponse.payload}');
  }
  /// テスト用：即座に通知を表示
  static Future<void> showTestNotification({
    String selectedAlarmSound = 'default',
  }) async {
    try {
      // channel ID を音に応じて変更
      final channelId = _getChannelId(selectedAlarmSound);
      final soundFileName = _getSoundFileName(selectedAlarmSound);
      print('🔊 [showTestNotification] 受け取った音: $selectedAlarmSound → $soundFileName (channelId: $channelId)');
    
      final androidDetails = AndroidNotificationDetails(
        channelId,
        'アラーム通知',
        importance: Importance.high,
        priority: Priority.high,
      );
    
      final iosDetails = DarwinNotificationDetails(
        sound: soundFileName,
      );
    
      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
    
      print('🔔 即座に通知を表示...');
      await _notificationsPlugin.show(
        999,
        '【テスト】出勤時間です',
        '今すぐ通知が来ましたか？',
        notificationDetails,
      );
      print('✓ 即座通知完了');
    } catch (e) {
      print('✗ 即座通知エラー: $e');
    }
    }
}