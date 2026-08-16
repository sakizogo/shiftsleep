import 'package:flutter/foundation.dart';
import 'package:shiftsleep/models/sleep_record.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';  // ← この行を追加
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/sjl_sri_calculator.dart';
import 'package:shiftsleep/services/sleep_advisory_service.dart';  // ========== Week 7 A 追加 ==========

/// 睡眠データの状態を一元管理する Provider
/// 
/// 責務:
/// - 睡眠記録のロード・更新
/// - SJL・SRI・睡眠負債の計算
/// - UI への状態通知
/// 
/// Week 7 A 追加:
/// - 分割睡眠（メイン + 補助）の集計
/// - 理想睡眠時間の推奨
/// - 睡眠改善アドバイスの生成
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

  // ========== Week 7 A 追加: アドバイス関連 ==========
  List<SleepAdvice> _allAdvice = [];    // 生成されたアドバイス（全て）
  List<SleepAdvice> _displayedAdvice = []; // 表示対象のアドバイス
  bool _isPremiumUser = false;          // 有料ユーザーフラグ
  bool _advicePromoVisible = true;  // ← この行を追加
  // ================================================

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

  // ========== Week 7 A 追加: アドバイス Getter ==========
  List<SleepAdvice> get displayedAdvice => _displayedAdvice;
  List<SleepAdvice> get allAdvice => _allAdvice;
  bool get isPremiumUser => _isPremiumUser;
  bool get advicePromoVisible => _advicePromoVisible;  // ← この行を追加
  
  /// 表示対象のアドバイスがあるか
  bool get hasAdvice => _displayedAdvice.isNotEmpty;
  
  /// 最優先のアドバイス（ホーム画面に表示）
  SleepAdvice? get topAdvice => _displayedAdvice.isNotEmpty 
    ? _displayedAdvice.first 
    : null;
  // ================================================

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

  // ========== Week 7 A 追加: 分割睡眠関連の Getter ==========
  
  /// 昨日のメイン睡眠時間（時間:分 形式）
  String get lastPrimarySleepFormatted {
    if (_latestRecord == null) return '--:--';
    
    // 最新レコードがメイン睡眠か確認
    if (_latestRecord!.sleepRole != SleepRole.primary) {
      return '--:--';
    }
    
    final duration = _latestRecord!.wakeTime.difference(_latestRecord!.bedtime);
    if (duration.isNegative) {
      final adjustedDuration = duration + Duration(days: 1);
      return '${adjustedDuration.inHours}h ${adjustedDuration.inMinutes % 60}m';
    }
    
    return '${duration.inHours}h ${duration.inMinutes % 60}m';
  }

  /// 昨日の補助睡眠時間（昼寝など）の合計（時間:分 形式）
  String get lastSupplementarySleepFormatted {
    if (_last7DaysRecords.isEmpty) return '--:--';
    
    // 昨日のレコードを抽出
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    final yesterdayRecords = _last7DaysRecords
        .where((record) => 
          record.sleepDate.year == yesterday.year &&
          record.sleepDate.month == yesterday.month &&
          record.sleepDate.day == yesterday.day &&
          record.sleepRole == SleepRole.supplementary
        )
        .toList();
    
    if (yesterdayRecords.isEmpty) return '0h 0m';
    
    int totalMinutes = 0;
    for (final record in yesterdayRecords) {
      final duration = record.wakeTime.difference(record.bedtime);
      if (duration.isNegative) {
        totalMinutes += (duration.inMinutes + 24 * 60);
      } else {
        totalMinutes += duration.inMinutes;
      }
    }
    
    return '${totalMinutes ~/ 60}h ${totalMinutes % 60}m';
  }

  /// 昨日の総睡眠時間（メイン + 補助）の合計（時間:分 形式）
  String get lastTotalSleepFormatted {
    if (_last7DaysRecords.isEmpty && _latestRecord == null) return '--:--';
    
    // 昨日のレコードを抽出（すべての SleepRole）
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    final yesterdayRecords = _last7DaysRecords
        .where((record) => 
          record.sleepDate.year == yesterday.year &&
          record.sleepDate.month == yesterday.month &&
          record.sleepDate.day == yesterday.day
        )
        .toList();
    
    if (yesterdayRecords.isEmpty) return '--:--';
    
    int totalMinutes = 0;
    for (final record in yesterdayRecords) {
      final duration = record.wakeTime.difference(record.bedtime);
      if (duration.isNegative) {
        totalMinutes += (duration.inMinutes + 24 * 60);
      } else {
        totalMinutes += duration.inMinutes;
      }
    }
    
    return '${totalMinutes ~/ 60}h ${totalMinutes % 60}m';
  }

  /// 過去7日間の平均睡眠時間（メイン睡眠のみ）
  String get averagePrimarySleepFormatted {
    final primaryRecords = _last7DaysRecords
        .where((record) => record.sleepRole == SleepRole.primary)
        .toList();
    
    if (primaryRecords.isEmpty) return '--:--';
    
    int totalMinutes = 0;
    for (final record in primaryRecords) {
      final duration = record.wakeTime.difference(record.bedtime);
      if (duration.isNegative) {
        totalMinutes += (duration.inMinutes + 24 * 60);
      } else {
        totalMinutes += duration.inMinutes;
      }
    }
    
    final averageMinutes = totalMinutes ~/ primaryRecords.length;
    return '${averageMinutes ~/ 60}h ${averageMinutes % 60}m';
  }

  /// 理想睡眠時間の推奨（固定値: 7時間）
  String get recommendedSleepFormatted {
    return '7h 0m';
  }
  // ========================================================================

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
        'test_user',
        DateTime.now().subtract(Duration(days: 7)),
        DateTime.now(),
      );
      _last30DaysRecords = await _repository.getSleepRecordsByDateRange(
        'test_user',
        DateTime.now().subtract(Duration(days: 30)),
        DateTime.now(),
      );

      // メトリクス計算
      _calculateMetrics();

      // ========== Week 7 A 追加: アドバイス生成 ==========
            
      // ========== Week 7 Phase 2 追加: AppSettings から改善アドバイス表示設定を読み込む ==========
      // settings_screen.dart と同じリポジトリインスタンスを作成
      final shiftRepository = ShiftRepository();
      final settings = await shiftRepository.getAppSettings('test_user');
      if (settings != null) {
        _advicePromoVisible = settings.advicePromoVisible;
      }
      // ====================================================================
      
      _generateAdvice();
      // ================================================

      print('[SleepProvider] Data loaded successfully');
      print('  - Latest: ${_latestRecord?.bedtime ?? "none"}');
      print('  - Latest sleepRole: ${_latestRecord?.sleepRole.jsonValue ?? "none"}');
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

  /// ========== Week 7 A 追加: 有料ユーザーフラグを設定 ==========
  /// 
  /// AppSettings から isPremium を取得して設定
  void setPremiumStatus(bool isPremium) {
    _isPremiumUser = isPremium;
    _generateAdvice();
    notifyListeners();
  }
  // ================================================================

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

  /// ========== Week 7 A 追加: アドバイスを生成 ==========
  /// 
  /// SJL/SRI/睡眠負債から改善ポイントを抽出し、
  /// 無料版/有料版に応じた表示内容を決定
  void _generateAdvice() {
    // アドバイス生成
    _allAdvice = SleepAdvisoryService.generateAdvice(
      sjl: _sjl,
      sri: _sri,
      sleepDebt: _sleepDebt,
      last7DaysRecords: _last7DaysRecords,
      isPremiumUser: _isPremiumUser,
    );

    // 表示対象アドバイスをフィルタリング
    _displayedAdvice = SleepAdvisoryService.filterAdviceByPlan(
      _allAdvice,
      isPremiumUser: _isPremiumUser,
    );

    print('[SleepProvider] Advice generated:');
    print('  - Total: ${_allAdvice.length} advices');
    print('  - Displayed: ${_displayedAdvice.length} advices (Premium: $_isPremiumUser)');
    if (_displayedAdvice.isNotEmpty) {
      print('  - Top advice: ${_displayedAdvice.first.title}');
    }
  }
  // ================================================================
}