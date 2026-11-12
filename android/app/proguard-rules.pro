# N179: リリース版の R8 のルール（Flutter の Gradle プラグインが、このファイルがあれば自動で読み込む）

# flutter_local_notifications：zonedSchedule の予約を Gson で保存・復元する
# （型の情報が消えると、再起動後に予約を読み直すときに落ちる）
-keepattributes Signature
-keepattributes *Annotation*
-keep class * extends com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep class com.dexterous.flutterlocalnotifications.** { *; }
