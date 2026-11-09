import 'package:flutter/material.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';
import 'package:shiftsleep/services/vacation_allocation.dart';
import 'package:shiftsleep/services/vacation_load_state.dart';  // N118 3/4 3d
import 'package:shiftsleep/constants/colors.dart';  // ← Week 27 追加

class VacationStatsWidget extends StatefulWidget {
  final String userId;
  // N140 3/4：有休・半休の未確定の 1 行（数字は確定済みだけ。未確定がなければ null）
  final String? pendingText;

  const VacationStatsWidget({
    Key? key,
    required this.userId,
    this.pendingText,
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
  // N118 3/4 3d：読み込みの状態。failed のときは数字を「—」にし、内訳・消滅予定は出さない（D4）
  VacationLoadState _loadState = VacationLoadState.loading;
  // N118 3/4 3d：カードの中の［再読み込み］の処理中（二度押し防止）
  bool _isReloading = false;

  @override
  void initState() {
    super.initState();
    _repository = VacationRepository();
    _loadStats();
  }

  /// N118 3/4 3d：どれか 1 つでも読めなければ（消滅予定だけでも）全体を失敗にする（D3）
  /// 作り直されたあと（ValueKey が変わったあと）は何もしない。新しいカードが自分で読んで表示する
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

      if (!mounted) return;
      setState(() {
        _totalUsed = totalUsed;
        _fiscalYear = fiscalYear;
        _balance = balance;
        _nextExpiringAccrual = nextExpiringAccrual;
        _loadState = VacationLoadState.loaded;
      });
    } catch (e) {
      print('Error loading vacation stats: $e');
      if (!mounted) return;
      setState(() => _loadState = VacationLoadState.failed);
    }
  }

  /// N118 3/4 3d：カードの中の［再読み込み］。結果はカードの表示で分かるので SnackBar は出さない（H）
  /// 再読み込み中は「—」のまま、ボタンを「読み込み中…」にする（J）
  Future<void> _reloadStats() async {
    if (!canReloadVacationSettings(reloading: _isReloading)) return;
    setState(() => _isReloading = true);
    try {
      await _loadStats();
    } finally {
      if (mounted) setState(() => _isReloading = false);
    }
  }

  /// N118 3/4 3d：読み込めなかったときの 1 行と［再読み込み］（カードの中）
  Widget _buildLoadFailedRow() {
    return Row(
      children: [
        Expanded(
          child: Text(
            vacationStatsLoadFailedText,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: canReloadVacationSettings(reloading: _isReloading) ? _reloadStats : null,
          icon: _isReloading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          label: Text(_isReloading ? '読み込み中…' : '再読み込み'),
        ),
      ],
    );
  }

  /// 有効な付与のうち、持ち越しの対象の付与の最初の日数（N65）。なければ 0
  static double _carriedOverPart(VacationBalance balance) {
    return balance.validAccruals
        .where((a) => a.isCarryOverTarget)
        .fold(0.0, (sum, a) => sum + a.startingDays);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadState == VacationLoadState.loading) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // N118 3/4 3d：失敗中は数字を「—」に（null を渡す）、内訳・消滅予定は出さない
    final loaded = _loadState == VacationLoadState.loaded;
    final showDetails = showVacationStatsDetails(_loadState);

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
                              // N118 3/4 3d：失敗中は付与年度がわからないので「使用日数」だけ
                              !loaded || _fiscalYear == null || _fiscalYear!.isCalendarYear
                                  ? '使用日数'
                                  : '使用日数（${_fiscalYear!.start.month}/${_fiscalYear!.start.day}〜）',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            Text(
                              vacationStatsDaysText(loaded ? _totalUsed : null),
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
                              vacationStatsDaysText(loaded ? (_balance?.totalRemaining ?? 0.0) : null),
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
                if (showDetails && _balance != null && _balance!.totalGranted > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '(内訳: 有効な付与 ${_balance!.totalGranted.toStringAsFixed(1)}日'
                    '${_carriedOverPart(_balance!) > 0 ? '〈うち持ち越し ${_carriedOverPart(_balance!).toStringAsFixed(1)}日〉' : ''}'
                    ' − 使用 ${_balance!.totalUsed.toStringAsFixed(1)}日)',
                    style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
                // N118 3/4 3d：読み込めなかったときの 1 行と［再読み込み］（D5：カードの中）
                if (_loadState == VacationLoadState.failed) ...[
                  const SizedBox(height: 8),
                  _buildLoadFailedRow(),
                ],
                // N140 3/4：未確定の有休・半休（確定するまで上の数字には入らない）
                // N118 3/4 3d（I）：DB を読まずに画面の未確定から作る 1 行なので、失敗中も出す
                if (widget.pendingText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.pendingText!,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ],
              ],
            ),
          ),
        ),
        
        // ========== Week 27 修正：有給消滅予定カード（黄色警告系）==========
        if (showDetails && _nextExpiringAccrual != null)
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