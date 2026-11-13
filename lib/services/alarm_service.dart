import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';  // ✅ H4

class AlarmService {
  // ===== MethodChannel 定義 =====
  static const String _methodChannelName = 'com.sakizoapps.shiftsleep/alarm';
  static final MethodChannel _methodChannel = MethodChannel(_methodChannelName);

  // N129 2/2 D2: デバッグ用アラームの ID（日付から作る ID は yyyymmdd＋1 桁なので重ならない）
  static const int _debugAlarmId = 999999990;

  // ===== Notification Plugin =====
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // ===== テスト音声再生用 =====
  static final AudioPlayer _testAudioPlayer = AudioPlayer();
  static Timer? _testAudioTimer;

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
    // N128：起動時の許可の request() はやめた（説明のダイアログ・バナーはホーム画面。alarm_permission.dart）
    // ※ WAKE_LOCK は AndroidManifest.xml に宣言済みなので、リクエスト不要

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

  /// ✅ H4: アラームON/OFF設定（SharedPreferences の is_alarm_enabled）を取得する
  ///    未保存・読み取りエラーの場合は true（ON）として扱う
  static Future<bool> isAlarmEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('is_alarm_enabled') ?? true;
    } catch (e) {
      print('⚠️ [AlarmService] アラームON/OFF設定の読み取りエラー（ONとして扱う）: $e');
      return true;
    }
  }

  /// ✅ Step2-2: 戻り値 null=成功またはスキップ / 'EXACT_ALARM_DENIED' / 'SCHEDULE_FAILED'
  static Future<String?> scheduleAlarmForShift({
    required DateTime shiftDate,
    required TimeOfDay alarmTime,
    bool mainAlarmEnabled = true,  // ✅ ShiftPre: false なら出勤時刻（main）を登録しない（既定 true＝起床時刻アラームは従来どおり）
    bool preAlarmEnabled = true,
    int preAlarmMinutes = 5,
    String selectedAlarmSound = 'default',
    bool isManualWake = false,  // ✅ N9: true なら main の文言を「起床時間です」にする（手動起床用）
  }) async {
    // ✅ H4: アラームOFFなら main / pre とも登録しない（エラーではないため null を返す）
    if (!await isAlarmEnabled()) {
      print('🔕 [AlarmService] アラームOFFのため登録しません: $shiftDate');
      return null;
    }

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

    // ✅ ShiftPre: mainAlarmEnabled が false のときは出勤時刻（main）を登録しない（mainError は null のまま）
    String? mainError;
    if (mainAlarmEnabled) {
      // ✅ N9: 手動起床のときだけ「起床時間です」に切り替える
      final mainTimeStr = '${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}';
      final mainTitle = isManualWake ? '起床時間です' : '出勤時間です';
      final mainBody = isManualWake ? '$mainTimeStr に起床予定です' : '$mainTimeStr に出勤します';

      await _scheduleNotification(
        id: _generateNotificationId(shiftDate, 'main'),
        title: mainTitle,
        body: mainBody,
        scheduledDate: mainAlarmDateTime,
        selectedAlarmSound: selectedAlarmSound,
      );

      // ✅ AlarmManager でもスケジュール（デバイススリープ中対応）
      mainError = await _scheduleWithAlarmManager(
        alarmId: _generateNotificationId(shiftDate, 'main'),
        scheduledDate: mainAlarmDateTime,
        title: mainTitle,
        body: mainBody,
        selectedAlarmSound: selectedAlarmSound,
      );
    }

    // 事前アラーム
    String? preError;  // ✅ Step2-2: 事前アラームの登録結果
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
      preError = await _scheduleWithAlarmManager(
        alarmId: _generateNotificationId(shiftDate, 'pre'),
        scheduledDate: preAlarmDateTime,
        title: '出勤${preAlarmMinutes}分前です',
        body: '準備をお始めください',
        selectedAlarmSound: selectedAlarmSound,
      );
    }

    // ✅ Step2-2: 権限エラーを優先して返す（どちらも成功・スキップなら null）
    if (mainError == 'EXACT_ALARM_DENIED' || preError == 'EXACT_ALARM_DENIED') {
      return 'EXACT_ALARM_DENIED';
    }
    return mainError ?? preError;
  }

  /// N180 3/3: 出勤前アラーム（pre）だけを登録する（確定・登録し直し・睡眠ボタンから呼ぶ）
  /// - shiftDate：登録した日（ID に使う。取り消しも同じ日で行う）
  /// - startAt：勤務が実際に始まる日時（shiftStartDateTime で出す。0:00〜4:59 開始は登録した日の翌日）
  /// - 鳴る日時は startAt − minutes（過ぎていれば登録しない）
  /// 戻り値は scheduleAlarmForShift と同じ（null=成功・スキップ・アラーム OFF / 'EXACT_ALARM_DENIED' / 'SCHEDULE_FAILED'）
  static Future<String?> schedulePreAlarm({
    required DateTime shiftDate,
    required DateTime startAt,
    required int minutes,
    String selectedAlarmSound = 'default',
  }) async {
    if (!await isAlarmEnabled()) {
      debugPrint('🔕 [AlarmService] アラームOFFのため pre を登録しません: $shiftDate');
      return null;
    }
    final id = _generateNotificationId(shiftDate, 'pre');
    final preAlarmDateTime = startAt.subtract(Duration(minutes: minutes));
    debugPrint('🔔 [AlarmService] pre を登録: 欄 $shiftDate、出勤 $startAt、鳴る $preAlarmDateTime');

    await _scheduleNotification(
      id: id,
      title: '出勤$minutes分前です',
      body: '準備をお始めください',
      scheduledDate: preAlarmDateTime,
      selectedAlarmSound: selectedAlarmSound,
    );
    return _scheduleWithAlarmManager(
      alarmId: id,
      scheduledDate: preAlarmDateTime,
      title: '出勤$minutes分前です',
      body: '準備をお始めください',
      selectedAlarmSound: selectedAlarmSound,
    );
  }

  /// ✅ Step2-2: エラーコードをユーザー向け文言に変換（null=通知不要）
  static String? alarmErrorMessage(String? code) {
    switch (code) {
      case 'EXACT_ALARM_DENIED':
        return '⚠️ アラームを設定できませんでした。端末の設定で『アラームとリマインダー』を許可してください';
      case 'SCHEDULE_FAILED':
        return '⚠️ アラームの設定に失敗しました。もう一度お試しください';
      default:
        return null;
    }
  }

  static Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String selectedAlarmSound = 'default',
  }) async {
    if (Platform.isAndroid) return; // N6: Android はネイティブ（AlarmManager）だけで通知する
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
  /// ✅ Step2-2: 戻り値 null=成功・過去時刻スキップ / 'EXACT_ALARM_DENIED' / 'SCHEDULE_FAILED'
  static Future<String?> _scheduleWithAlarmManager({
    required int alarmId,
    required DateTime scheduledDate,
    required String title,
    required String body,
    String selectedAlarmSound = 'default',
  }) async {
    // ✅ Step1-B: 過去時刻はネイティブ登録しない（即時発火防止）
    // ※ 同じ alarmId の既存予約はキャンセルしない（他の呼び出し元の有効な予約を守るため）
    if (!scheduledDate.isAfter(DateTime.now())) {
      print('⏭️ [AlarmService] AlarmManager 登録スキップ（過去時刻）: ID=$alarmId, 予定=$scheduledDate');
      return null;
    }

    try {
      print('⏰ AlarmManager スケジュール開始');
      print('⏰ アラーム ID: $alarmId');
      print('⏰ スケジュール時刻: $scheduledDate');
      print('🔊 アラーム音: $selectedAlarmSound');

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
          'selectedAlarmSound': selectedAlarmSound,
        },
      );

      print('✅ AlarmManager スケジュール成功: $result');
      return null;
    } on PlatformException catch (e) {
      // ✅ Step1-B: Kotlin 側で過去時刻と判定された場合はスキップとして識別
      if (e.code == 'PAST_TIME') {
        print('⏭️ [AlarmService] AlarmManager 登録スキップ（Kotlin側で過去時刻と判定）: ID=$alarmId');
        return null;
      } else {
        print('❌ AlarmManager スケジュール エラー: ${e.code} ${e.message}');
        return e.code == 'EXACT_ALARM_DENIED' ? 'EXACT_ALARM_DENIED' : 'SCHEDULE_FAILED';
      }
    } catch (e) {
      print('❌ AlarmManager スケジュール エラー: $e');
      return 'SCHEDULE_FAILED';
    }
  }

  /// AlarmManager のアラームをキャンセル
  /// N19：戻り値 true=取り消せた（対象なしを含む）／ false=失敗（例外は外に出さない）
  static Future<bool> _cancelWithAlarmManager(int alarmId) async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        'cancelAlarmWithAlarmManager',
        {'alarmId': alarmId},
      );
      // ✅ Step1-A: 成功／対象なしは Kotlin の戻り値で区別する
      print('✅ AlarmManager キャンセル処理完了: $result');
      return true;
    } catch (e) {
      print('❌ AlarmManager キャンセル エラー: $e');
      return false;
    }
  }

  /// N126: 控え（shiftsleep_native_alarms）から未来の予約を登録し直す（起動時に main.dart から呼ぶ）
  ///    Android のときだけ。件数はログだけ（ユーザーには出さない）。例外は外に出さない
  static Future<void> restoreSavedAlarms() async {
    if (!Platform.isAndroid) return;
    try {
      final counts = await _methodChannel.invokeMapMethod<String, int>('restoreAlarms');
      debugPrint('🔄 [AlarmService] 控えから登録し直し：$counts');
    } catch (e) {
      debugPrint('❌ [AlarmService] 控えからの登録し直しエラー: $e');
    }
  }

  /// N181: 控え（shiftsleep_native_alarms）にある予約をまとめて取り消し、控えを空にする（アラームを OFF にしたとき）
  ///    Android のときだけ（ほかには控えがないので true）。戻り値 true=全部取り消せた。例外は外に出さない
  static Future<bool> cancelAllSavedAlarms() async {
    if (!Platform.isAndroid) return true;
    try {
      final counts = await _methodChannel.invokeMapMethod<String, int>('cancelAllAlarms');
      debugPrint('🔕 [AlarmService] 控えの予約をまとめて取り消し：$counts');
      return cancelAllSucceeded(counts);
    } catch (e) {
      debugPrint('❌ [AlarmService] 控えの予約をまとめて取り消せませんでした: $e');
      return false;
    }
  }

  /// N181: cancelAllAlarms の件数の Map から、全部取り消せたかを決める（failed が 0 のときだけ true）
  @visibleForTesting
  static bool cancelAllSucceeded(Map<String, int>? counts) => counts != null && counts['failed'] == 0;

  /// N129 2/2: 今アラームの音が鳴っているか（サービス・予備の経路のどちらでも true）
  ///    Android のときだけ。例外は外に出さず false を返す
  static Future<bool> isAlarmSoundPlaying() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _methodChannel.invokeMethod<bool>('isAlarmSoundPlaying') ?? false;
    } catch (e) {
      debugPrint('❌ [AlarmService] 鳴っているかの確認エラー: $e');
      return false;
    }
  }

  /// N129 2/2 D2: デバッグ用に、シフトを使わず 10 秒後に本番と同じ経路で鳴らす（設定画面の kDebugMode のボタンから呼ぶ）
  ///    戻り値 null=成功 / 'EXACT_ALARM_DENIED' / 'SCHEDULE_FAILED'
  static Future<String?> scheduleDebugAlarm({required String selectedAlarmSound}) {
    return _scheduleWithAlarmManager(
      alarmId: _debugAlarmId,
      scheduledDate: DateTime.now().add(const Duration(seconds: 10)),
      title: 'デバッグ用アラーム',
      body: '10 秒後に鳴らすボタンから登録しました',
      selectedAlarmSound: selectedAlarmSound,
    );
  }

  static int _generateNotificationId(DateTime date, String type) {
    final dateStr =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final typeNum = type == 'main' ? 0 : 1;
    return int.parse('$dateStr$typeNum');
  }

  /// N19：戻り値 true=main・pre とも AlarmManager から取り消せた
  static Future<bool> cancelAlarm(DateTime date) async {
    final mainAlarmId = _generateNotificationId(date, 'main');
    final preAlarmId = _generateNotificationId(date, 'pre');

    // flutter_local_notifications をキャンセル
    await _notificationsPlugin.cancel(mainAlarmId);
    await _notificationsPlugin.cancel(preAlarmId);

    // ✅ AlarmManager もキャンセル
    final mainCancelled = await _cancelWithAlarmManager(mainAlarmId);
    final preCancelled = await _cancelWithAlarmManager(preAlarmId);

    print('✓ アラームをキャンセルしました: $date');
    return mainCancelled && preCancelled;
  }

  /// ✅ H1: 起床時刻アラーム（main）だけをキャンセルする（出勤前アラーム pre には触れない）
  /// N19：戻り値 true=AlarmManager から取り消せた
  static Future<bool> cancelMainAlarm(DateTime date) async {
    final mainAlarmId = _generateNotificationId(date, 'main');

    // flutter_local_notifications の main のみキャンセル
    await _notificationsPlugin.cancel(mainAlarmId);

    // AlarmManager の main のみキャンセル
    final cancelled = await _cancelWithAlarmManager(mainAlarmId);

    print('✓ 起床アラーム（main）をキャンセルしました: $date');
    return cancelled;
  }

  /// ✅ H3: 出勤前アラーム（pre）だけをキャンセルする（起床時刻アラーム main には触れない）
  /// N180 2/3：戻り値 true=AlarmManager から取り消せた（対象なしを含む）
  static Future<bool> cancelPreAlarm(DateTime date) async {
    final preAlarmId = _generateNotificationId(date, 'pre');

    // flutter_local_notifications の pre のみキャンセル
    await _notificationsPlugin.cancel(preAlarmId);

    // AlarmManager の pre のみキャンセル（成功／対象なし／エラーは _cancelWithAlarmManager がログ出力）
    final cancelled = await _cancelWithAlarmManager(preAlarmId);

    print('✓ 出勤前アラーム（pre）をキャンセルしました: $date');
    return cancelled;
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

      // ✅ N52: 試聴も本番と同じアラーム音量の系統（USAGE_ALARM）で鳴らす（試聴の大きさ＝本番の大きさ）
      await _testAudioPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
        ),
      );

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
  
  /// 🆕 追加：既に鳴っている AlarmReceiver の音声を停止
  /// N129 2/2: 戻り値 true=止めた / false=止められなかった（例外は今までどおり外に出さない）
  static Future<bool> stopAlarmSound() async {
    try {
      final result = await _methodChannel.invokeMethod('stopAlarm');
      print('✅ stopAlarmSound 呼び出し成功: $result');
      return true;
    } catch (e) {
      print('❌ stopAlarmSound エラー: $e');
      return false;
    }
  }
}