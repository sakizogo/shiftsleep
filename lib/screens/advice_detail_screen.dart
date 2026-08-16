import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/services/sleep_advisory_service.dart';

/// ========== Week 7 Phase 3 修正: actionTip を有料版限定に ==========
/// 
/// 差別化戦略：案②
/// - 無料版：アドバイスの詳細説明は見える
/// - 無料版：実行ヒント（actionTip）はロック表示
/// - 有料版：実行ヒントが完全に見える
///
/// 目的:
/// - すべてのアドバイスをリスト表示
/// - 無料版：最大1個、有料版：最大5個
/// - アドバイスをタップで詳細ポップアップ表示
/// - 有料版ロック表示（isPremiumOnly）+ actionTip ロック表示
/// 
/// デザイン:
/// - リスト形式（スクロール対応）
/// - 優先度バッジ（テキスト: 高・中・低）+ カテゴリアイコン
/// - タップでポップアップ内容表示
class AdviceDetailScreen extends StatefulWidget {
  const AdviceDetailScreen({Key? key}) : super(key: key);

  @override
  State<AdviceDetailScreen> createState() => _AdviceDetailScreenState();
}

class _AdviceDetailScreenState extends State<AdviceDetailScreen> {
  SleepAdvice? _selectedAdvice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('改善アドバイス'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Consumer<SleepProvider>(
        builder: (context, sleepProvider, child) {
          final advices = sleepProvider.displayedAdvice;

          // アドバイスがない場合
          if (advices.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 64,
                    color: Colors.green.shade300,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'アドバイスはありません',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'あと少し睡眠データを\n蓄積してください',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // アドバイスリスト表示
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: advices.length,
            itemBuilder: (context, index) {
              final advice = advices[index];
              return _AdviceCard(
                advice: advice,
                isPremiumUser: sleepProvider.isPremiumUser,
                onTap: () {
                  setState(() {
                    _selectedAdvice = advice;
                  });
                  _showAdviceDetailDialog(context, advice, sleepProvider.isPremiumUser, sleepProvider.advicePromoVisible);
                },
              );
            },
          );
        },
      ),
    );
  }

  /// 詳細ポップアップを表示
  void _showAdviceDetailDialog(
    BuildContext context,
    SleepAdvice advice,
    bool isPremiumUser,
    bool advicePromoVisible,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        // 有料版ロック表示（アドバイス自体が有料版限定の場合）
        final isAdviceLocked = advice.isPremiumOnly && !isPremiumUser && advicePromoVisible;
        
        // ========== Week 7 Phase 3 修正: actionTip のロック判定 ==========
        // actionTip は、有料版ユーザーか、無料版でも isPremiumOnly でない場合のみ表示
        final isActionTipLocked = advice.actionTip != null && !isPremiumUser;
        // ====================================================================

        return AlertDialog(
          title: Text(
            advice.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 説明文
                isAdviceLocked
                    ? Column(
                        children: [
                          const Icon(Icons.lock, size: 48, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            advice.description,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              border: Border.all(color: Colors.blue.shade200),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.star, color: Colors.blue),
                                SizedBox(height: 8),
                                Text(
                                  'プレミアム版に登録すると、\n詳細な改善アドバイスが\n すべて見られます',
                                  style: TextStyle(
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
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            advice.description,
                            style: const TextStyle(fontSize: 14, height: 1.6),
                          ),
                          
                          // ========== Week 7 Phase 3 修正: actionTip をロック化 ==========
                          if (advice.actionTip != null) ...[
                            const SizedBox(height: 16),
                            isActionTipLocked
                                ? Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      border: Border.all(color: Colors.amber.shade200),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '💡 実行ヒント（プレミアム版で解放）',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'プレミアム版ではここに「${advice.title}」を実行するための具体的な方法が表示されます。\n\n例：毎日のアラーム設定時刻、食事のタイミング、運動の頻度など、すぐに実行できるアクション情報が満載です。',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      border: Border.all(color: Colors.blue.shade200),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '💡 実行ヒント',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          advice.actionTip!,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                          ],
                          // ========================================================================
                        ],
                      ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
            if (isAdviceLocked)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('準備中です')),
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
}

/// ========== アドバイスカード ウィジェット ==========
class _AdviceCard extends StatelessWidget {
  final SleepAdvice advice;
  final bool isPremiumUser;
  final VoidCallback onTap;

  const _AdviceCard({
    required this.advice,
    required this.isPremiumUser,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 有料版ロック判定
    final isLocked = advice.isPremiumOnly && !isPremiumUser;

    // カテゴリ名を日本語に変換
    String categoryLabel() {
      switch (advice.category) {
        case 'sjl':
          return '体内時計のズレ（SJL）';
        case 'sri':
          return '睡眠の規則性（SRI）';
        case 'debt':
          return '睡眠負債（DEBT）';
        default:
          return 'その他';
      }
    }

    // カテゴリアイコンを取得
    IconData categoryIcon() {
      switch (advice.category) {
        case 'sjl':
          return Icons.schedule;
        case 'sri':
          return Icons.bedtime;
        case 'debt':
          return Icons.energy_savings_leaf;
        default:
          return Icons.info;
      }
    }

    // 優先度の色（赤緑色盲対応）
    Color priorityColor() {
      switch (advice.priority) {
        case 1:
          return Colors.red.shade600;
        case 2:
          return Colors.orange.shade600;
        case 3:
          return Colors.green.shade600;
        default:
          return Colors.grey;
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isLocked ? Colors.grey.shade300 : priorityColor(),
              width: 3,
            ),
            borderRadius: BorderRadius.circular(8),
            color: isLocked ? Colors.grey.shade50 : Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ヘッダー: 優先度 + カテゴリ
                Row(
                  children: [
                    // 優先度 + カテゴリ名バッジ
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: priorityColor().withOpacity(0.1),
                        border: Border.all(color: priorityColor()),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            categoryIcon(),
                            size: 16,
                            color: priorityColor(),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '【重要】${categoryLabel()}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: priorityColor(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Spacer(),

                    // ロック表示
                    if (isLocked)
                      const Icon(
                        Icons.lock,
                        size: 20,
                        color: Colors.grey,
                      ),

                    // タップアイコン
                    if (!isLocked)
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey,
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // タイトル
                Text(
                  advice.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // 説明（最初の1～2行のみ）
                Text(
                  _truncateText(advice.description, 2),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// テキストを指定行数で切り詰める
  String _truncateText(String text, int maxLines) {
    final lines = text.split('\n');
    if (lines.length <= maxLines) return text;
    return '${lines.sublist(0, maxLines).join('\n')}...';
  }
}