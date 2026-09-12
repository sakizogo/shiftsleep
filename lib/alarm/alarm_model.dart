import 'package:uuid/uuid.dart';

/// シンプルなアラームモデル
class Alarm {
  final String id;
  final DateTime scheduledTime;  // アラーム予約時刻
  final bool isEnabled;          // 有効/無効
  final String label;            // ラベル（例：「出勤時間」）
  final String selectedAlarmSound;  // ★ 追加

  Alarm({
    String? id,
    required this.scheduledTime,
    this.isEnabled = true,
    this.label = 'Alarm',
    this.selectedAlarmSound = 'default',  // ★ 追加
  }) : id = id ?? const Uuid().v4();

  /// 時刻が過去かどうか
  bool get isPast => scheduledTime.isBefore(DateTime.now());

  /// 残り時間（秒）
  int get secondsUntilAlarm {
    final diff = scheduledTime.difference(DateTime.now());
    return diff.inSeconds > 0 ? diff.inSeconds : 0;
  }

  @override
  String toString() => 'Alarm(id: $id, time: $scheduledTime, enabled: $isEnabled)';
}