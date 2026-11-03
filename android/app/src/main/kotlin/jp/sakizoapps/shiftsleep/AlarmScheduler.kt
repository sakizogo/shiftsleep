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
            Log.d("AlarmScheduler", "🔔 scheduleAlarmWithAlarmManager: id=$alarmId, time=$timestampMs, sound=$selectedAlarmSound")

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // ✅ Step2-1: Android 12 以降は登録前に正確なアラームの権限を確認（権限なしなら登録しない）
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                Log.w("AlarmScheduler", "⛔ 正確なアラームの権限がないため登録しません（ID: $alarmId）")
                return "EXACT_ALARM_DENIED"
            }
            val intent = Intent(context, AlarmReceiver::class.java).apply {
                action = "jp.sakizoapps.shiftsleep.ALARM_ACTION"
                putExtra("alarmId", alarmId.toString())
                putExtra("label", title)
                putExtra("body", body)
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

            Log.d("AlarmScheduler", "✅ setExactAndAllowWhileIdle 完了（ID: $alarmId, 時刻: $timestampMs）")
            // ✅ H2 Step 3: 予約の保存（登録に成功したときだけ保存）
            save(context, SavedAlarm(timestampMs, alarmId, title, body, selectedAlarmSound))
            return null
        } catch (e: SecurityException) {
            // ✅ Step2-1: 権限不足による失敗を識別して返す
            Log.e("AlarmScheduler", "❌ 正確なアラームの権限エラー: ${e.message}")
            return "EXACT_ALARM_DENIED"
        } catch (e: Exception) {
            Log.e("AlarmScheduler", "❌ scheduleAlarmWithAlarmManager エラー: ${e.message}")
            return "SCHEDULE_FAILED"
        }
    }

    // ✅ Step1-A: 戻り値 true=取消成功 / false=対象なし / null=例外
    fun cancel(context: Context, alarmId: Int): Boolean? {
        try {
            Log.d("AlarmScheduler", "🔴 cancelAlarmWithAlarmManager: id=$alarmId")

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
                Log.d("AlarmScheduler", "ℹ️ キャンセル対象なし（ID: $alarmId）")
                // ✅ H2 Step 3: 予約の保存（対象なしでも保存分は削除）
                remove(context, alarmId)
                return false
            }

            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            Log.d("AlarmScheduler", "✅ AlarmManager キャンセル完了（ID: $alarmId）")
            // ✅ H2 Step 3: 予約の保存（取消に成功したら保存分を削除）
            remove(context, alarmId)
            return true
        } catch (e: Exception) {
            Log.e("AlarmScheduler", "❌ cancelAlarmWithAlarmManager エラー: ${e.message}")
            return null
        }
    }

    // N126: 控えから登録し直す（BootReceiver と、アプリを開いたときの MethodChannel から呼ぶ）
    // 未来の予約は登録し直し、過去の予約は控えから消す。アラームが OFF なら何もしない（控えにも触らない）
    // 戻り値：restored（復元）・removed（過去なので削除）・denied（権限なし）・failed（その他の失敗）・off（OFF なら 1）
    fun restoreAll(context: Context): Map<String, Int> {
        // shared_preferences の従来型 API の保存形式に依存（AlarmReceiver の flutter.alarm_stopped_at_ms と同じ）
        val alarmEnabled = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean("flutter.is_alarm_enabled", true)
        if (!alarmEnabled) {
            Log.d("AlarmScheduler", "🔕 アラームOFFのため控えから登録し直しません")
            return mapOf("restored" to 0, "removed" to 0, "denied" to 0, "failed" to 0, "off" to 1)
        }

        var restored = 0
        var removed = 0
        var denied = 0
        var failed = 0
        val now = System.currentTimeMillis()

        for (alarm in loadAll(context)) {
            if (alarm.timestampMs > now) {
                // 未来の予約：登録し直す（同じ alarmId は上書きになる）
                val errorCode = schedule(
                    context,
                    alarm.timestampMs,
                    alarm.alarmId,
                    alarm.title,
                    alarm.body,
                    alarm.selectedAlarmSound
                )
                when (errorCode) {
                    null -> {
                        restored++
                        Log.d("AlarmScheduler", "✅ 復元成功（ID: ${alarm.alarmId}, 時刻: ${alarm.timestampMs}）")
                    }
                    "EXACT_ALARM_DENIED" -> {
                        denied++
                        Log.w("AlarmScheduler", "⛔ 権限がないため復元できません（ID: ${alarm.alarmId}, 時刻: ${alarm.timestampMs}）")
                    }
                    else -> {
                        failed++
                        Log.w("AlarmScheduler", "❌ 復元失敗（ID: ${alarm.alarmId}, 時刻: ${alarm.timestampMs}, エラー: $errorCode）")
                    }
                }
            } else {
                // 過去の予約：登録せずに削除
                remove(context, alarm.alarmId)
                removed++
                Log.d("AlarmScheduler", "🗑️ 過去時刻のため削除（ID: ${alarm.alarmId}, 時刻: ${alarm.timestampMs}, now=$now）")
            }
        }

        Log.d("AlarmScheduler", "🔄 控えから登録し直し：復元 $restored 件 / 削除 $removed 件 / 権限なし $denied 件 / 失敗 $failed 件")
        return mapOf("restored" to restored, "removed" to removed, "denied" to denied, "failed" to failed, "off" to 0)
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
