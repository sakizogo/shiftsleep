// プレミアムの 🔒 を押したときのダイアログ（A-3 2/3）
//
// 改善アドバイスの詳細（AdviceDetailScreen）と、ホームの睡眠プランのカードから使う
// - 鍵のアイコン・（あれば）説明・プレミアムの案内の文
// - ［閉じる］［プレミアム版に登録］
// - N138＋N139 4b：［プレミアム版に登録］はダイアログを閉じてから購入画面（4a）を開く（D30 A）
//   - 閉じる前に NavigatorState と ScaffoldMessengerState を取っておき、閉じたダイアログの context は使わない
//   - configure していないときは開かず「ℹ️ 準備中です」を青で出す（設定画面と同じ。D31 A・D32 A）
//   - 1 つのダイアログで 2 回目に押しても何もしない（購入画面が 2 枚開かない。D33 A）
//   - 購入・復元のあとの 🔒 の切り替えは、呼び出し元が SleepProvider を見て行う（ここでは何もしない）
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shiftsleep/screens/premium_purchase_screen.dart';
import 'package:shiftsleep/services/premium_service.dart';

/// configure していないときの SnackBar の文（D32 A：設定画面・購入画面と同じ）
const String premiumComingSoonText = premiumNotReadyText;

/// 🔒 のダイアログを出す
/// - title：ダイアログの見出し
/// - description：鍵の下に出す説明（灰色の斜体。なければ出さない）
/// - message：プレミアムの案内の文
/// - isRevenueCatConfigured：configure しているかを確かめる関数（テストで差し替える。既定は PremiumService）
Future<void> showPremiumLockDialog(
  BuildContext context, {
  required String title,
  String? description,
  required String message,
  Future<bool> Function()? isRevenueCatConfigured,
}) {
  var opening = false;  // D33 A：このダイアログで［プレミアム版に登録］を押したか
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                children: [
                  const Icon(Icons.lock, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  if (description != null) ...[
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      border: Border.all(color: Colors.blue.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.star, color: Colors.blue),
                        const SizedBox(height: 8),
                        Text(
                          message,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('閉じる'),
          ),
          ElevatedButton(
            onPressed: () {
              if (opening) return;
              opening = true;
              unawaited(_openPurchaseScreen(
                dialogContext,
                isRevenueCatConfigured ?? PremiumService().isRevenueCatConfigured,
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            child: const Text('プレミアム版に登録', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    },
  );
}

/// N138＋N139 4b：ダイアログを閉じてから、購入画面を開く（configure していなければ「ℹ️ 準備中です」）
Future<void> _openPurchaseScreen(BuildContext dialogContext, Future<bool> Function() isConfigured) async {
  // 閉じる前に取っておく（どちらもアプリ全体のもので、ダイアログを閉じても残る）
  final navigator = Navigator.of(dialogContext);
  final messenger = ScaffoldMessenger.of(dialogContext);
  navigator.pop();

  final configured = await isConfigured();
  if (!configured) {
    debugPrint('[PremiumLockDialog] ℹ️ RevenueCat を configure していないので、購入画面を開きません');
    if (!messenger.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text(premiumComingSoonText), backgroundColor: Colors.blue),
    );
    return;
  }
  if (!navigator.mounted) return;
  await navigator.push(MaterialPageRoute<void>(builder: (_) => const PremiumPurchaseScreen()));
}
