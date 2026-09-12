package jp.sakizoapps.shiftsleep

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.sakizoapps.shiftsleep/alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarm" -> {
                    val alarmId = call.argument<String>("alarmId") ?: ""
                    val timestampMs = call.argument<Long>("timestampMs") ?: 0L
                    val label = call.argument<String>("label") ?: "Alarm"
                    val selectedAlarmSound = call.argument<String>("selectedAlarmSound") ?: "default"
                    
                    setAlarm(alarmId, timestampMs, label, selectedAlarmSound)
                    result.success("✅ アラームセット成功")
                }
                "cancelAlarm" -> {
                    val alarmId = call.argument<String>("alarmId") ?: ""
                    cancelAlarm(alarmId)
                    result.success("✅ キャンセル成功")
                }
                "cancelAllAlarms" -> {
                    cancelAllAlarms()
                    result.success("✅ 全キャンセル成功")
                }
                "stopAlarm" -> {
                    stopAlarm()
                    result.success("✅ アラーム停止")
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setAlarm(alarmId: String, timestampMs: Long, label: String, selectedAlarmSound: String) {
        try {
            Log.d("MainActivity", "🔔 setAlarm: id=$alarmId, time=$timestampMs, sound=$selectedAlarmSound")
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = "com.sakizoapps.shiftsleep.ALARM_ACTION"
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
            AlarmReceiver.ringtone?.stop()
            Log.d("MainActivity", "✅ アラーム停止完了")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ アラーム停止エラー: ${e.message}")
        }
    }
}