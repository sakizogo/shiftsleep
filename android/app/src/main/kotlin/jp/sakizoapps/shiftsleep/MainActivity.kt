package jp.sakizoapps.shiftsleep

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        // MethodChannel の名前（Dart 側と一致させる必要があります）
        private const val CHANNEL = "com.sakizoapps.shiftsleep/alarm"
    }

    private val alarmManager: AlarmManager by lazy {
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // MethodChannel のセットアップ
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleAlarmWithAlarmManager" -> {
                        // Dart から呼ばれるメソッド
                        val timestampMs = call.argument<Long>("timestampMs")
                        val alarmId = call.argument<Int>("alarmId")
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")

                        if (timestampMs != null && alarmId != null && title != null && body != null) {
                            scheduleAlarmWithAlarmManager(
                                timestampMs = timestampMs,
                                alarmId = alarmId,
                                title = title,
                                body = body
                            )
                            result.success("✅ AlarmManager でスケジュール完了")
                        } else {
                            result.error("INVALID_ARGS", "必須パラメータが不足しています", null)
                        }
                    }

                    "cancelAlarmWithAlarmManager" -> {
                        val alarmId = call.argument<Int>("alarmId")
                        if (alarmId != null) {
                            cancelAlarmWithAlarmManager(alarmId)
                            result.success("✅ AlarmManager のアラーム削除完了")
                        } else {
                            result.error("INVALID_ARGS", "alarmId が必須です", null)
                        }
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    /**
     * AlarmManager を使用してアラームをスケジュール
     * デバイススリープ中でも確実に発火します
     *
     * @param timestampMs - アラーム時刻（ミリ秒）
     * @param alarmId - アラーム ID（一意）
     * @param title - 通知タイトル
     * @param body - 通知本文
     */
    private fun scheduleAlarmWithAlarmManager(
        timestampMs: Long,
        alarmId: Int,
        title: String,
        body: String
    ) {
        try {
            // Intent を作成（AlarmReceiver にデータを渡す）
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                putExtra("alarmId", alarmId)
                putExtra("title", title)
                putExtra("body", body)
            }

            // PendingIntent を作成（FLAG_UPDATE_CURRENT で既存を上書き）
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId,  // requestCode = alarmId（一意性確保）
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // AlarmManager.setAndAllowWhileIdle() でセット
            // （デバイススリープ中でも実行される）
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Android 12+ では scheduleExactAlarm 権限チェックが必要
                if (alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        timestampMs,
                        pendingIntent
                    )
                    android.util.Log.d(
                        "MainActivity",
                        "✅ setAndAllowWhileIdle 実行（正確時刻）: $timestampMs"
                    )
                } else {
                    // 権限がない場合は setAndAllowWhileIdle（不正確）を使用
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        timestampMs,
                        pendingIntent
                    )
                    android.util.Log.w(
                        "MainActivity",
                        "⚠️ 正確なアラーム権限がありません。不正確モードで実行"
                    )
                }
            } else {
                // Android 11 以下
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timestampMs,
                    pendingIntent
                )
                android.util.Log.d("MainActivity", "✅ setAndAllowWhileIdle 実行: $timestampMs")
            }

        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ AlarmManager スケジュール エラー: ${e.message}", e)
        }
    }

    /**
     * AlarmManager のアラームをキャンセル
     */
    private fun cancelAlarmWithAlarmManager(alarmId: Int) {
        try {
            val intent = Intent(this, AlarmReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
            android.util.Log.d("MainActivity", "✅ AlarmManager キャンセル完了: $alarmId")
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ キャンセル エラー: ${e.message}", e)
        }
    }
}