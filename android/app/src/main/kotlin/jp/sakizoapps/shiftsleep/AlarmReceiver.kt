package jp.sakizoapps.shiftsleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import android.util.Log
import androidx.core.app.PendingIntentCompat
import androidx.core.content.ContextCompat

class AlarmReceiver : BroadcastReceiver() {
  companion object {
    var mediaPlayer: MediaPlayer? = null
    var alarmHandler: Handler? = null
    var isAlarmPlaying = false
    var alarmStartTime: Long = 0
    const val AUTO_STOP_DURATION_MS = 60000L
    const val PLAY_DURATION_MS = 500L
    const val SILENCE_DURATION_MS = 200L
  }

  override fun onReceive(context: Context, intent: Intent?) {
    Log.d("AlarmReceiver", "🔔 onReceive() が呼ばれました！")
    Log.d("AlarmReceiver", "Action: ${intent?.action}")

    if (intent == null || context == null) {
      Log.e("AlarmReceiver", "❌ Intent または Context が null")
      return
    }

    if (intent.action == "jp.sakizoapps.shiftsleep.STOP_ALARM") {
      Log.d("AlarmReceiver", "🛑 停止ボタンを押されました")
      handleAlarmStopped(context, intent.getStringExtra("alarmId"))
      return
    }

    val alarmId = intent.getStringExtra("alarmId") ?: "unknown"
    val label = intent.getStringExtra("label") ?: "Alarm"
    val selectedAlarmSound = intent.getStringExtra("selectedAlarmSound") ?: "default"
    val body = intent.getStringExtra("body") ?: ""

    Log.d("AlarmReceiver", "🔔 アラーム発火！ ID: $alarmId, Label: $label, Sound: $selectedAlarmSound")

    // N46: 鳴ったアラームの保存分を消す（AlarmManager の予約は鳴った時点で終わっている）
    alarmId.toIntOrNull()?.let { AlarmScheduler.remove(context, it) }

    // N29: 音はフォアグラウンドサービスで鳴らす（アプリをスワイプで消したあとでも鳴るように）
    try {
      val serviceIntent = Intent(context, AlarmSoundService::class.java).apply {
        putExtra("alarmId", alarmId)
        putExtra("label", label)
        putExtra("body", body)
        putExtra("selectedAlarmSound", selectedAlarmSound)
      }
      ContextCompat.startForegroundService(context, serviceIntent)
      Log.d("AlarmReceiver", "✅ AlarmSoundService を起動しました")
    } catch (e: Exception) {
      // 起動できなかったときは、今までどおりこの中で鳴らす
      Log.e("AlarmReceiver", "❌ AlarmSoundService の起動エラー（従来の方法で鳴らします）: ${e.message}")
      showNotification(context, alarmId, label, body)
      playAlarmSoundContinuous(context, alarmId, selectedAlarmSound)
      vibrate(context)
    }
  }

