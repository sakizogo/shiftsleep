// N191 3/3：設定画面の［アップグレード］でプレミアムの状態を確かめたあとの SnackBar
//
// 出し分けは SleepProvider の値（setPremiumStatus のあと。デバッグの上書きも含む）で決める（D15 B）
// 画面の欄の表示といつもそろえるため
import 'package:flutter/material.dart';

/// プレミアムのとき
const premiumCheckPremiumText = '✨ プレミアム版をご利用中です！';

/// 無料のとき
const premiumCheckFreeText = '無料版をご利用中です。プレミアム版でさらに多くの機能をご利用いただけます。';

/// 確かめたあとの SnackBar の文言と色
({String text, Color color}) premiumCheckMessage(bool isPremium) {
  if (isPremium) return (text: premiumCheckPremiumText, color: Colors.green);
  return (text: premiumCheckFreeText, color: Colors.blue);
}
