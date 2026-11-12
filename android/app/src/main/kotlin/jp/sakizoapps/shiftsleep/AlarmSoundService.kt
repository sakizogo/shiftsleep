package jp.sakizoapps.shiftsleep

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.PendingIntentCompat
import androidx.core.app.ServiceCompat

// N29: アラーム音をフォアグラウンドサービスで鳴らす
// （アプリを「最近使ったアプリ」からスワイプで消したあとでも、音が鳴り続けるようにする）
// - 起動：AlarmReceiver が startForegroundService で起動する（Step 5 で切り替え）
// - 停止：stopService（停止ボタンは AlarmReceiver 経由、「起きる」は MainActivity.stopAlarm 経由）
// - 60 秒で自動停止（N27: 起床扱いにはしない。「自動で止まりました」の通知を残す）
class AlarmSoundService : Service() {
  companion object {
    private const val TAG = "AlarmSoundService"
    const val CHANNEL_ID = "alarm_channel"
    const val AUTO_STOP_DURATION_MS = 60000L
    const val PLAY_DURATION_MS = 500L
    const val SILENCE_DURATION_MS = 200L
    private const val WAKE_LOCK_TIMEOUT_MS = 70000L

    // N129 2/2: 音が鳴っているか（MainActivity の isAlarmSoundPlaying から読む）
    // プロセスが消えると音も止まるので、SharedPreferences ではなく static で持つ
    var isSoundPlaying = false
      private set

    // N27: 自動停止のお知らせ通知（前面通知とは別の ID。音・バイブなし。「起きる」で消える）
    fun showAutoStoppedNotification(context: Context, alarmId: String) {
      try {
        val openIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
          flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPendingIntent = openIntent?.let {
          PendingIntentCompat.getActivity(
            context,
            alarmId.hashCode() + 2,
            it,
            PendingIntent.FLAG_UPDATE_CURRENT,
            false
          )
        }
        val text = "起きたら睡眠を記録するため「起きる」を押してください"
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
          .setSmallIcon(R.drawable.ic_stat_alarm)
          .setContentTitle("⏰ アラームが自動で止まりました")
          .setContentText(text)
          .setStyle(NotificationCompat.BigTextStyle().bigText(text))
          .setPriority(NotificationCompat.PRIORITY_HIGH)
          .setSilent(true)
          .setAutoCancel(false)
          .setContentIntent(openPendingIntent)
          .build()
        NotificationManagerCompat.from(context).notify(alarmId.hashCode() + 3, notification)
        Log.d(TAG, "✅ 自動停止の通知を表示しました")
      } catch (e: Exception) {
        Log.e(TAG, "❌ 自動停止の通知エラー: ${e.message}")
      }
    }

    // N49: アプリの設定画面で保存した音量（0〜100）を読む。保存していない・読めないときは 1.0（最大）
    // shared_preferences の従来型 API の保存形式に依存（Dart の setInt は Long で保存される）
    fun readAlarmVolume(context: Context): Float {
      return try {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val percent = prefs.getLong("flutter.alarm_volume_percent", 100L).coerceIn(0L, 100L)
        percent / 100f
      } catch (e: Exception) {
        Log.e(TAG, "❌ 音量の読み込みエラー（最大で鳴らします）: ${e.message}")
        1.0f
      }
    }
  }

