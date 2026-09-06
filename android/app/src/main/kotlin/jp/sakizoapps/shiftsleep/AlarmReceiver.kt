package jp.sakizoapps.shiftsleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d("AlarmReceiver", "🔔 onReceive() が呼ばれました！")
        Log.d("AlarmReceiver", "Action: ${intent?.action}")
        Log.d("AlarmReceiver", "Intent: ${intent?.toUri(Intent.URI_INTENT_SCHEME)}")

        if (intent == null) {
            Log.e("AlarmReceiver", "❌ Intent が null です")
            return
        }

        if (context == null) {
            Log.e("AlarmReceiver", "❌ Context が null です")
            return
        }

        Log.d("AlarmReceiver", "📍 intent.action: ${intent.action}")

        // Intent から値を取得
        val alarmId = intent.getIntExtra("alarmId", -1)
        val title = intent.getStringExtra("title") ?: "ShiftSleep アラーム"
        val body = intent.getStringExtra("body") ?: "出勤時間です"
        val selectedAlarmSound = intent.getStringExtra("selectedAlarmSound") ?: "default"

        Log.d("AlarmReceiver", "📍 alarmId: $alarmId, title: $title, body: $body, sound: $selectedAlarmSound")

        // ===== WAKE_LOCK 取得（デバイスをスリープから起動） =====
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "ShiftSleep:AlarmWakeLock"
            )
        } else {
            @Suppress("DEPRECATION")
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
            showNotification(context, alarmId, title, body, selectedAlarmSound)

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
    private fun showNotification(
        context: Context,
        alarmId: Int,
        title: String,
        body: String,
        selectedAlarmSound: String
    ) {
        try {
            // selectedAlarmSound に基づいてチャネルを決定
            val channelId = getChannelId(selectedAlarmSound)
            val soundUri = getSoundUri(context, selectedAlarmSound)

            Log.d("AlarmReceiver", "🔊 使用チャネル: $channelId, 音声: $selectedAlarmSound")

            // NotificationCompat.Builder で通知を構築
            val notificationBuilder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setVibrate(longArrayOf(0, 500, 200, 500))  // バイブレーション
                .setSound(soundUri)  // ★ 音声を明示的に設定

            // 通知を表示
            val notificationManager = NotificationManagerCompat.from(context)
            notificationManager.notify(alarmId, notificationBuilder.build())

            Log.d("AlarmReceiver", "✅ 通知表示完了: $title (チャネル: $channelId)")

        } catch (e: Exception) {
            Log.e("AlarmReceiver", "❌ 通知表示エラー: ${e.message}", e)
        }
    }

    /**
     * selectedAlarmSound に基づいてチャネルID を取得
     */
    private fun getChannelId(selectedAlarmSound: String): String {
        return when (selectedAlarmSound) {
            "gentle" -> "alarm_channel_gentle"
            "harsh" -> "alarm_channel_harsh"
            else -> "alarm_channel_default"
        }
    }

    /**
     * selectedAlarmSound に基づいて音声 Uri を取得
     */
    private fun getSoundUri(context: Context, selectedAlarmSound: String): Uri {
        val soundFileName = when (selectedAlarmSound) {
            "gentle" -> "alarm_gentle"
            "harsh" -> "alarm_harsh"
            else -> "alarm_default"
        }

        // android.resource:// スキームで raw フォルダのファイルを指定
        val resourceId = context.resources.getIdentifier(
            soundFileName,
            "raw",
            context.packageName
        )

        return if (resourceId != 0) {
            Uri.parse("android.resource://${context.packageName}/$resourceId")
        } else {
            // リソースが見つからない場合はシステムデフォルト音を使用
            Log.w("AlarmReceiver", "⚠️ $soundFileName が見つかりません。デフォルト音を使用します")
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        }
    }
}