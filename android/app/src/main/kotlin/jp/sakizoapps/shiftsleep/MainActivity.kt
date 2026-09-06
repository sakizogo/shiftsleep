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
        // MethodChannel の名前（Dart 側と一致させる必須）
        private const val CHANNEL = "com.sakizoapps.shiftsleep/alarm"
        
        // ★ AlarmManager が使用するアクション（これだけ1つ残す）
        private const val ALARM_ACTION = "jp.sakizoapps.shiftsleep.ALARM_ACTION"
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
                        val selectedAlarmSound = call.argument<String>("selectedAlarmSound") ?: "default"

                        if (timestampMs != null && alarmId != null && title != null && body != null) {
                            scheduleAlarmWithAlarmManager(
                                timestampMs = timestampMs,
                                alarmId = alarmId,
                                title = title,
                                body = body,
                                selectedAlarmSound = selectedAlarmSound
                            )
                            result.success("✅ AlarmManager でスケジュール完了")
                        } else {
                            result.error("INVALID_ARGS", "必要なパラメータが不足しています", null)
                        }
                    }

                    "cancelAlarmWithAlarmManager" -> {
                        val alarmId = call.argument<Int>("alarmId")
                        if (alarmId != null) {
                            cancelAlarmWithAlarmManager(alarmId)
                            result.success("✅ AlarmManager のアラーム削除完了")
                        } else {
                            result.error("INVALID_ARGS", "alarmId が不足です", null)
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
     * @param alarmId - アラーム ID（ユニーク）
     * @param title - 通知タイトル
     * @param body - 通知本文
     * @param selectedAlarmSound - アラーム音の種類（'default', 'gentle', 'harsh'）
     */
    private fun scheduleAlarmWithAlarmManager(
        timestampMs: Long,
        alarmId: Int,
        title: String,
        body: String,
        selectedAlarmSound: String
    ) {
        try {
            // ★ Intent を作成・ALARM_ACTION を明示的に設定
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = ALARM_ACTION  // ★ ここが重要！
                putExtra("alarmId", alarmId)
                putExtra("title", title)
                putExtra("body", body)
                putExtra("selectedAlarmSound", selectedAlarmSound)
            }

            // PendingIntent を作成・FLAG_UPDATE_CURRENT で既存を更新
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId,  // requestCode = alarmId（ユニーク確保）
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            android.util.Log.d(
                "MainActivity",
                "🔍 PendingIntent 作成完了: alarmId=$alarmId, action=$ALARM_ACTION"
            )

            // AlarmManager.setAndAllowWhileIdle() でセット
            // （デバイススリープ中でも発火します）
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Android 12+ では scheduleExactAlarm 権限をチェック
                if (alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        timestampMs,
                        pendingIntent
                    )
                    android.util.Log.d(
                        "MainActivity",
                        "✅ setAndAllowWhileIdle 実行中（正確時刻）: $timestampMs"
                    )
                } else {
                    // 権限がない場合は setAndAllowWhileIdle（不正確モード）を使用
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        timestampMs,
                        pendingIntent
                    )
                    android.util.Log.w(
                        "MainActivity",
                        "⚠️ 正確なアラーム権限がありません。不正確モードで実行します"
                    )
                }
            } else {
                // Android 11 以下
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timestampMs,
                    pendingIntent
                )
                android.util.Log.d("MainActivity", "✅ setAndAllowWhileIdle 実行完了 $timestampMs")
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
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = ALARM_ACTION  // ★ ここも同じアクションを使用
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
            android.util.Log.d("MainActivity", "✅ AlarmManager キャンセル完了 $alarmId")
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ キャンセル エラー: ${e.message}", e)
        }
    }
}