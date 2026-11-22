// N138＋N139 5a：RevenueCat の API キーを選ぶ（どちらもアプリに埋め込む前提の公開キー）
// - デバッグ版：Test Store のキー（test_）。release で使うと SDK がアプリを閉じるので、デバッグ版だけで使う（N26）
// - デバッグ版以外（release・profile）：Google Play 用のキー（goog_）
// - main.dart は revenueCatApiKeyFor(debug: kDebugMode) で選ぶ。キーが空なら configure しない（N26）

/// Test Store のキー（デバッグ版だけで使う）
const String revenueCatTestApiKey = 'test_UbjWenDYUzXCqxFqxQpEWCJcZpH';

/// Google Play 用のキー（Public API Key。release・profile で使う）
const String revenueCatProductionApiKey = 'goog_hVoQQepDZxiVfuHcYVHmJzUJdxZ';

/// debug なら Test Store のキー、そうでなければ Google Play 用のキー
String revenueCatApiKeyFor({required bool debug}) =>
    debug ? revenueCatTestApiKey : revenueCatProductionApiKey;
