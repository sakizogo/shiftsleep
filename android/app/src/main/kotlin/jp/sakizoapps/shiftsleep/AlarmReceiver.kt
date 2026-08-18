package jp.sakizoapps.shiftsleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        Log.d("AlarmReceiver", "🔔 アラーム発火！")

        if (intent == null) {
            Log.e("AlarmReceiver", "❌ Intent が null です")
            return
        }

        // Intent から値を取得
        val alarmId = intent.getIntExtra("alarmId", -1)
        val title = intent.getStringExtra("title") ?: "ShiftSleep アラーム"
        val body = intent.getStringExtra("body") ?: "出勤時間です"

        Log.d("AlarmReceiver", "📍 alarmId: $alarmId, title: $title, body: $body")

        // ===== WAKE_LOCK 取得（デバイスをスリープから起動） =====
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "ShiftSleep:AlarmWakeLock"
            )
        } else {
            powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "ShiftSleep:AlarmWakeLock"
            )
        }

        try {
            // WAKE_LOCK を 10 秒間取得（十分な時間）
            wakeLock.acquire(10 * 1000L)
            Log.d("AlarmReceiver", "🔌 WAKE_LOCK 取得（10秒間）")

            // ===== 通知を表示 =====
            showNotification(context, alarmId, title, body)

        } catch (e: Exception) {
            Log.e("AlarmReceiver", "❌ エラー: ${e.message}", e)
        } finally {
            // WAKE_LOCK を解放
            if (wakeLock.isHeld) {
                wakeLock.release()
                Log.d("AlarmReceiver", "🔌 WAKE_LOCK 解放")
            }
        }
    }

    /**
     * 通知を表示（flutter_local_notifications が処理）
     *
     * 注：実際の音声再生は flutter_local_notifications が
     * Notification Channel の設定に基づいて行います
     */
    private fun showNotification(context: Context, alarmId: Int, title: String, body: String) {
        try {
            val channelId = "alarm_channel_default"

            // NotificationCompat.Builder で通知を構築
            val notificationBuilder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setVibrate(longArrayOf(0, 500, 200, 500))  // バイブレーション

            // 通知を表示
            val notificationManager = NotificationManagerCompat.from(context)
            notificationManager.notify(alarmId, notificationBuilder.build())

            Log.d("AlarmReceiver", "✅ 通知表示完了: $title")

        } catch (e: Exception) {
            Log.e("AlarmReceiver", "❌ 通知表示エラー: ${e.message}", e)
        }
    }
}