  private fun showNotification(context: Context, alarmId: String, label: String, body: String) {
    try {
      val stopIntent = Intent(context, AlarmReceiver::class.java).apply {
        action = "jp.sakizoapps.shiftsleep.STOP_ALARM"
        putExtra("alarmId", alarmId)
      }
      val stopPendingIntent = PendingIntentCompat.getBroadcast(
        context,
        alarmId.hashCode() + 1,
        stopIntent,
        android.app.PendingIntent.FLAG_UPDATE_CURRENT,
        false
      )

      // N6: 通知をタップしたらアプリを開く（音は止めない。止めるのは「停止」ボタンだけ）
      val openIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
      }
      val openPendingIntent = openIntent?.let {
        PendingIntentCompat.getActivity(
          context,
          alarmId.hashCode() + 2,
          it,
          android.app.PendingIntent.FLAG_UPDATE_CURRENT,
          false
        )
      }

      val notification = NotificationCompat.Builder(context, "alarm_channel")
        .setSmallIcon(R.drawable.ic_stat_alarm)
        .setContentTitle("⏰ $label")
        .setContentText(body.ifEmpty { label })
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setAutoCancel(false)
        .setContentIntent(openPendingIntent)
        .addAction(
          android.R.drawable.ic_menu_close_clear_cancel,
          "停止",
          stopPendingIntent
        )
        .build()

      val notificationManager = NotificationManagerCompat.from(context)
      notificationManager.notify(alarmId.hashCode(), notification)

      Log.d("AlarmReceiver", "✅ 通知表示完了（停止ボタン付き）")
    } catch (e: Exception) {
      Log.e("AlarmReceiver", "❌ 通知表示エラー: ${e.message}")
    }
  }

  private fun playAlarmSoundContinuous(context: Context, alarmId: String, selectedAlarmSound: String) {
    try {
      val resourceName = when (selectedAlarmSound) {
        "gentle" -> "alarm_gentle"
        "harsh" -> "alarm_harsh"
        else -> "alarm_default"
      }
      
      val resourceId = context.resources.getIdentifier(
        resourceName,
        "raw",
        context.packageName
      )
      
      // N49: アプリで設定した音量で鳴らす
      val volume = AlarmSoundService.readAlarmVolume(context)
      mediaPlayer = MediaPlayer().apply {
        setDataSource(context, Uri.parse("android.resource://${context.packageName}/$resourceId"))
        setVolume(volume, volume)
      }
      
      mediaPlayer?.prepare()
      
      isAlarmPlaying = true
      alarmStartTime = System.currentTimeMillis()
      alarmHandler = Handler(Looper.getMainLooper())
      
      Log.d("AlarmReceiver", "🔊 アラーム音繰り返し再生開始: $selectedAlarmSound（MediaPlayer）")
      Log.d("AlarmReceiver", "📌 停止ボタンを押すまで鳴らし続けます")
      Log.d("AlarmReceiver", "⏱️ 1分間何もしない場合は自動停止します")
      
      playAlarmLoop(context)
      startAutoStopCheck(context, alarmId)
      
    } catch (e: Exception) {
      Log.e("AlarmReceiver", "❌ アラーム音再生エラー: ${e.message}")
    }
  }

  private fun playAlarmLoop(context: Context) {
    alarmHandler?.post {
      if (!isAlarmPlaying) {
        Log.d("AlarmReceiver", "🛑 アラーム再生ループを停止しました")
        return@post
      }

      try {
        mediaPlayer?.seekTo(0)
        mediaPlayer?.start()
        Log.d("AlarmReceiver", "🔊 再生中...（0.5秒）")

        vibrateOnce(context)

        alarmHandler?.postDelayed({
          if (isAlarmPlaying && mediaPlayer?.isPlaying == true) {
            mediaPlayer?.pause()
            Log.d("AlarmReceiver", "🔇 一時停止中...（0.2秒）")
            
            alarmHandler?.postDelayed({
              playAlarmLoop(context)
            }, SILENCE_DURATION_MS)
          }
        }, PLAY_DURATION_MS)
      } catch (e: Exception) {
        Log.e("AlarmReceiver", "❌ 再生ループエラー: ${e.message}")
      }
    }
  }

  private fun startAutoStopCheck(context: Context, alarmId: String) {
    alarmHandler?.postDelayed({
      if (isAlarmPlaying) {
        val elapsedTime = System.currentTimeMillis() - alarmStartTime
        
        if (elapsedTime >= AUTO_STOP_DURATION_MS) {
          Log.d("AlarmReceiver", "⏰ 1分経過。自動停止します。")
          handleAutoStopped(context, alarmId)
        } else {
          val remainingTime = AUTO_STOP_DURATION_MS - elapsedTime
          Log.d("AlarmReceiver", "⏱️ 自動停止まで あと ${remainingTime / 1000}秒")
          startAutoStopCheck(context, alarmId)
        }
      }
    }, 1000L)
  }

  private fun stopAlarm() {
    try {
      isAlarmPlaying = false
      mediaPlayer?.stop()
      mediaPlayer?.release()
      mediaPlayer = null
      alarmHandler?.removeCallbacksAndMessages(null)
      alarmHandler = null
      
      Log.d("AlarmReceiver", "🛑 アラーム停止完了")
    } catch (e: Exception) {
      Log.e("AlarmReceiver", "❌ アラーム停止エラー: ${e.message}")
    }
  }

  // 停止ボタンの処理：音を止める＋通知を消す＋停止時刻を保存（＝起床扱い）
  private fun handleAlarmStopped(context: Context, alarmId: String?) {
    stopAlarm()
    // N29: フォアグラウンドサービスで鳴っている音も止める
    context.stopService(Intent(context, AlarmSoundService::class.java))

    if (alarmId != null) {
      NotificationManagerCompat.from(context).cancel(alarmId.hashCode())
    }

    // shared_preferences の従来型 API の保存形式に依存。
    // SharedPreferencesAsync に移行すると動かない
    context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
      .edit().putLong("flutter.alarm_stopped_at_ms", System.currentTimeMillis()).apply()
  }

  // N27: 予備の鳴らし方での 1 分自動停止：音を止めて、お知らせ通知に差し替える（起床扱いにはしない）
  private fun handleAutoStopped(context: Context, alarmId: String) {
    stopAlarm()
    NotificationManagerCompat.from(context).cancel(alarmId.hashCode())
    AlarmSoundService.showAutoStoppedNotification(context, alarmId)
  }

  private fun vibrateOnce(context: Context) {
    try {
      val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        vibrator.vibrate(VibrationEffect.createOneShot(100, VibrationEffect.DEFAULT_AMPLITUDE))
      } else {
        @Suppress("DEPRECATION")
        vibrator.vibrate(100)
      }
    } catch (e: Exception) {
      Log.e("AlarmReceiver", "❌ バイブレーションエラー: ${e.message}")
    }
  }

  private fun vibrate(context: Context) {
    try {
      val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        vibrator.vibrate(VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE))
      } else {
        @Suppress("DEPRECATION")
        vibrator.vibrate(500)
      }
      Log.d("AlarmReceiver", "📳 バイブレーション実行")
    } catch (e: Exception) {
      Log.e("AlarmReceiver", "❌ バイブレーションエラー: ${e.message}")
    }
  }
}