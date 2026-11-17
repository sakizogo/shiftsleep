import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shiftsleep/constants/colors.dart';  // N189
import 'package:shiftsleep/constants/text_styles.dart';  // N189
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/services/sleep_advisory_service.dart';
import 'package:shiftsleep/widgets/premium_lock_dialog.dart';  // A-3 2/3

/// 有料版限定のアドバイスの 🔒 の案内の文
const String adviceLockedMessage = 'プレミアム版に登録すると、\n詳細な改善アドバイスが\n すべて見られます';

/// N189：優先度の色（白地とのコントラスト：高 red.shade700 約 5.0:1・中 deepOrange.shade900 約 5.6:1・低 green.shade800 約 5.1:1）
/// 赤と緑は protanopia で見分けにくいので、札には advicePriorityLabel の文字も出す
Color advicePriorityColor(int priority) {
  switch (priority) {
    case 1:
      return Colors.red.shade700;
    case 2:
      return Colors.deepOrange.shade900;
    case 3:
      return Colors.green.shade800;
    default:
      return Colors.grey.shade700;
  }
}

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

          // N203：出すアドバイスがない場合は、ホームと同じ分け方の 1 行（記録不足／大きな改善点なし）
          final emptyMessage = SleepAdvisoryService.emptyAdviceMessage(
            all: sleepProvider.allAdvice,
            displayed: advices,
          );
          if (emptyMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      sleepProvider.allAdvice.isEmpty ? Icons.hourglass_empty : Icons.check_circle,
                      size: 64,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      emptyMessage,
                      style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
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
    // 有料版ロック表示（アドバイス自体が有料版限定の場合）。A-3 2/3：ダイアログはカードと共通の関数
    final isAdviceLocked = advice.isPremiumOnly && !isPremiumUser && advicePromoVisible;
    if (isAdviceLocked) {
      showPremiumLockDialog(
        context,
        title: advice.title,
        description: advice.description,
        message: adviceLockedMessage,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        
        // N186：actionTip の出し方はホームと共通（無料は 🔒 の案内だけ。案内が OFF なら出さない）
        final tipView = actionTipView(
          advice,
          isPremium: isPremiumUser,
          promoVisible: advicePromoVisible,
        );

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
                // 説明文（ロックのときは showPremiumLockDialog）
                Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            advice.description,
                            style: const TextStyle(fontSize: 14, height: 1.6),
                          ),
                          
                          // ========== Week 7 Phase 3 修正: actionTip をロック化 ==========
                          if (tipView != ActionTipView.hidden) ...[
                            const SizedBox(height: 16),
                            tipView == ActionTipView.locked
                                // N189：ホームの鍵の表示と同じ形（白地・鍵と文字は textSecondary）。ダイアログも白地なので細い枠で囲む
                                ? Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(color: AppColors.borderDefault),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // N186：ホームと同じく 🔒 のアイコン＋文言
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.lock,
                                              size: 16,
                                              color: AppColors.textSecondary,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                actionTipLockedLabel,
                                                style: AppTextStyles.descriptionStyle.copyWith(
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'プレミアム版では、このアドバイスを毎日の睡眠に生かすための短いヒントが表示されます。',  // N207：実際の実行ヒント（寝る時刻・仮眠など）に合わせ、言いすぎない
                                          style: AppTextStyles.noteStyle,
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

    // 優先度の色（N189：白地で 4.5:1 以上。色だけに頼らず札に「優先度 高／中／低」の文字も出す）
    Color priorityColor() => advicePriorityColor(advice.priority);

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
                    // 優先度 + カテゴリ名バッジ（N189：右の矢印・鍵のぶんを残して左に寄せる）
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          // N189：札の地は白。色は枠と文字だけに使う
                          decoration: BoxDecoration(
                            color: Colors.white,
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
                              // N189：いつも「【重要】」だったのを、優先度に合わせた文字に
                              // 大きい文字では札の中で折り返す
                              Flexible(
                                child: Text(
                                  '${advicePriorityLabel(advice.priority)}・${categoryLabel()}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: priorityColor(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

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