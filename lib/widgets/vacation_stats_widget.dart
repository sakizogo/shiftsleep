import 'package:flutter/material.dart';
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

      setState(() {
        _totalUsed = totalUsed;
        _remaining = remaining;
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

    return Card(
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
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}