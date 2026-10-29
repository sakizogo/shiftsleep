import 'package:flutter/material.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';
import 'package:shiftsleep/services/vacation_allocation.dart';
import 'package:shiftsleep/constants/colors.dart';  // ← Week 27 追加

class VacationStatsWidget extends StatefulWidget {
  final String userId;

  const VacationStatsWidget({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<VacationStatsWidget> createState() => _VacationStatsWidgetState();
}

class _VacationStatsWidgetState extends State<VacationStatsWidget> {
  late VacationRepository _repository;
  double _totalUsed = 0.0;
  FiscalYear? _fiscalYear;  // N66：使用日数を数える付与年度（求まらなければ暦年）
  VacationBalance? _balance;  // N66：残日数と内訳は付与の割り当て結果から出す
  Map<String, dynamic>? _nextExpiringAccrual;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _repository = VacationRepository();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      // N66：使用日数は付与年度（今日より後の予定も含む）で数える
      final fiscalYear = await _repository.getCurrentFiscalYear(widget.userId);
      final fiscalYearUsages = await _repository.getVacationUsageInFiscalYear(widget.userId, fiscalYear);
      final totalUsed = VacationRepository.usedDaysInFiscalYear(fiscalYearUsages, fiscalYear);
      final balance = await _repository.getVacationBalance(widget.userId);
      final nextExpiringAccrual = await _repository.getNextExpiringAccrual(widget.userId);
      debugPrint('📊 N66: 有給統計 残日数=${balance.totalRemaining}, 有効な付与=${balance.totalGranted}, '
          'うち持ち越し=${_carriedOverPart(balance)}, 使用=${balance.totalUsed}');
      debugPrint('📅 N66: 付与年度 ${fiscalYear.start.toIso8601String().split('T')[0]}〜'
          '${fiscalYear.end.toIso8601String().split('T')[0]}${fiscalYear.isCalendarYear ? '（暦年）' : ''}, '
          '使用 ${fiscalYearUsages.length} 件・$totalUsed 日');

      setState(() {
        _totalUsed = totalUsed;
        _fiscalYear = fiscalYear;
        _balance = balance;
        _nextExpiringAccrual = nextExpiringAccrual;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading vacation stats: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 有効な付与のうち、持ち越しの対象の付与の最初の日数（N65）。なければ 0
  static double _carriedOverPart(VacationBalance balance) {
    return balance.validAccruals
        .where((a) => a.isCarryOverTarget)
        .fold(0.0, (sum, a) => sum + a.startingDays);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Column(
      children: [
        // ======================== 有給統計カード（Week 27: protanopia 対応）========================
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📅 今年度の有給統計',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                
                // ========== Week 27: 使用日数（黄色系） + 残日数（青色系）==========
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 使用日数：黄色系
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.vacationUsedBg,
                          border: Border.all(color: AppColors.vacationUsedBorder, width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              // N66：付与年度の開始日を出す（暦年に戻したときは「使用日数」だけ）
                              _fiscalYear == null || _fiscalYear!.isCalendarYear
                                  ? '使用日数'
                                  : '使用日数（${_fiscalYear!.start.month}/${_fiscalYear!.start.day}〜）',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            Text(
                              '${_totalUsed.toStringAsFixed(1)}日',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.vacationUsedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // 残日数：青色系
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.vacationRemainingBg,
                          border: Border.all(color: AppColors.vacationRemainingBorder, width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '残日数',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            Text(
                              '${(_balance?.totalRemaining ?? 0.0).toStringAsFixed(1)}日',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.vacationRemainingText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // N65：内訳は割り当て結果から作る（有効な付与 − 有効な付与から使った分 ＝ 残日数）
                // N66：2 つの枠の下に、横いっぱいの 1 行で出す
                if (_balance != null && _balance!.totalGranted > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '(内訳: 有効な付与 ${_balance!.totalGranted.toStringAsFixed(1)}日'
                    '${_carriedOverPart(_balance!) > 0 ? '〈うち持ち越し ${_carriedOverPart(_balance!).toStringAsFixed(1)}日〉' : ''}'
                    ' − 使用 ${_balance!.totalUsed.toStringAsFixed(1)}日)',
                    style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
        
        // ========== Week 27 修正：有給消滅予定カード（黄色警告系）==========
        if (_nextExpiringAccrual != null)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Card(
              elevation: 0,
              color: AppColors.expiryWarningBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppColors.expiryWarningBorder, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Icon(Icons.warning, color: AppColors.expiryWarningText, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '⏰ 有給消滅予定',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.expiryWarningText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_nextExpiringAccrual!['expiryMonth']}月${_nextExpiringAccrual!['expiryDay']}日までに有休${(_nextExpiringAccrual!['daysRemaining'] as double).toStringAsFixed(1)}日が消滅します',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}