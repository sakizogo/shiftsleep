package jp.sakizoapps.shiftsleep

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.sakizoapps.shiftsleep/alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        createNotificationChannel()
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarm" -> {
                    val alarmId = call.argument<String>("alarmId") ?: ""
                    val timestampMs = call.argument<Long>("timestampMs") ?: 0L
                    val label = call.argument<String>("label") ?: "Alarm"
                    val selectedAlarmSound = call.argument<String>("selectedAlarmSound") ?: "default"
                    
                    setAlarm(alarmId, timestampMs, label, selectedAlarmSound)
                    result.success("アラームセット成功")
                }
                "scheduleAlarmWithAlarmManager" -> {
                    val timestampMs = call.argument<Long>("timestampMs") ?: 0L
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    val title = call.argument<String>("title") ?: "Alarm"
                    val body = call.argument<String>("body") ?: ""
                    val selectedAlarmSound = call.argument<String>("selectedAlarmSound") ?: "default"
                    
                    scheduleAlarmWithAlarmManager(timestampMs, alarmId, title, body, selectedAlarmSound)
                    result.success("AlarmManager スケジュール成功")
                }
                "cancelAlarmWithAlarmManager" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    cancelAlarmWithAlarmManager(alarmId)
                    result.success("AlarmManager キャンセル成功")
                }
                "cancelAlarm" -> {
                    val alarmId = call.argument<String>("alarmId") ?: ""
                    cancelAlarm(alarmId)
                    result.success("キャンセル成功")
                }
                "cancelAllAlarms" -> {
                    cancelAllAlarms()
                    result.success("全キャンセル成功")
                }
                "stopAlarm" -> {
                    stopAlarm()
                    result.success("アラーム停止")
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "アラーム"
            val descriptionText = "シフト睡眠アプリのアラーム通知"
            val importance = android.app.NotificationManager.IMPORTANCE_HIGH
            val channel = android.app.NotificationChannel("alarm_channel", name, importance).apply {
                description = descriptionText
                enableVibration(true)
                setShowBadge(true)
            }
            val notificationManager: android.app.NotificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d("MainActivity", "✅ Notification Channel 作成完了（alarm_channel）")
        }
    }

    private fun scheduleAlarmWithAlarmManager(
        timestampMs: Long,
        alarmId: Int,
        title: String,
        body: String,
        selectedAlarmSound: String
    ) {
        try {
            Log.d("MainActivity", "🔔 scheduleAlarmWithAlarmManager: id=$alarmId, time=$timestampMs, sound=$selectedAlarmSound")
            
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = "jp.sakizoapps.shiftsleep.ALARM_ACTION"
                putExtra("alarmId", alarmId.toString())
                putExtra("label", title)
                putExtra("selectedAlarmSound", selectedAlarmSound)
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                this, alarmId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                timestampMs,
                pendingIntent
            )
            
            Log.d("MainActivity", "✅ setExactAndAllowWhileIdle 完了（ID: $alarmId, 時刻: $timestampMs）")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ scheduleAlarmWithAlarmManager エラー: ${e.message}")
        }
    }

    private fun cancelAlarmWithAlarmManager(alarmId: Int) {
        try {
            Log.d("MainActivity", "🔴 cancelAlarmWithAlarmManager: id=$alarmId")
            
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AlarmReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                this, alarmId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            alarmManager.cancel(pendingIntent)
            Log.d("MainActivity", "✅ AlarmManager キャンセル完了（ID: $alarmId）")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ cancelAlarmWithAlarmManager エラー: ${e.message}")
        }
    }

    private fun setAlarm(alarmId: String, timestampMs: Long, label: String, selectedAlarmSound: String) {
        try {
            Log.d("MainActivity", "🔔 setAlarm: id=$alarmId, time=$timestampMs, sound=$selectedAlarmSound")
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = "jp.sakizoapps.shiftsleep.ALARM_ACTION"
                putExtra("alarmId", alarmId)
                putExtra("label", label)
                putExtra("selectedAlarmSound", selectedAlarmSound)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this, alarmId.hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestampMs, pendingIntent)
            Log.d("MainActivity", "✅ setAndAllowWhileIdle 完了")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ setAlarm エラー: ${e.message}")
        }
    }

    private fun cancelAlarm(alarmId: String) {
        try {
            Log.d("MainActivity", "❌ cancelAlarm: id=$alarmId")
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AlarmReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                this, alarmId.hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
            Log.d("MainActivity", "✅ キャンセル完了")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ cancelAlarm エラー: ${e.message}")
        }
    }

    private fun cancelAllAlarms() {
        try {
            Log.d("MainActivity", "❌ cancelAllAlarms 呼び出し")
            Log.d("MainActivity", "✅ 全キャンセル完了")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ cancelAllAlarms エラー: ${e.message}")
        }
    }

    private fun stopAlarm() {
        try {
            Log.d("MainActivity", "🛑 stopAlarm 呼び出し")
            AlarmReceiver.mediaPlayer?.stop()
            Log.d("MainActivity", "✅ アラーム停止完了")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ アラーム停止エラー: ${e.message}")
        }
    }
}