  private var mediaPlayer: MediaPlayer? = null
  private var handler: Handler? = null
  private var wakeLock: PowerManager.WakeLock? = null
  private var isPlaying = false
  private var startTimeMs: Long = 0
  private var currentAlarmId: String? = null

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent == null) {
      Log.w(TAG, "⚠️ Intent が null のため停止します")
      stopSelf()
      return START_NOT_STICKY
    }

    val alarmId = intent.getStringExtra("alarmId") ?: "unknown"
    val label = intent.getStringExtra("label") ?: "Alarm"
    val body = intent.getStringExtra("body") ?: ""
    val selectedAlarmSound = intent.getStringExtra("selectedAlarmSound") ?: "default"

    Log.d(TAG, "🔔 サービス開始 ID: $alarmId, Label: $label, Sound: $selectedAlarmSound")

    // N34: 鳴っている途中で次のアラームが来たら、前の再生を片付けてから始める
    val previousAlarmId = currentAlarmId
    releasePlayback()
    currentAlarmId = alarmId

    // N31: アプリを一度も開いていなくても通知が出せるように、ここでもチャンネルを作る
    ensureNotificationChannel()

    try {
      val notification = buildNotification(alarmId, label, body)
      val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
      } else {
        0
      }
      // N141: 確かめる用（debuggable のときだけ）。F3 を起こす（startForeground を呼ばないまま下の catch へ）
      if (DebugFailFlag.shouldFail(this, DebugFailFlag.START_FOREGROUND)) {
        throw IllegalStateException("debug: start_foreground")
      }
      ServiceCompat.startForeground(this, alarmId.hashCode(), notification, type)
      Log.d(TAG, "✅ 前面通知を表示しました")
      // N34: 前のアラームの通知は、前面サービスの通知から外れたあとで消す
      if (previousAlarmId != null && previousAlarmId != alarmId) {
        NotificationManagerCompat.from(this).cancel(previousAlarmId.hashCode())
      }
    } catch (e: Exception) {
      Log.e(TAG, "❌ startForeground エラー（予備の経路で鳴らします）: ${e.message}")
      // N141: 予備の経路の通知は同じ id で出すので、先に前面の通知を外し、onDestroy でも消さないようにする
      ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
      currentAlarmId = null
      AlarmReceiver().startFallback(applicationContext, alarmId, label, body, selectedAlarmSound)
      stopSelf()
      return START_NOT_STICKY
    }

    acquireWakeLock()
    vibrate(500)
    startPlayback(selectedAlarmSound)

    return START_NOT_STICKY
  }

  override fun onDestroy() {
    Log.d(TAG, "🛑 サービス終了")
    releasePlayback()
    ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
    currentAlarmId?.let { NotificationManagerCompat.from(this).cancel(it.hashCode()) }
    currentAlarmId = null
    super.onDestroy()
  }

  private fun ensureNotificationChannel() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel = NotificationChannel(CHANNEL_ID, "アラーム", NotificationManager.IMPORTANCE_HIGH).apply {
        description = "シフト睡眠アプリのアラーム通知"
        enableVibration(true)
        setShowBadge(true)
      }
      val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      nm.createNotificationChannel(channel)
    }
  }

  private fun buildNotification(alarmId: String, label: String, body: String): Notification {
    // 停止ボタン：今までどおり AlarmReceiver の STOP_ALARM に送る
    val stopIntent = Intent(this, AlarmReceiver::class.java).apply {
      action = "jp.sakizoapps.shiftsleep.STOP_ALARM"
      putExtra("alarmId", alarmId)
    }
    val stopPendingIntent = PendingIntentCompat.getBroadcast(
      this,
      alarmId.hashCode() + 1,
      stopIntent,
      PendingIntent.FLAG_UPDATE_CURRENT,
      false
    )

    // 通知をタップしたらアプリを開く（音は止めない。止めるのは「停止」ボタンだけ）
    val openIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
      flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
    }
    val openPendingIntent = openIntent?.let {
      PendingIntentCompat.getActivity(
        this,
        alarmId.hashCode() + 2,
        it,
        PendingIntent.FLAG_UPDATE_CURRENT,
        false
      )
    }

    return NotificationCompat.Builder(this, CHANNEL_ID)
      .setSmallIcon(R.drawable.ic_stat_alarm)
      .setContentTitle("⏰ $label")
      .setContentText(body.ifEmpty { label })
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      // N32: アラームとして扱わせる（おやすみモードで「アラームを許可」なら抑えられない）・ロック画面でも本文と［停止］を見せる
      .setCategory(NotificationCompat.CATEGORY_ALARM)
      .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      .setAutoCancel(false)
      .setContentIntent(openPendingIntent)
      .addAction(
        android.R.drawable.ic_menu_close_clear_cancel,
        "停止",
        stopPendingIntent
      )
      .build()
  }

  private fun startPlayback(selectedAlarmSound: String) {
    val resourceName = when (selectedAlarmSound) {
      "gentle" -> "alarm_gentle"
      "harsh" -> "alarm_harsh"
      else -> "alarm_default"
    }
    // N49: アプリで設定した音量で鳴らす（端末のアラーム音量に掛け算される）
    val volume = readAlarmVolume(this)
    val failFlag = DebugFailFlag.read(this)

    // N141: 選んだ音 → alarm_default の順に試す。どちらもだめなら音なし（バイブだけ）で鳴らし続ける
    // 前面サービス・通知・60 秒の自動停止は、音があってもなくても同じ（stopSelf はしない）
    mediaPlayer = createPlayer(
      resourceName, volume,
      debugFail = failFlag == DebugFailFlag.PREPARE || failFlag == DebugFailFlag.PREPARE_ALL
    ) ?: createPlayer("alarm_default", volume, debugFail = failFlag == DebugFailFlag.PREPARE_ALL)

    // バイブだけのときも「鳴っている」扱い（音量 0% のときと同じ。ホームの「起きる」の表示に使う）
    isPlaying = true
    isSoundPlaying = true
    startTimeMs = System.currentTimeMillis()
    handler = Handler(Looper.getMainLooper())

    if (mediaPlayer != null) {
      Log.d(TAG, "🔊 アラーム音繰り返し再生開始: $selectedAlarmSound（USAGE_ALARM、音量 ${(volume * 100).toInt()}%）")
    } else {
      Log.w(TAG, "⚠️ 音源を準備できないため、バイブだけで鳴らします")
    }
    playLoop()
    startAutoStopCheck()
  }

  // N141: 音源を準備する。失敗したら作りかけの MediaPlayer を片付けて null を返す（N130 の予備の経路と同じ考え方）
  // debugFail：確かめる用（DebugFailFlag）。prepare の直前で失敗させる
  private fun createPlayer(resourceName: String, volume: Float, debugFail: Boolean): MediaPlayer? {
    var player: MediaPlayer? = null
    return try {
      val resourceId = resources.getIdentifier(resourceName, "raw", packageName)
      val uri = Uri.parse("android.resource://$packageName/$resourceId")
      // 先に player に入れてから組み立てる（途中で失敗しても catch で release できるように）
      player = MediaPlayer()
      player.apply {
        // N29: アラーム音量で鳴らす（メディア音量が 0 でも鳴る）
        setAudioAttributes(
          AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        )
        setDataSource(this@AlarmSoundService, uri)
        setVolume(volume, volume)
        if (debugFail) throw IllegalStateException("debug: prepare")
        prepare()
      }
      player
    } catch (e: Exception) {
      Log.e(TAG, "❌ 音源の準備エラー（$resourceName）: ${e.message}")
      player?.release()
      null
    }
  }

  // 0.5 秒鳴らして 0.2 秒止める、をくり返す（AlarmReceiver と同じ動き）
  private fun playLoop() {
    handler?.post {
      if (!isPlaying) return@post
      try {
        mediaPlayer?.seekTo(0)
        mediaPlayer?.start()
        vibrate(100)
        handler?.postDelayed({
          // N141: 音なし（バイブだけ）のときは player がないので、そのまま続ける（音ありで止まったときの扱いは N177）
          val player = mediaPlayer
          if (isPlaying && (player == null || player.isPlaying)) {
            player?.pause()
            handler?.postDelayed({ playLoop() }, SILENCE_DURATION_MS)
          }
        }, PLAY_DURATION_MS)
      } catch (e: Exception) {
        Log.e(TAG, "❌ 再生ループエラー: ${e.message}")
      }
    }
  }

  // 1 秒ごとに確認し、60 秒たったら止める（N27: 起床扱いにはせず、お知らせ通知を残す）
  private fun startAutoStopCheck() {
    handler?.postDelayed({
      if (isPlaying) {
        val elapsed = System.currentTimeMillis() - startTimeMs
        if (elapsed >= AUTO_STOP_DURATION_MS) {
          Log.d(TAG, "⏰ 1分経過。自動停止します（起床扱いにはしません）")
          currentAlarmId?.let { showAutoStoppedNotification(this@AlarmSoundService, it) }
          stopSelf()
        } else {
          startAutoStopCheck()
        }
      }
    }, 1000L)
  }

  private fun releasePlayback() {
    isPlaying = false
    isSoundPlaying = false
    handler?.removeCallbacksAndMessages(null)
    handler = null
    try {
      mediaPlayer?.stop()
    } catch (e: Exception) {
      Log.e(TAG, "❌ 停止エラー: ${e.message}")
    }
    mediaPlayer?.release()
    mediaPlayer = null
    wakeLock?.let { if (it.isHeld) it.release() }
    wakeLock = null
  }

  private fun acquireWakeLock() {
    try {
      val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
      wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ShiftSleep:AlarmSound").apply {
        setReferenceCounted(false)
        acquire(WAKE_LOCK_TIMEOUT_MS)
      }
    } catch (e: Exception) {
      Log.e(TAG, "❌ WakeLock エラー: ${e.message}")
    }
  }

  @Suppress("DEPRECATION")
  private fun vibrate(durationMs: Long) {
    try {
      val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
      } else {
        vibrator.vibrate(durationMs)
      }
    } catch (e: Exception) {
      Log.e(TAG, "❌ バイブレーションエラー: ${e.message}")
    }
  }
}
