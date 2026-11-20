// N210：設定画面の「ℹ️ このアプリについて」（プライバシーポリシーへのリンク）
//
// 開く処理は UrlOpener で差し替えられる（テストではプラグインを呼ばない）
// 既定は外部のブラウザで開く（D6 A）。開けなかったときの例外の中身は debugPrint だけに出す
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:url_launcher/url_launcher.dart';

/// プライバシーポリシーの URL
const privacyPolicyUrl = 'https://sites.google.com/view/shiftsleep-privacy';

/// 欄の見出し
const aboutAppSectionTitle = 'ℹ️ このアプリについて';

/// 行の文言（読み上げにはこの 1 つを使う）
const privacyPolicyLabel = 'プライバシーポリシー';

/// 画面では、この区切りで折り返す。つなげると privacyPolicyLabel と同じ
/// 大きい文字（2.0 倍）で「ー」だけが次の行に落ちないようにするため（P1 と同じやり方）
const privacyPolicyLabelParts = ['プライバシー', 'ポリシー'];

/// 外部リンクのアイコンの読み上げ
const externalLinkSemanticLabel = '外部のブラウザで開きます';

/// 開けなかったときの知らせ（D21 B：URL を出す）
const privacyPolicyOpenFailedText = '⚠️ プライバシーポリシーを開けませんでした。ブラウザで $privacyPolicyUrl を開いてください';

/// 開けなかったときの SnackBar の［コピー］
const copyUrlActionLabel = 'コピー';

/// ［コピー］のあとの知らせ
const urlCopiedText = '✅ URL をコピーしました';

/// 開く関数（テストで差し替える）。開けたら true
typedef UrlOpener = Future<bool> Function(Uri uri);

/// 既定：外部のブラウザで開く
Future<bool> openInExternalBrowser(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// プライバシーポリシーを開く。開けなかった・例外のときは false（例外は外に出さない）
Future<bool> openPrivacyPolicy({UrlOpener open = openInExternalBrowser}) async {
  try {
    return await open(Uri.parse(privacyPolicyUrl));
  } catch (e) {
    debugPrint('⚠️ N210: プライバシーポリシーを開けませんでした: $e');
    return false;
  }
}
