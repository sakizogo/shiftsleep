import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:permission_handler/permission_handler.dart';

class AlarmService {
  // ===== MethodChannel 定義 =====
  static const String _methodChannelName = 'com.sakizoapps.shiftsleep/alarm';
  static final MethodChannel _methodChannel = MethodChannel(_methodChannelName);

  // ===== Notification Plugin =====
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // ===== テスト音声再生用 =====
  static final AudioPlayer _testAudioPlayer = AudioPlayer();
  static Timer? _testAudioTimer;

  // ===== 初期化フラグ =====
  static bool _isInitialized = false;

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

      // ※ WAKE_LOCK は AndroidManifest.xml に宣言済みなので、リクエスト不要
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

    // ★ 追加：初期化完了フラグをセット ★
    _isInitialized = true;
    print('✅ AlarmService initialized successfully');
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
    String selectedAlarmSound = 'default',
  }) async {
    print('🔴 [DEBUG] scheduleAlarmForShift が呼び出されました！');
    print('🔴 [DEBUG] シフト日: $shiftDate, 出勤時刻: ${alarmTime.hour}:${alarmTime.minute}');

    // メインアラーム
    final mainAlarmDateTime = DateTime(
      shiftDate.year,
      shiftDate.month,
      shiftDate.day,
      alarmTime.hour,
      alarmTime.minute,
    );

    await _scheduleNotification(
      id: _generateNotificationId(shiftDate, 'main'),
      title: '出勤時間です',
      body: '${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')} に出勤します',
      scheduledDate: mainAlarmDateTime,
      selectedAlarmSound: selectedAlarmSound,
    );

    // ✅ AlarmManager でもスケジュール（デバイススリープ中対応）
    await _scheduleWithAlarmManager(
      alarmId: _generateNotificationId(shiftDate, 'main'),
      scheduledDate: mainAlarmDateTime,
      title: '出勤時間です',
      body: '${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')} に出勤します',
    );

    // 事前アラーム
    if (preAlarmEnabled) {
      final preAlarmDateTime = mainAlarmDateTime.subtract(Duration(minutes: preAlarmMinutes));

      await _scheduleNotification(
        id: _generateNotificationId(shiftDate, 'pre'),
        title: '出勤${preAlarmMinutes}分前です',
        body: '準備をお始めください',
        scheduledDate: preAlarmDateTime,
        selectedAlarmSound: selectedAlarmSound,
      );

      // ✅ AlarmManager でもスケジュール（デバイススリープ中対応）
      await _scheduleWithAlarmManager(
        alarmId: _generateNotificationId(shiftDate, 'pre'),
        scheduledDate: preAlarmDateTime,
        title: '出勤${preAlarmMinutes}分前です',
        body: '準備をお始めください',
      );
    }
  }

  static Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String selectedAlarmSound = 'default',
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
        sound: RawResourceAndroidNotificationSound(soundFileName),
        enableLights: true,
        showWhen: true,
      );

      final iosDetails = DarwinNotificationDetails(
        sound: soundFileName,
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
        androidScheduleMode: AndroidScheduleMode.exact,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      print('✓ アラーム設定完了: $title (ID: $id)');
    } catch (e) {
      print('✗ アラーム設定エラー: $e');
      print('✗ エラースタックトレース: ${e.toString()}');
    }
  }

  /// AlarmManager でアラームをスケジュール（デバイススリープ中対応）
  static Future<void> _scheduleWithAlarmManager({
    required int alarmId,
    required DateTime scheduledDate,
    required String title,
    required String body,
  }) async {
    try {
      print('⏰ AlarmManager スケジュール開始');
      print('⏰ アラーム ID: $alarmId');
      print('⏰ スケジュール時刻: $scheduledDate');

      // MillisecondsSinceEpoch でタイムスタンプを取得
      final timestampMs = scheduledDate.millisecondsSinceEpoch;

      // Kotlin の scheduleAlarmWithAlarmManager メソッドを呼び出し
      final result = await _methodChannel.invokeMethod<String>(
        'scheduleAlarmWithAlarmManager',
        {
          'timestampMs': timestampMs,
          'alarmId': alarmId,
          'title': title,
          'body': body,
        },
      );

      print('✅ AlarmManager スケジュール成功: $result');
    } catch (e) {
      print('❌ AlarmManager スケジュール エラー: $e');
    }
  }

  /// AlarmManager のアラームをキャンセル
  static Future<void> _cancelWithAlarmManager(int alarmId) async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        'cancelAlarmWithAlarmManager',
        {'alarmId': alarmId},
      );
      print('✅ AlarmManager キャンセル成功: $result');
    } catch (e) {
      print('❌ AlarmManager キャンセル エラー: $e');
    }
  }

  static int _generateNotificationId(DateTime date, String type) {
    final dateStr =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final typeNum = type == 'main' ? 0 : 1;
    return int.parse('$dateStr$typeNum');
  }

  static Future<void> cancelAlarm(DateTime date) async {
    final mainAlarmId = _generateNotificationId(date, 'main');
    final preAlarmId = _generateNotificationId(date, 'pre');

    // flutter_local_notifications をキャンセル
    await _notificationsPlugin.cancel(mainAlarmId);
    await _notificationsPlugin.cancel(preAlarmId);

    // ✅ AlarmManager もキャンセル
    await _cancelWithAlarmManager(mainAlarmId);
    await _cancelWithAlarmManager(preAlarmId);

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

  /// テスト通知を即座に再生（設定画面用）
  ///
  /// [selectedAlarmSound] - アラーム音の種類（'default', 'gentle', 'harsh'）
  /// [volume] - 音量（0.0〜1.0）
  ///
  /// 動作：
  /// 1. 即座にアラーム音を再生（audioplayers 使用）
  /// 2. ユーザー指定の音量で再生
  /// 3. 2秒後に自動停止（長い音源の途中停止対応）
  static Future<void> showTestNotification({
    required String selectedAlarmSound,
    double volume = 1.0,
  }) async {
    try {
      // 既に再生中なら停止
      if (_testAudioPlayer.state == PlayerState.playing) {
        await _testAudioPlayer.stop();
        _testAudioTimer?.cancel();
        print('[AlarmService] ℹ️ 前の再生を停止しました');
      }

      // 音声ファイルのマッピング（assets/raw/ 配下のファイル）
      final soundMap = {
        'default': 'alarm_default.mp3',
        'gentle': 'alarm_gentle.mp3',
        'harsh': 'alarm_harsh.mp3',
      };

      final soundFileName = soundMap[selectedAlarmSound] ?? soundMap['default']!;

      // 音量設定（0.0〜1.0）
      await _testAudioPlayer.setVolume(volume);

      print('[AlarmService] 🔊 テスト音再生開始: $selectedAlarmSound (音量: ${(volume * 100).toStringAsFixed(0)}%)');

      // AssetSource を使用してアセットから再生
      await _testAudioPlayer.play(AssetSource('raw/$soundFileName'));

      // 2秒後に停止（タイマー設定）
      _testAudioTimer = Timer(const Duration(seconds: 2), () async {
        await _testAudioPlayer.stop();
        print('[AlarmService] ⏱️ テスト音停止（2秒経過）');
      });

    } catch (e) {
      print('[AlarmService] ❌ テスト音再生エラー: $e');
    }
  }
}