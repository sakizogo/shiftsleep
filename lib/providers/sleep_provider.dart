import 'package:flutter/foundation.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/sjl_sri_calculator.dart';

/// 睡眠データの状態を一元管理する Provider
/// 
/// 責務:
/// - 睡眠記録のロード・更新
/// - SJL・SRI・睡眠負債の計算
/// - UI への状態通知
class SleepProvider extends ChangeNotifier {
  final SleepRepository _repository;

  // ========================
  // 状態変数
  // ========================

  SleepRecord? _latestRecord;           // 昨夜の睡眠記録
  List<SleepRecord> _last7DaysRecords = []; // 過去7日のレコード
  List<SleepRecord> _last30DaysRecords = []; // 過去30日のレコード

  double _sjl = 0.0;                    // Social Jetlag (時間)
  double _sri = 0.0;                    // Sleep Regularity Index (%)
  Duration _sleepDebt = Duration.zero;  // 睡眠負債
  
  bool _isLoading = false;
  String? _errorMessage;

  // ========================
  // Getter
  // ========================

  SleepRecord? get latestRecord => _latestRecord;
  List<SleepRecord> get last7DaysRecords => _last7DaysRecords;
  List<SleepRecord> get last30DaysRecords => _last30DaysRecords;

  double get sjl => _sjl;
  double get sri => _sri;
  Duration get sleepDebt => _sleepDebt;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // ========================
  // 計算済み値（UI 用）
  // ========================

  /// 昨夜の睡眠時間（時間:分 形式の文字列）
  String get lastSleepDurationFormatted {
    if (_latestRecord == null) return '--:--';
    
    final duration = _latestRecord!.wakeTime.difference(_latestRecord!.bedtime);
    
    // 翌日にまたがる場合
    if (duration.isNegative) {
      final adjustedDuration = duration + Duration(days: 1);
      return '${adjustedDuration.inHours}h ${adjustedDuration.inMinutes % 60}m';
    }
    
    return '${duration.inHours}h ${duration.inMinutes % 60}m';
  }

