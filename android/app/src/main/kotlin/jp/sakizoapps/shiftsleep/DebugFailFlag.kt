package jp.sakizoapps.shiftsleep

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log

// N141: 確かめる用に、アラームの経路をわざと失敗させるフラグ（debuggable なビルドのときだけ読む）
// adb shell setprop debug.shiftsleep.fail <値> で指定し、空にすると元に戻る
// 値：
// - start_fgs        … AlarmReceiver の startForegroundService（F1）→ 予備の経路へ
// - start_foreground … サービスの startForeground の直前（F3）→ 予備の経路へ
// - prepare          … サービスの 1 回目の音源の準備（F4）→ alarm_default で再挑戦
// - prepare_all      … サービスの音源の準備をすべて（F4）→ バイブだけ
// - service_hang     … サービスの onStartCommand の先頭で 12 秒眠る（F2）→ 落とされたあと見張りの予約で予備の経路へ
object DebugFailFlag {
  private const val TAG = "DebugFailFlag"
  private const val PROP_KEY = "debug.shiftsleep.fail"

  const val START_FGS = "start_fgs"
  const val START_FOREGROUND = "start_foreground"
  const val PREPARE = "prepare"
  const val PREPARE_ALL = "prepare_all"
  const val SERVICE_HANG = "service_hang"

  // 今のフラグの値。debuggable でない（リリース版）・読めないときは "" （フラグなし）
  fun read(context: Context): String {
    if ((context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) return ""
    return try {
      // android.os.SystemProperties は非公開 API なので反射で読む
      val value = Class.forName("android.os.SystemProperties")
        .getMethod("get", String::class.java)
        .invoke(null, PROP_KEY) as? String ?: ""
      if (value.isNotEmpty()) Log.w(TAG, "🧪 $PROP_KEY = $value（わざと失敗させます）")
      value
    } catch (e: Throwable) {
      // 非公開 API が使えない・反射に失敗したときも例外は外に出さず、フラグなしとして扱う
      Log.w(TAG, "⚠️ $PROP_KEY を読めませんでした（フラグなしとして扱います）: ${e.message}")
      ""
    }
  }

  fun shouldFail(context: Context, point: String): Boolean = read(context) == point
}
