// プレミアムの 🔒 を押したときのダイアログ（A-3 2/3）
//
// 改善アドバイスの詳細（AdviceDetailScreen）と、ホームの睡眠プランのカードから使う
// - 鍵のアイコン・（あれば）説明・プレミアムの案内の文
// - ［閉じる］［プレミアム版に登録］。［プレミアム版に登録］はダイアログを閉じて「準備中です」の SnackBar
import 'package:flutter/material.dart';

/// ［プレミアム版に登録］を押したときの SnackBar の文
const String premiumComingSoonText = '準備中です';

/// 🔒 のダイアログを出す
/// - title：ダイアログの見出し
/// - description：鍵の下に出す説明（灰色の斜体。なければ出さない）
/// - message：プレミアムの案内の文
Future<void> showPremiumLockDialog(
  BuildContext context, {
  required String title,
  String? description,
  required String message,
}) {
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
              final messenger = ScaffoldMessenger.of(dialogContext);
              Navigator.of(dialogContext).pop();
              messenger.showSnackBar(
                const SnackBar(content: Text(premiumComingSoonText)),
              );
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