  /// 昨夜の入眠時刻（HH:MM 形式）
  String get lastBedtimeFormatted {
    if (_latestRecord == null) return '--:--';
    final time = _latestRecord!.bedtime;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// 昨夜の起床時刻（HH:MM 形式）
  String get lastWakeTimeFormatted {
    if (_latestRecord == null) return '--:--';
    final time = _latestRecord!.wakeTime;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// SJL の評価テキスト
  String get sjlEvaluation {
    if (_sjl < 1.0) {
      return '正常範囲';
    } else if (_sjl < 2.0) {
      return 'やや乱れている';
    } else {
      return '大きく乱れている';
    }
  }

  /// SRI の評価テキスト
  String get sriEvaluation {
    if (_sri >= 80) {
      return '非常に規則正しい';
    } else if (_sri >= 60) {
      return '規則正しい';
    } else if (_sri >= 40) {
      return 'やや不規則';
    } else if (_sri >= 0) {
      return '不規則';
    } else {
      return '大きく乱れている';
    }
  }

  /// 睡眠負債のフォーマット（-14h 30m 形式）
  String get sleepDebtFormatted {
    final isNegative = _sleepDebt.isNegative;
    final absDuration = isNegative 
        ? _sleepDebt.abs() 
        : _sleepDebt;
    
    final sign = isNegative ? '-' : '+';
    return '$sign${absDuration.inHours}h ${absDuration.inMinutes % 60}m';
  }

  /// 睡眠負債の評価テキスト
  String get sleepDebtEvaluation {
    final hours = _sleepDebt.inHours.abs();
    
    if (_sleepDebt.isNegative) {
      if (hours >= 10) return '要注意（10時間以上不足）';
      if (hours >= 5) return '改善推奨（5時間以上不足）';
      return '軽度の不足';
    } else {
      return '十分睡眠が取れています';
    }
  }

  // ========================
  // コンストラクタ
  // ========================

  SleepProvider(this._repository);

  // ========================
  // パブリックメソッド
  // ========================

  /// 全睡眠データとメトリクスをロード
  Future<void> loadAllSleepData() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // データ取得
      _latestRecord = await _repository.getLatestSleepRecord('test_user');
      _last7DaysRecords = await _repository.getSleepRecordsByDateRange(
        'test_user',  // ← 追加
        DateTime.now().subtract(Duration(days: 7)),
        DateTime.now(),
      );
      _last30DaysRecords = await _repository.getSleepRecordsByDateRange(
        'test_user',  // ← 追加
        DateTime.now().subtract(Duration(days: 30)),
        DateTime.now(),
      );

      // メトリクス計算
      _calculateMetrics();

      print('[SleepProvider] Data loaded successfully');
      print('  - Latest: ${_latestRecord?.bedtime ?? "none"}');
      print('  - Last 7 days: ${_last7DaysRecords.length} records');
      print('  - Last 30 days: ${_last30DaysRecords.length} records');
    } catch (e) {
      _errorMessage = 'Failed to load sleep data: $e';
      print('[SleepProvider] Error: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 昨夜のデータのみロード（高速）
  Future<void> loadLatestSleepData() async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      _latestRecord = await _repository.getLatestSleepRecord('test_user');
      print('[SleepProvider] Latest record loaded');
    } catch (e) {
      _errorMessage = 'Failed to load latest sleep data: $e';
      print('[SleepProvider] Error: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 睡眠記録を更新（修正機能用）
  Future<void> updateSleepRecord(SleepRecord record) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _repository.updateSleepRecord(record);

      // 更新後、データを再ロード
      await loadAllSleepData();

      print('[SleepProvider] Record updated: ${record.id}');
    } catch (e) {
      _errorMessage = 'Failed to update sleep record: $e';
      print('[SleepProvider] Error: $_errorMessage');
      notifyListeners();
    }
  }

  /// 睡眠記録を削除
  Future<void> deleteSleepRecord(String recordId) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _repository.deleteSleepRecord(recordId);

      // 更新後、データを再ロード
      await loadAllSleepData();

      print('[SleepProvider] Record deleted: $recordId');
    } catch (e) {
      _errorMessage = 'Failed to delete sleep record: $e';
      print('[SleepProvider] Error: $_errorMessage');
      notifyListeners();
    }
  }

  /// 新規睡眠記録を挿入
  Future<void> insertSleepRecord(SleepRecord record) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _repository.insertSleepRecord(record);

      // 更新後、データを再ロード
      await loadAllSleepData();

      print('[SleepProvider] New record inserted');
    } catch (e) {
      _errorMessage = 'Failed to insert sleep record: $e';
      print('[SleepProvider] Error: $_errorMessage');
      notifyListeners();
    }
  }

  /// 手動でメトリクスを再計算（デバッグ用）
  void recalculateMetrics() {
    _calculateMetrics();
    notifyListeners();
  }

  // ========================
  // プライベートメソッド
  // ========================

  /// SJL・SRI・睡眠負債を計算
  void _calculateMetrics() {
    // SJL 計算（過去7日以上のデータが必要）
    if (_last7DaysRecords.length >= 5) {
      _sjl = SJLSRICalculator.calculateSJL(_last7DaysRecords);
    } else {
      _sjl = 0.0;
    }

    // SRI 計算（過去2日以上のデータが必要）
    if (_last7DaysRecords.length >= 2) {
      _sri = SJLSRICalculator.calculateSRI(_last7DaysRecords);
    } else {
      _sri = 0.0;
    }

    // 睡眠負債計算
    if (_last30DaysRecords.isNotEmpty) {
      _sleepDebt = SJLSRICalculator.calculateSleepDebt(_last30DaysRecords);
    } else {
      _sleepDebt = Duration.zero;
    }

    print('[SleepProvider] Metrics calculated:');
    print('  - SJL: $_sjl h (${sjlEvaluation})');
    print('  - SRI: $_sri (${sriEvaluation})');
    print('  - Debt: ${_sleepDebt.inHours}h ${_sleepDebt.inMinutes % 60}m');
  }
}
