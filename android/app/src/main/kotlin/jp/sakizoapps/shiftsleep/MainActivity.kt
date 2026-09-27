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
import jp.sakizoapps.shiftsleep.AlarmReceiver  // ← 🆕 追加

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
                    
                    // ✅ Step1-B: 過去時刻は登録しない（setExactAndAllowWhileIdle は過去時刻だと即時発火する）
                    // ※ 同じ alarmId の既存予約はキャンセルしない（他の呼び出し元の有効な予約を守るため）
                    val now = System.currentTimeMillis()
                    if (timestampMs <= now) {
                        Log.w("MainActivity", "⏭️ 過去時刻のため登録スキップ（ID: $alarmId, time=$timestampMs, now=$now）")
                        result.error("PAST_TIME", "過去時刻のためアラームを登録しません", alarmId)
                        return@setMethodCallHandler
                    }

                    // ✅ Step2-1: 登録結果に応じて戻り値を分ける（null=成功 / それ以外=エラーコード）
                    val errorCode = scheduleAlarmWithAlarmManager(timestampMs, alarmId, title, body, selectedAlarmSound)
                    if (errorCode == null) {
                        result.success("AlarmManager スケジュール成功")
                    } else {
                        result.error(errorCode, "AlarmManager スケジュール失敗", alarmId)
                    }
                }
                "cancelAlarmWithAlarmManager" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    // ✅ Step1-A: 取消結果に応じて戻り値を分ける（null=例外）
                    when (cancelAlarmWithAlarmManager(alarmId)) {
                        true -> result.success("AlarmManager キャンセル成功")
                        false -> result.success("AlarmManager キャンセル対象なし")
                        null -> result.error("CANCEL_FAILED", "AlarmManager キャンセル失敗", alarmId)
                    }
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

    // ✅ Step2-1: 戻り値 null=登録成功 / "EXACT_ALARM_DENIED"=権限なし / "SCHEDULE_FAILED"=その他の失敗
    private fun scheduleAlarmWithAlarmManager(
        timestampMs: Long,
        alarmId: Int,
        title: String,
        body: String,
        selectedAlarmSound: String
    ): String? {
        try {
            Log.d("MainActivity", "🔔 scheduleAlarmWithAlarmManager: id=$alarmId, time=$timestampMs, sound=$selectedAlarmSound")
            
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // ✅ Step2-1: Android 12 以降は登録前に正確なアラームの権限を確認（権限なしなら登録しない）
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                Log.w("MainActivity", "⛔ 正確なアラームの権限がないため登録しません（ID: $alarmId）")
                return "EXACT_ALARM_DENIED"
            }
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
            return null
        } catch (e: SecurityException) {
            // ✅ Step2-1: 権限不足による失敗を識別して返す
            Log.e("MainActivity", "❌ 正確なアラームの権限エラー: ${e.message}")
            return "EXACT_ALARM_DENIED"
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ scheduleAlarmWithAlarmManager エラー: ${e.message}")
            return "SCHEDULE_FAILED"
        }
    }

    // ✅ Step1-A: 戻り値 true=取消成功 / false=対象なし / null=例外
    private fun cancelAlarmWithAlarmManager(alarmId: Int): Boolean? {
        try {
            Log.d("MainActivity", "🔴 cancelAlarmWithAlarmManager: id=$alarmId")
            
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // ✅ Step1-A: 登録時と同じ action を付けて同一の PendingIntent に一致させる
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = "jp.sakizoapps.shiftsleep.ALARM_ACTION"
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this, alarmId, intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            
            // ✅ Step1-A: 既存の PendingIntent がなければ「対象なし」（正常）
            if (pendingIntent == null) {
                Log.d("MainActivity", "ℹ️ キャンセル対象なし（ID: $alarmId）")
                return false
            }

            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            Log.d("MainActivity", "✅ AlarmManager キャンセル完了（ID: $alarmId）")
            return true
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ cancelAlarmWithAlarmManager エラー: ${e.message}")
            return null
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
        Log.d("MainActivity", "🔴 stopAlarm 呼び出し")

        // 🆕 companion object の変数に直接アクセス
        AlarmReceiver.isAlarmPlaying = false
        AlarmReceiver.mediaPlayer?.stop()
        AlarmReceiver.mediaPlayer?.release()
        AlarmReceiver.mediaPlayer = null
        AlarmReceiver.alarmHandler?.removeCallbacksAndMessages(null)
        AlarmReceiver.alarmHandler = null

        Log.d("MainActivity", "✅ アラーム停止完了")
        } catch (e: Exception) {
        Log.e("MainActivity", "❌ アラーム停止エラー: ${e.message}")
        }
    }
}