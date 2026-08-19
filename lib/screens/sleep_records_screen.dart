import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/text_styles.dart';
import '../models/sleep_record.dart';
import '../repositories/sleep_repository.dart';

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

          // ✅ Phase 5 Step 1: 0h 0m のレコードをフィルタ
          final allRecords = snapshot.data ?? [];
          final records = allRecords
              .where((record) => record.durationMinutes >= 1)
              .toList();

          if (records.isEmpty) {
            return Center(
              child: Text(
                '睡眠記録がまだありません\n「今から寝る」ボタンで記録を開始してください',
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
              final duration = record.durationMinutes;
              final hours = duration ~/ 60;
              final minutes = duration % 60;

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
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ Phase 5 Step 2: × ボタン追加
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${record.sleepDate.year}年${record.sleepDate.month}月${record.sleepDate.day}日',
                            style: AppTextStyles.sectionTitleStyle,
                          ),
                          Row(
                            children: [
                              Text(
                                '${hours}h ${minutes}m',
                                style: AppTextStyles.statNumberStyle.copyWith(
                                  color: AppColors.warningRed,
                                ),
                              ),
                              // × ボタン
                              IconButton(
                                icon: const Icon(Icons.close),
                                iconSize: 20.0,
                                color: AppColors.warningRed,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
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
                      const SizedBox(height: 8.0),
                      Text(
                        '起床タイプ: ${record.wakeUpType}',
                        style: AppTextStyles.labelStyle,
                      ),
                      Text(
                        '修正可能期限: ${_formatDateTime(record.canEditUntil)}',
                        style: AppTextStyles.labelStyle,
                      ),
                      if (record.modifiedCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            '修正回数: ${record.modifiedCount}',
                            style: AppTextStyles.labelStyle.copyWith(
                              color: AppColors.warningRed,
                            ),
                          ),
                        ),
                    ],
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

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}/${dateTime.month}/${dateTime.day} ${_formatTime(dateTime)}';
  }

  // ✅ Phase 5 Step 3: 削除確認ダイアログ
  void _showDeleteConfirmDialog(BuildContext context, String recordId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除確認'),
        content: const Text('この睡眠記録を削除してもいいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              // ✅ Phase 5 Step 4: 削除実行 + UI リフレッシュ
              try {
                await _sleepRepository.deleteSleepRecord(recordId);
                // 削除後、リストを再読み込み
                setState(() {
                  _recordsFuture = _sleepRepository.getSleepRecordsByUserId(widget.userId);
                });
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('睡眠記録を削除しました')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('削除に失敗しました: $e')),
                  );
                }
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