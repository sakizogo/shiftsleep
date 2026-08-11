import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class AlarmService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz_data.initializeTimeZones();

    // Android設定
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS設定
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

    // Android 12以上の通知チャネル作成
    await _createNotificationChannel();
  }

  /// 通知チャネルの作成（音声を含む）
  static Future<void> _createNotificationChannel() async {
    const androidChannel = AndroidNotificationChannel(
      'alarm_channel_id',
      'アラーム通知',
      description: 'シフト出勤時間のアラーム通知',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
      // 1. デフォルト（推奨）
      sound: const RawResourceAndroidNotificationSound('alarm_default'),

      // 2. 優しい音
      // sound: const RawResourceAndroidNotificationSound('alarm_gentle'),

      // 3. 大きい音
      // sound: const RawResourceAndroidNotificationSound('alarm_harsh'),
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// アラームのスケジュール設定
  static Future<void> scheduleAlarmForShift({
    required DateTime shiftDate,
    required TimeOfDay alarmTime,
    bool preAlarmEnabled = true,
    int preAlarmMinutes = 5,
  }) async {
    // メインアラーム
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
      isAlarm: true,
    );

    // 前アラーム
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
        isAlarm: true,
      );
    }
  }

  /// 通知のスケジュール
  static Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    bool isAlarm = false,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'alarm_channel_id',
        'アラーム通知',
        channelDescription: 'シフト出勤時間のアラーム通知',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('alarm_default'),
        enableLights: true,
        showWhen: true,
      );

      const iosDetails = DarwinNotificationDetails(
        sound: 'alarm_default.aiff',
        presentSound: true,
        presentAlert: true,
        presentBadge: true,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // スケジュール通知
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAndAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      print('✓ アラーム設定完了: $title (ID: $id)');
    } catch (e) {
      print('✗ アラーム設定エラー: $e');
    }
  }

  /// 通知IDの生成（日付 + タイプから一意なIDを生成）
  static int _generateNotificationId(DateTime date, String type) {
    final dateStr =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final typeNum = type == 'main' ? 0 : 1;
    return int.parse('$dateStr$typeNum');
  }

  /// アラームをキャンセル
  static Future<void> cancelAlarm(DateTime date) async {
    await _notificationsPlugin.cancel(_generateNotificationId(date, 'main'));
    await _notificationsPlugin.cancel(_generateNotificationId(date, 'pre'));
    print('✓ アラームをキャンセルしました: $date');
  }

  /// すべてのアラームをクリア
  static Future<void> cancelAllAlarms() async {
    await _notificationsPlugin.cancelAll();
    print('✓ すべてのアラームをクリアしました');
  }

  /// 通知タップ時のコールバック
  static void _onNotificationTapped(
      NotificationResponse notificationResponse) {
    print('通知がタップされました: ${notificationResponse.payload}');
    // ここで画面遷移などの処理を追加
  }
}