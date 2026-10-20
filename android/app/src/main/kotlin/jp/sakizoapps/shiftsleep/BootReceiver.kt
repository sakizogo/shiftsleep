package jp.sakizoapps.shiftsleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

// ✅ H2 Step 4: 再起動後のアラーム復元
// 端末の再起動・アプリ更新後に、保存済みのネイティブアラーム（ALARM_ACTION）を登録し直す
class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"

        // ✅ H2 Step 4: 再起動後のアラーム復元（受け取る action）
        private val BOOT_ACTIONS = setOf(
            "android.intent.action.BOOT_COMPLETED",
            "android.intent.action.MY_PACKAGE_REPLACED",
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON"
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action !in BOOT_ACTIONS) return

        try {
            Log.d(TAG, "🔄 アラーム復元開始（action: $action）")

            var restored = 0
            var removed = 0
            var failed = 0
            val now = System.currentTimeMillis()

            for (alarm in AlarmScheduler.loadAll(context)) {
                if (alarm.timestampMs > now) {
                    // 未来の予約：登録し直す
                    val errorCode = AlarmScheduler.schedule(
                        context,
                        alarm.timestampMs,
                        alarm.alarmId,
                        alarm.title,
                        alarm.body,
                        alarm.selectedAlarmSound
                    )
                    if (errorCode == null) {
                        restored++
                        Log.d(TAG, "✅ 復元成功（ID: ${alarm.alarmId}, 時刻: ${alarm.timestampMs}）")
                    } else {
                        failed++
                        Log.w(TAG, "❌ 復元失敗（ID: ${alarm.alarmId}, 時刻: ${alarm.timestampMs}, エラー: $errorCode）")
                    }
                } else {
                    // 過去の予約：登録せずに削除
                    AlarmScheduler.remove(context, alarm.alarmId)
                    removed++
                    Log.d(TAG, "🗑️ 過去時刻のため削除（ID: ${alarm.alarmId}, 時刻: ${alarm.timestampMs}, now=$now）")
                }
            }

            Log.d(TAG, "🔄 アラーム復元完了：復元 $restored 件 / 削除 $removed 件 / 失敗 $failed 件")
        } catch (e: Exception) {
            Log.e(TAG, "❌ アラーム復元エラー: ${e.message}")
        }
    }
}
