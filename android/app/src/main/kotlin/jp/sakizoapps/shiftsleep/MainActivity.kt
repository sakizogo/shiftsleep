package jp.sakizoapps.shiftsleep
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.NotificationManager
import android.content.Context
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
        // ✅ H2 Step 3: 予約の保存（登録と保存は AlarmScheduler に移動）
        return AlarmScheduler.schedule(this, timestampMs, alarmId, title, body, selectedAlarmSound)
    }

    // ✅ Step1-A: 戻り値 true=取消成功 / false=対象なし / null=例外
    private fun cancelAlarmWithAlarmManager(alarmId: Int): Boolean? {
        // ✅ H2 Step 3: 予約の保存（取消と保存分の削除は AlarmScheduler に移動）
        return AlarmScheduler.cancel(this, alarmId)
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

        // N6: 「起きる」で音を止めたら、残っているアラーム通知（alarm_channel）もすべて消す
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.activeNotifications
                ?.filter { it.notification.channelId == "alarm_channel" }
                ?.forEach { nm?.cancel(it.tag, it.id) }
        }

        Log.d("MainActivity", "✅ アラーム停止完了")
        } catch (e: Exception) {
        Log.e("MainActivity", "❌ アラーム停止エラー: ${e.message}")
        }
    }
}