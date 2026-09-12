package jp.sakizoapps.shiftsleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import android.util.Log

class AlarmReceiver : BroadcastReceiver() {
  companion object {
    var ringtone: android.media.Ringtone? = null
  }

  override fun onReceive(context: Context, intent: Intent?) {
    Log.d("AlarmReceiver", "🔔 onReceive() が呼ばれました！")
    Log.d("AlarmReceiver", "Action: ${intent?.action}")

    if (intent == null || context == null) {
      Log.e("AlarmReceiver", "❌ Intent または Context が null")
      return
    }

    val alarmId = intent.getStringExtra("alarmId") ?: "unknown"
    val label = intent.getStringExtra("label") ?: "Alarm"
    val selectedAlarmSound = intent.getStringExtra("selectedAlarmSound") ?: "default"

    Log.d("AlarmReceiver", "🔔 アラーム発火！ ID: $alarmId, Label: $label, Sound: $selectedAlarmSound")

    showNotification(context, alarmId, label)
    playAlarmSound(context, selectedAlarmSound)
    vibrate(context)
  }

  private fun showNotification(context: Context, alarmId: String, label: String) {
    try {
      val notification = NotificationCompat.Builder(context, "alarm_channel")
        .setSmallIcon(android.R.drawable.ic_dialog_info)
        .setContentTitle("⏰ アラーム")
        .setContentText(label)
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setAutoCancel(true)
        .build()

      val notificationManager = NotificationManagerCompat.from(context)
      notificationManager.notify(alarmId.hashCode(), notification)

      Log.d("AlarmReceiver", "✅ 通知表示完了")
    } catch (e: Exception) {
      Log.e("AlarmReceiver", "❌ 通知表示エラー: ${e.message}")
    }
  }

  private fun playAlarmSound(context: Context, selectedAlarmSound: String) {
    try {
      // selectedAlarmSound に応じて、raw フォルダ内のMP3ファイルを指定
      val resourceName = when (selectedAlarmSound) {
        "gentle" -> "alarm_gentle"
        "harsh" -> "alarm_harsh"
        else -> "alarm_default"
      }
      
      // Uri を構築
      val ringtoneUri = Uri.parse("android.resource://${context.packageName}/raw/$resourceName")
      
      ringtone = RingtoneManager.getRingtone(context, ringtoneUri)
      ringtone?.play()
      Log.d("AlarmReceiver", "🔊 アラーム音再生開始: $selectedAlarmSound (resource: $resourceName)")
    } catch (e: Exception) {
      Log.e("AlarmReceiver", "❌ アラーム音再生エラー: ${e.message}")
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