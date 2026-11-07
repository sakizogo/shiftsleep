import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/sleep_preference_service.dart';

/// N142：⚠️ に日時を並べる上限（多いときは「ほか N 件」にする）
const _maxListedOrphans = 3;

/// N142：「今から寝る」の途中で終わり、記録だけ残ったものか
/// currentStartTimesMs・currentRecordIds：今の睡眠中の記録の開始時刻（ミリ秒）と ID
/// appStartedAt：今回の起動の時刻。以後に作られた記録は「今から寝る」と競合するので対象にしない
bool isOrphanSleepRecord(
  SleepRecord record, {
  required DateTime appStartedAt,
  required Set<int> currentStartTimesMs,
  required Set<String> currentRecordIds,
}) {
  final sleepDate = record.sleepDate;
  final nextDay7am = DateTime(sleepDate.year, sleepDate.month, sleepDate.day + 1, 7);
  return record.durationMinutes == 0 &&
      record.sleepStartAuto &&
      record.modifiedCount == 0 &&
      record.sleepEndTime.isAtSameMomentAs(nextDay7am) &&
      !currentStartTimesMs.contains(record.sleepStartTime.millisecondsSinceEpoch) &&
      !currentRecordIds.contains(record.id) &&
      record.createdAt.isBefore(appStartedAt);
}

/// N142：取り消した記録を 1 つの ⚠️ で知らせる文言（新しい順に並べる）
String orphanRecordsRemovedText(List<SleepRecord> removed) {
  const guide = '必要なら睡眠記録の「追加」で入れてください';
  String label(DateTime time) =>
      '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';

  if (removed.length == 1) {
    return '⚠️ ${label(removed.single.sleepStartTime)} の『今から寝る』が途中で終わっていたため取り消しました。$guide';
  }
  final times = removed.map((record) => record.sleepStartTime).toList()
    ..sort((a, b) => b.compareTo(a));
  final listed = times.take(_maxListedOrphans).map(label).join('、');
  final others = times.length - _maxListedOrphans;
  final suffix = others > 0 ? ' ほか $others 件' : '';
  return '⚠️ 『今から寝る』が途中で終わっていた ${times.length} 件（$listed$suffix）を取り消しました。$guide';
}

/// N142：起動時に、記録だけ残ったものを消す
class OrphanSleepRecordService {
  /// 消せた記録を返す（なければ空。知らせるのは呼び出し元）。例外は外に出さない
  /// 復元が終わる前と、SharedPreferences・DB を読めないときは何も消さない
  /// 消せなかった記録はログだけ（次の起動でまた試す）
  /// SharedPreferences を DB より先に読む（間に起床しても、読んだ DB の行は完了済みか、除外の対象になる）
  static Future<List<SleepRecord>> cleanUp({
    required SleepProvider provider,
    required SleepRepository repository,
    required DateTime appStartedAt,
  }) async {
    if (!provider.isSleepStateRestored) {
      debugPrint('[OrphanSleepRecord] ⏭️ 睡眠状態の復元前のため片付けません');
      return const [];
    }

    final List<SleepRecord> orphans;
    try {
      final saved = await SleepPreferenceService.readSleepStateOrThrow();
      final startTimes = {provider.sleepStartTime, saved.startTime}.whereType<DateTime>();
      final recordIds = {provider.currentSleepRecordIdNow, saved.recordId}.whereType<String>();
      final records = await repository.getSleepRecordsByUserId('test_user');
      orphans = records
          .where((record) => isOrphanSleepRecord(
                record,
                appStartedAt: appStartedAt,
                currentStartTimesMs: startTimes.map((time) => time.millisecondsSinceEpoch).toSet(),
                currentRecordIds: recordIds.toSet(),
              ))
          .toList();
    } catch (e) {
      debugPrint('[OrphanSleepRecord] ❌ 読み取りに失敗したため何も消しません: $e');
      return const [];
    }

    final removed = <SleepRecord>[];
    for (final record in orphans) {
      try {
        await repository.deleteSleepRecord(record.id);
        removed.add(record);
        debugPrint('[OrphanSleepRecord] 🗑️ 記録だけ残ったものを消しました: ${record.id}');
      } catch (e) {
        debugPrint('[OrphanSleepRecord] ❌ 消せませんでした（次の起動でまた試します）: ${record.id}: $e');
      }
    }

    if (removed.isNotEmpty) {
      try {
        await provider.loadAllSleepData();
      } catch (e) {
        // 消せたことは知らせる（読み直しは次の機会でよい）
        debugPrint('[OrphanSleepRecord] ⚠️ 片付けのあとの読み直しに失敗: $e');
      }
    }
    return removed;
  }
}
