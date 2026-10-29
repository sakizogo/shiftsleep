import 'package:shiftsleep/models/vacation_model.dart';

/// 有休の使用を付与に割り当てて、付与ごとの残りを計算する（N80）
///
/// DB にも Flutter にも依存しない。日付はすべて年・月・日だけで比べる（toLocal() は通さない。N64 と同じ）

/// 持ち越し（N80）
/// 「基準日（持ち越しを数えた時点の直近の付与日）に、その前の付与に残っていた日数」
/// 例：基準日 2026-10-01・20 日 ＝ 2025-10-01 の付与が、2026-10-01 の時点で 20 日残っていた
class CarryOver {
  final DateTime baseDate;  // 基準日
  final double days;        // 持ち越し日数

  const CarryOver({
    required this.baseDate,
    required this.days,
  });
}

/// 1 つの付与の割り当て結果
class AccrualBalance {
  final VacationAccrual accrual;
  final double startingDays;     // 付与日数（持ち越しの対象なら持ち越し日数）
  final double usedDays;         // 割り当てた使用
  final bool isCarryOverTarget;  // 持ち越しの対象の付与か
  final bool isExpired;          // today の時点で失効しているか

  const AccrualBalance({
    required this.accrual,
    required this.startingDays,
    required this.usedDays,
    required this.isCarryOverTarget,
    required this.isExpired,
  });

  /// 残り（0 以上。足りない分は割り当てないので、マイナスにはならない）
  double get remainingDays => startingDays - usedDays;
}

/// 全部の付与の割り当て結果
class VacationBalance {
  final List<AccrualBalance> accruals;  // 付与日の古い順（失効済みも含む）
  final double unallocatedDays;         // 付与が足りず割り当てられなかった使用（ログ用、画面には出さない）

  const VacationBalance({
    required this.accruals,
    required this.unallocatedDays,
  });

  /// 失効していない付与
  Iterable<AccrualBalance> get validAccruals => accruals.where((a) => !a.isExpired);

  /// 有効な付与の残りの合計
  double get totalRemaining =>
      validAccruals.fold(0.0, (sum, a) => sum + a.remainingDays);

  /// 有効な付与の最初の日数の合計
  double get totalGranted =>
      validAccruals.fold(0.0, (sum, a) => sum + a.startingDays);

  /// 有効な付与に割り当てた使用の合計
  double get totalUsed =>
      validAccruals.fold(0.0, (sum, a) => sum + a.usedDays);

  /// 有効な付与のうち、失効がいちばん早いもの（残り 0 でも返す）。なければ null
  AccrualBalance? get nextExpiring {
    AccrualBalance? next;
    for (final a in validAccruals) {
      if (next == null ||
          _dateOnly(a.accrual.expiryDate).isBefore(_dateOnly(next.accrual.expiryDate))) {
        next = a;
      }
    }
    return next;
  }
}

/// 年・月・日だけにする（toLocal() は通さない。UTC の値も数字をそのまま使う）
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 使用を付与に割り当てる（N80）
///
/// - 使用は日付の古い順に、その日に有効（付与日 ≦ 使用日 ≦ 失効日）で残りがある付与のうち、
///   付与日がいちばん古いものから引く。足りなければ次の付与から引く（0.5 日もそのまま）
/// - 失効した付与も割り当ての対象に入れる（残りの合計には有効な付与だけを足す）
/// - 持ち越しの対象（付与日が基準日より前の付与のうち、いちばん新しいもの）は持ち越し日数から始め、
///   基準日より前の使用はその付与から引かない（持ち越しの数にすでに入っているため）
/// - どの付与からも引けなかった分は unallocatedDays に足すだけ（残りはマイナスにしない）
/// - 未来の使用（予定の有休）も引く
VacationBalance allocateUsage({
  required List<VacationAccrual> accruals,
  required List<VacationUsage> usages,
  required DateTime today,
  CarryOver? carryOver,
}) {
  final todayDate = _dateOnly(today);

  final sortedAccruals = [...accruals]
    ..sort((a, b) => _dateOnly(a.accrualDate).compareTo(_dateOnly(b.accrualDate)));

  // 持ち越しの対象の付与（持ち越しが 0 以下、または基準日より前に付与がなければ使わない）
  DateTime? baseDate;
  int? targetIndex;
  if (carryOver != null && carryOver.days > 0) {
    baseDate = _dateOnly(carryOver.baseDate);
    for (int i = 0; i < sortedAccruals.length; i++) {
      if (_dateOnly(sortedAccruals[i].accrualDate).isBefore(baseDate)) {
        targetIndex = i;  // 古い順なので、最後に当たったものがいちばん新しい
      }
    }
  }

  final startingDays = [
    for (int i = 0; i < sortedAccruals.length; i++)
      i == targetIndex ? carryOver!.days : sortedAccruals[i].daysGranted,
  ];
  final usedDays = List<double>.filled(sortedAccruals.length, 0.0);
  var unallocatedDays = 0.0;

  final sortedUsages = [...usages]
    ..sort((a, b) => _dateOnly(a.usageDate).compareTo(_dateOnly(b.usageDate)));

  for (final usage in sortedUsages) {
    final day = _dateOnly(usage.usageDate);
    var need = usage.daysUsed;

    for (int i = 0; i < sortedAccruals.length && need > 0; i++) {
      final accrual = sortedAccruals[i];
      if (day.isBefore(_dateOnly(accrual.accrualDate))) continue;
      if (day.isAfter(_dateOnly(accrual.expiryDate))) continue;
      if (i == targetIndex && day.isBefore(baseDate!)) continue;

      final left = startingDays[i] - usedDays[i];
      if (left <= 0) continue;

      final take = left < need ? left : need;
      usedDays[i] += take;
      need -= take;
    }

    if (need > 0) unallocatedDays += need;
  }

  return VacationBalance(
    accruals: [
      for (int i = 0; i < sortedAccruals.length; i++)
        AccrualBalance(
          accrual: sortedAccruals[i],
          startingDays: startingDays[i],
          usedDays: usedDays[i],
          isCarryOverTarget: i == targetIndex,
          isExpired: todayDate.isAfter(_dateOnly(sortedAccruals[i].expiryDate)),
        ),
    ],
    unallocatedDays: unallocatedDays,
  );
}
