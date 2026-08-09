import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/dimensions.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';

class EventType {
  final String id;
  final String name;
  final String emoji;

  EventType({
    required this.id,
    required this.name,
    required this.emoji,
  });
}

class CalendarEventScreen extends StatefulWidget {
  final DateTime? initialDate;

  const CalendarEventScreen({
    Key? key,
    this.initialDate,
  }) : super(key: key);

  @override
  State<CalendarEventScreen> createState() => CalendarEventScreenState();
}

class CalendarEventScreenState extends State<CalendarEventScreen> {
  final ShiftRepository _shiftRepository = ShiftRepository();

  late DateTime _selectedDate;
  EventType? _selectedEventType;
  final TextEditingController _eventNameController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _isLoading = false;

  final List<EventType> _eventTypes = [
    EventType(id: 'salary', name: '給料日', emoji: '💰'),
    EventType(id: 'bonus', name: 'ボーナス', emoji: '🎁'),
    EventType(id: 'trip', name: '慰安旅行', emoji: '✈️'),
    EventType(id: 'holiday', name: '祝日', emoji: '🎉'),
    EventType(id: 'meeting', name: '重要な会議', emoji: '📅'),
    EventType(id: 'deadline', name: '締切', emoji: '⏰'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('イベント追加'),
        backgroundColor: AppColors.primaryGradientStart,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.sectionPaddingHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppDimensions.paddingLarge),

              Text('日付', style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: AppDimensions.paddingSmall),
              _buildDatePicker(),
              const SizedBox(height: AppDimensions.paddingLarge),

              Text('イベント種類', style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: AppDimensions.paddingSmall),
              _buildEventTypeSelector(),
              const SizedBox(height: AppDimensions.paddingLarge),

              Text('イベント名（オプション）', style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: AppDimensions.paddingSmall),
              _buildEventNameField(),
              const SizedBox(height: AppDimensions.paddingLarge),

              Text('メモ（オプション）', style: AppTextStyles.bodyTextStyle.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: AppDimensions.paddingSmall),
              _buildNotesField(),
              const SizedBox(height: AppDimensions.paddingXLarge),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.borderDefault,
                        padding: EdgeInsets.symmetric(vertical: AppDimensions.paddingMedium),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium)),
                      ),
                      child: Text('キャンセル', style: AppTextStyles.bodyTextStyle.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.paddingMedium),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedEventType != null && !_isLoading ? _saveEvent : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedEventType != null ? AppColors.primaryGradientStart : AppColors.borderDefault,
                        padding: EdgeInsets.symmetric(vertical: AppDimensions.paddingMedium),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium)),
                      ),
                      child: _isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                          : Text('保存', style: AppTextStyles.bodyTextStyle.copyWith(color: _selectedEventType != null ? Colors.white : AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime.utc(2024, 1, 1),
          lastDate: DateTime.utc(2026, 12, 31),
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: AppColors.primaryGradientStart)),
            child: child!,
          ),
        );
        if (picked != null) setState(() => _selectedDate = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium, vertical: AppDimensions.paddingSmall),
        decoration: BoxDecoration(border: Border.all(color: AppColors.borderDefault), borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}', style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 14, color: AppColors.textPrimary)),
            Icon(Icons.calendar_today, size: 20, color: AppColors.primaryGradientStart),
          ],
        ),
      ),
    );
  }

  Widget _buildEventTypeSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _eventTypes.map((eventType) {
          final isSelected = _selectedEventType?.id == eventType.id;
          return Padding(
            padding: const EdgeInsets.only(right: AppDimensions.paddingSmall),
            child: GestureDetector(
              onTap: () => setState(() => _selectedEventType = isSelected ? null : eventType),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium, vertical: AppDimensions.paddingSmall),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryGradientStart.withOpacity(0.2) : AppColors.cardBgGray,
                  border: Border.all(color: isSelected ? AppColors.primaryGradientStart : AppColors.borderDefault, width: isSelected ? 2 : 1),
                  borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSmall),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(eventType.emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 4),
                    Text(eventType.name, style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: isSelected ? AppColors.primaryGradientStart : AppColors.textSecondary), textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEventNameField() {
    return TextField(
      controller: _eventNameController,
      decoration: InputDecoration(
        hintText: '例：夏季ボーナス',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium), borderSide: const BorderSide(color: AppColors.borderDefault)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium), borderSide: const BorderSide(color: AppColors.borderDefault)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium), borderSide: BorderSide(color: AppColors.primaryGradientStart, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium, vertical: AppDimensions.paddingSmall),
      ),
      style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 14),
    );
  }

  Widget _buildNotesField() {
    return TextField(
      controller: _notesController,
      maxLines: 3,
      decoration: InputDecoration(
        hintText: 'メモを追加...',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium), borderSide: const BorderSide(color: AppColors.borderDefault)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium), borderSide: const BorderSide(color: AppColors.borderDefault)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium), borderSide: BorderSide(color: AppColors.primaryGradientStart, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium, vertical: AppDimensions.paddingSmall),
      ),
      style: AppTextStyles.bodyTextStyle.copyWith(fontSize: 14),
    );
  }

  Future<void> _saveEvent() async {
    if (_selectedEventType == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('イベント種類を選択してください'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _shiftRepository.createCalendarEvent(
        _selectedDate,
        _selectedEventType!.id,
        _selectedEventType!.emoji,
        eventName: _eventNameController.text.isNotEmpty ? _eventNameController.text : null,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('イベント保存: ${_selectedDate.month}/${_selectedDate.day} ${_selectedEventType!.emoji}'),
            backgroundColor: AppColors.primaryGradientStart,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('Error saving event: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e'), backgroundColor: AppColors.warningRed));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}