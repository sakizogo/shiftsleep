import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shiftsleep/repositories/vacation_repository.dart';

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
  double _remaining = 0.0;
  double _carriedOverDays = 0.0;
  double _daysExpiring = 0.0;
  DateTime? _expirationDate;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _repository = VacationRepository();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final totalUsed = await _repository.getTotalDaysUsedThisYear(widget.userId);
      final remaining = await _repository.getRemainingDaysThisYear(widget.userId);
      
      // Week 13: 持ち越し有休関連を取得
      final carriedOverDays = await _repository.getCarriedOverDays(widget.userId) ?? 0.0;
      final daysExpiring = await _repository.getDaysExpiringThisYear(widget.userId) ?? 0.0;
      final expirationDate = await _repository.getExpirationDate(widget.userId);

      setState(() {
        _totalUsed = totalUsed;
        _remaining = remaining;
        _carriedOverDays = carriedOverDays;
        _daysExpiring = daysExpiring;
        _expirationDate = expirationDate;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading vacation stats: $e');
      setState(() {
        _isLoading = false;
      });
    }
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
        // ======================== 有給統計カード ========================
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📅 今年の有給統計',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('使用日数', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(
                          '${_totalUsed.toStringAsFixed(1)}日',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('残日数', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(
                          '${_remaining.toStringAsFixed(1)}日',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        if (_carriedOverDays > 0)
                          Text(
                            '(内訳: 付与20日 + 持ち越し${_carriedOverDays.toStringAsFixed(0)}日 - 使用${_totalUsed.toStringAsFixed(1)}日)',
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // ======================== Week 13: 消滅予定メッセージ ========================
        if (_daysExpiring > 0 && _expirationDate != null)
          Card(
            elevation: 1,
            color: Colors.orange.withOpacity(0.1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${DateFormat('M月d日').format(_expirationDate!)}に前年分の有休${_daysExpiring.toStringAsFixed(0)}日が消滅します。',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '計画的に使いましょう！',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        // ===============================================================================
      ],
    );
  }
}