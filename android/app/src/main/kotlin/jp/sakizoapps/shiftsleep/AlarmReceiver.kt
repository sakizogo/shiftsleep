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
      stopAlarm()
      return
    }

    val alarmId = intent.getStringExtra("alarmId") ?: "unknown"
    val label = intent.getStringExtra("label") ?: "Alarm"
    val selectedAlarmSound = intent.getStringExtra("selectedAlarmSound") ?: "default"

    Log.d("AlarmReceiver", "🔔 アラーム発火！ ID: $alarmId, Label: $label, Sound: $selectedAlarmSound")

    showNotification(context, alarmId, label)
    playAlarmSoundContinuous(context, selectedAlarmSound)
    vibrate(context)
  }

  private fun showNotification(context: Context, alarmId: String, label: String) {
    try {
      val stopIntent = Intent(context, AlarmReceiver::class.java).apply {
        action = "jp.sakizoapps.shiftsleep.STOP_ALARM"
      }
      val stopPendingIntent = PendingIntentCompat.getBroadcast(
        context,
        alarmId.hashCode() + 1,
        stopIntent,
        android.app.PendingIntent.FLAG_UPDATE_CURRENT,
        false
      )

      val notification = NotificationCompat.Builder(context, "alarm_channel")
        .setSmallIcon(android.R.drawable.ic_dialog_info)
        .setContentTitle("⏰ アラーム")
        .setContentText(label)
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setAutoCancel(false)
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

  private fun playAlarmSoundContinuous(context: Context, selectedAlarmSound: String) {
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
      
      mediaPlayer = MediaPlayer().apply {
        setDataSource(context, Uri.parse("android.resource://${context.packageName}/$resourceId"))
        setVolume(1.0f, 1.0f)
      }
      
      mediaPlayer?.prepare()
      
      isAlarmPlaying = true
      alarmStartTime = System.currentTimeMillis()
      alarmHandler = Handler(Looper.getMainLooper())
      
      Log.d("AlarmReceiver", "🔊 アラーム音繰り返し再生開始: $selectedAlarmSound（MediaPlayer）")
      Log.d("AlarmReceiver", "📌 停止ボタンを押すまで鳴らし続けます")
      Log.d("AlarmReceiver", "⏱️ 1分間何もしない場合は自動停止します")
      
      playAlarmLoop(context)
      startAutoStopCheck()
      
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

  private fun startAutoStopCheck() {
    alarmHandler?.postDelayed({
      if (isAlarmPlaying) {
        val elapsedTime = System.currentTimeMillis() - alarmStartTime
        
        if (elapsedTime >= AUTO_STOP_DURATION_MS) {
          Log.d("AlarmReceiver", "⏰ 1分経過。自動停止します。")
          stopAlarm()
        } else {
          val remainingTime = AUTO_STOP_DURATION_MS - elapsedTime
          Log.d("AlarmReceiver", "⏱️ 自動停止まで あと ${remainingTime / 1000}秒")
          startAutoStopCheck()
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