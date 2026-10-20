package jp.sakizoapps.shiftsleep

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONObject

// ✅ H2 Step 3: 予約の保存
// AlarmManager への登録・取消と、再起動後の再登録に使う予約内容の保存を行う
object AlarmScheduler {
    // ✅ H2 Step 3: 予約の保存（保存先とキー）
    private const val PREFS_NAME = "shiftsleep_native_alarms"
    private const val KEY_PREFIX = "alarm_"

    // ✅ H2 Step 3: 予約の保存（保存する予約内容）
    data class SavedAlarm(
        val timestampMs: Long,
        val alarmId: Int,
        val title: String,
        val body: String,
        val selectedAlarmSound: String
    )

    // ✅ Step2-1: 戻り値 null=登録成功 / "EXACT_ALARM_DENIED"=権限なし / "SCHEDULE_FAILED"=その他の失敗
    fun schedule(
        context: Context,
        timestampMs: Long,
        alarmId: Int,
        title: String,
        body: String,
        selectedAlarmSound: String
    ): String? {
        try {
            Log.d("MainActivity", "🔔 scheduleAlarmWithAlarmManager: id=$alarmId, time=$timestampMs, sound=$selectedAlarmSound")

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // ✅ Step2-1: Android 12 以降は登録前に正確なアラームの権限を確認（権限なしなら登録しない）
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                Log.w("MainActivity", "⛔ 正確なアラームの権限がないため登録しません（ID: $alarmId）")
                return "EXACT_ALARM_DENIED"
            }
            val intent = Intent(context, AlarmReceiver::class.java).apply {
                action = "jp.sakizoapps.shiftsleep.ALARM_ACTION"
                putExtra("alarmId", alarmId.toString())
                putExtra("label", title)
                putExtra("selectedAlarmSound", selectedAlarmSound)
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context, alarmId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                timestampMs,
                pendingIntent
            )

            Log.d("MainActivity", "✅ setExactAndAllowWhileIdle 完了（ID: $alarmId, 時刻: $timestampMs）")
            // ✅ H2 Step 3: 予約の保存（登録に成功したときだけ保存）
            save(context, SavedAlarm(timestampMs, alarmId, title, body, selectedAlarmSound))
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
    fun cancel(context: Context, alarmId: Int): Boolean? {
        try {
            Log.d("MainActivity", "🔴 cancelAlarmWithAlarmManager: id=$alarmId")

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // ✅ Step1-A: 登録時と同じ action を付けて同一の PendingIntent に一致させる
            val intent = Intent(context, AlarmReceiver::class.java).apply {
                action = "jp.sakizoapps.shiftsleep.ALARM_ACTION"
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context, alarmId, intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )

            // ✅ Step1-A: 既存の PendingIntent がなければ「対象なし」（正常）
            if (pendingIntent == null) {
                Log.d("MainActivity", "ℹ️ キャンセル対象なし（ID: $alarmId）")
                // ✅ H2 Step 3: 予約の保存（対象なしでも保存分は削除）
                remove(context, alarmId)
                return false
            }

            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            Log.d("MainActivity", "✅ AlarmManager キャンセル完了（ID: $alarmId）")
            // ✅ H2 Step 3: 予約の保存（取消に成功したら保存分を削除）
            remove(context, alarmId)
            return true
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ cancelAlarmWithAlarmManager エラー: ${e.message}")
            return null
        }
    }

    // ✅ H2 Step 3: 予約の保存（保存済みの予約をすべて読み出す。Step 4 で使用）
    fun loadAll(context: Context): List<SavedAlarm> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val alarms = mutableListOf<SavedAlarm>()
        for ((key, value) in prefs.all) {
            if (!key.startsWith(KEY_PREFIX) || value !is String) continue
            try {
                val json = JSONObject(value)
                alarms.add(
                    SavedAlarm(
                        timestampMs = json.getLong("timestampMs"),
                        alarmId = json.getInt("alarmId"),
                        title = json.getString("title"),
                        body = json.getString("body"),
                        selectedAlarmSound = json.getString("selectedAlarmSound")
                    )
                )
            } catch (e: Exception) {
                Log.e("AlarmScheduler", "❌ 保存済みアラームの読み出しエラー（$key）: ${e.message}")
            }
        }
        return alarms
    }

    // ✅ H2 Step 3: 予約の保存（保存済みの予約を1件削除。Step 4 でも使用）
    fun remove(context: Context, alarmId: Int) {
        try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY_PREFIX + alarmId)
                .apply()
        } catch (e: Exception) {
            Log.e("AlarmScheduler", "❌ 保存済みアラームの削除エラー（ID: $alarmId）: ${e.message}")
        }
    }

    // ✅ H2 Step 3: 予約の保存（同じ alarmId は上書き。保存に失敗しても登録結果は変えない）
    private fun save(context: Context, alarm: SavedAlarm) {
        try {
            val json = JSONObject().apply {
                put("timestampMs", alarm.timestampMs)
                put("alarmId", alarm.alarmId)
                put("title", alarm.title)
                put("body", alarm.body)
                put("selectedAlarmSound", alarm.selectedAlarmSound)
            }
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_PREFIX + alarm.alarmId, json.toString())
                .apply()
        } catch (e: Exception) {
            Log.e("AlarmScheduler", "❌ アラームの保存エラー（ID: ${alarm.alarmId}）: ${e.message}")
        }
    }
}
