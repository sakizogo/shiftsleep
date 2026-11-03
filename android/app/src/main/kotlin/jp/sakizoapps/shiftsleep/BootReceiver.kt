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
            "com.htc.intent.action.QUICKBOOT_POWERON",
            // N126: 「アラームとリマインダー」の許可を外して戻したときにも復元する
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action !in BOOT_ACTIONS) return

        try {
            Log.d(TAG, "🔄 アラーム復元開始（action: $action）")
            // N126: 控えから登録し直す処理は AlarmScheduler.restoreAll にまとめた
            val counts = AlarmScheduler.restoreAll(context)
            Log.d(TAG, "🔄 アラーム復元完了：$counts")
        } catch (e: Exception) {
            Log.e(TAG, "❌ アラーム復元エラー: ${e.message}")
        }
    }
}
