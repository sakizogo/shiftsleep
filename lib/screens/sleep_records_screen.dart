import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/colors.dart';
import '../constants/text_styles.dart';
import '../models/sleep_record.dart';
import '../providers/sleep_provider.dart';
import '../repositories/sleep_repository.dart';
import '../services/sleep_record_kind.dart';  // N199：formatSleepDuration
import '../widgets/sleep_duration_rating_badge.dart';  // N110
import 'edit_sleep_record_screen.dart';

class SleepRecordsScreen extends StatefulWidget {
  final String userId;

  const SleepRecordsScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<SleepRecordsScreen> createState() => _SleepRecordsScreenState();
}

class _SleepRecordsScreenState extends State<SleepRecordsScreen> {
  final SleepRepository _sleepRepository = SleepRepository();
  late Future<List<SleepRecord>> _recordsFuture;

  @override
  void initState() {
    super.initState();
    _recordsFuture = _sleepRepository.getSleepRecordsByUserId(widget.userId);
  }

  /// N108：一覧を DB から読み直す
  void _reloadRecords() {
    setState(() {
      _recordsFuture = _sleepRepository.getSleepRecordsByUserId(widget.userId);
    });
  }

  /// N108：追加（record == null）・修正の画面を開く。戻ったら保存したかどうかにかかわらず読み直す
  Future<void> _openEditScreen({SleepRecord? record}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSleepRecordScreen(record: record),
      ),
    );
    if (!mounted) return;
    _reloadRecords();
  }

  /// N108：睡眠中の進行中の記録か（todaysSplitSleepDuration・occupiedRange と同じ判定）
  bool _isSleepingRecord(SleepRecord record, SleepProvider provider) {
    if (!provider.isSleepingNow) return false;
    final sleepStartTime = provider.sleepStartTime;
    return record.id == provider.currentSleepRecordIdNow ||
        (sleepStartTime != null &&
            record.sleepStartTime.millisecondsSinceEpoch ==
                sleepStartTime.millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '睡眠記録',
          style: AppTextStyles.headerStyle,
        ),
        // N108：押し忘れた睡眠を追加（入眠日の初期値は今日）
        actions: [
          TextButton.icon(
            onPressed: () => _openEditScreen(),
            icon: const Icon(Icons.add),
            label: const Text('追加'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryGradientStart,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: AppColors.borderDefault,
            height: 1.0,
          ),
        ),
      ),
      body: FutureBuilder<List<SleepRecord>>(
        future: _recordsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'エラーが発生しました: ${snapshot.error}',
                style: AppTextStyles.bodyTextStyle,
              ),
            );
          }

          // N108：0 分の記録も出して ✕ で消せるようにする。睡眠中の進行中の記録だけは出さない
          final allRecords = snapshot.data ?? [];
          final sleepProvider = context.read<SleepProvider>();
          final records = allRecords
              .where((record) => !_isSleepingRecord(record, sleepProvider))
              .toList();

          if (records.isEmpty) {
            return Center(
              child: Text(
                '睡眠記録がまだありません\n「今から寝る」で記録するか、「＋ 追加」から追加してください',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyTextStyle,
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              final duration = Duration(minutes: record.durationMinutes);
              final rating = sleepDurationRating(duration);  // N110：時間の色と札
              final ratingLabel = rating.listLabel;
              final wakeUpLabel = wakeUpTypeLabel(record.wakeUpType);  // N112

              return Card(
                margin: const EdgeInsets.only(bottom: 12.0),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  side: BorderSide(
                    color: AppColors.borderDefault,
                    width: 1.0,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                // N108：カードをタップで修正を開く（31 日以上前の記録も開ける）
                child: InkWell(
                  onTap: () => _openEditScreen(record: record),
                  child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ Phase 5 Step 2: × ボタン追加
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // N108：幅が足りないときは日付を「…」で縮める（睡眠時間は縮めない）
                          Expanded(
                            child: Text(
                              formatSleepRecordListDate(record.sleepDate, DateTime.now()),  // 今年は年を省く（札が出ても日にちが見えるように）
                              style: AppTextStyles.sectionTitleStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Row(
                            children: [
                              // N110：不足・長すぎのときだけ札（補助・良好は札なし）
                              if (ratingLabel != null) ...[
                                SleepDurationRatingBadge(rating: rating, label: ratingLabel),
                                const SizedBox(width: 6.0),
                              ],
                              Text(
                                formatSleepDuration(duration),  // N199
                                style: AppTextStyles.statNumberStyle.copyWith(
                                  color: sleepDurationRatingColor(rating),  // N110
                                ),
                              ),
                              // N108：✏️ 修正ボタン（compact でタップの範囲は 40×40）
                              IconButton(
                                icon: const Icon(Icons.edit),
                                iconSize: 20.0,
                                color: AppColors.primaryGradientStart,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                tooltip: '修正',
                                onPressed: () => _openEditScreen(record: record),
                              ),
                              // × ボタン
                              IconButton(
                                icon: const Icon(Icons.close),
                                iconSize: 20.0,
                                color: AppColors.warningRed,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  _showDeleteConfirmDialog(context, record.id);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12.0),
                      Text(
                        '入眠: ${_formatTime(record.sleepStartTime)}',
                        style: AppTextStyles.bodyTextStyle,
                      ),
                      Text(
                        '起床: ${_formatTime(record.sleepEndTime)}',
                        style: AppTextStyles.bodyTextStyle,
                      ),
                      // N112：表示名がないとき（空など）は行を出さない
                      if (wakeUpLabel != null) ...[
                        const SizedBox(height: 8.0),
                        Text(
                          '起床タイプ: $wakeUpLabel',
                          style: AppTextStyles.labelStyle,
                        ),
                      ],
                      if (record.modifiedCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            '修正回数: ${record.modifiedCount}',
                            style: AppTextStyles.labelStyle.copyWith(
                              color: AppColors.textSecondary,  // 注意の印ではないので、ほかの補足と同じ灰色
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  // ✅ Phase 5 Step 3: 削除確認ダイアログ
  void _showDeleteConfirmDialog(BuildContext context, String recordId) {
    showDialog(
      context: context,
      // N108：外の context を上書きしないよう、ダイアログの context は dialogContext にする
      builder: (dialogContext) => AlertDialog(
        title: const Text('削除確認'),
        content: const Text('この睡眠記録を削除してもいいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              // N108：Provider 経由で削除し、ホーム（今日の合計・統計）も読み直す
              final messenger = ScaffoldMessenger.of(context);
              final provider = context.read<SleepProvider>();
              Navigator.pop(dialogContext);
              try {
                await provider.deleteSleepRecord(recordId);
                if (!mounted) return;
                _reloadRecords();
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  const SnackBar(content: Text('✅ 睡眠記録を削除しました')),
                );
              } catch (e) {
                if (!mounted) return;
                _reloadRecords();
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  SnackBar(content: Text('❌ 削除に失敗しました: $e')),
                );
              }
            },
            child: const Text(
              '削除',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}