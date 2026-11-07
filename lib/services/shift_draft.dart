// シフト管理の未確定の差分（N140）
//
// DB から読めた内容（基準）と画面の内容を比べて、追加・変更・削除を差分にする
// 読み直したときは、DB の新しい内容の上に差分を重ねる
// 差分は ShiftDraftStore に入れて home_screen が持つ（シフト管理画面の State が作り直されても残る）
// DB・画面には依存しない
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shiftsleep/constants/shift_enums.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';

/// 1 日分の未確定の変更
class ShiftDraftEntry {
  /// 未確定のパターン。null は削除（× の削除も含む）
  final ShiftPatternModel? pattern;

  /// 差分を作ったときの基準の pattern_id（行がなければ null）
  final String? basePatternId;

  /// 基準を読む前に入れた変更なら false（衝突の判定をしない）
  final bool baseKnown;

  const ShiftDraftEntry({
    required this.pattern,
    required this.basePatternId,
    this.baseKnown = true,
  });
}

/// 未確定の変更の一覧（日付は時刻なし）
class ShiftDraft {
  final Map<DateTime, ShiftDraftEntry> entries;

  const ShiftDraft([this.entries = const {}]);

  bool get isEmpty => entries.isEmpty;
  int get length => entries.length;
}

/// mergeShiftDraft の結果
class ShiftDraftMergeResult {
  /// _shiftMap の新しい中身
  final Map<DateTime, ShiftPatternModel> merged;

  /// 別の画面で変えられた日（未確定を優先した）
  final List<DateTime> conflictDates;

  /// パターンが削除されて、未確定から外した日
  final List<DateTime> removedDates;

  const ShiftDraftMergeResult({
    required this.merged,
    required this.conflictDates,
    required this.removedDates,
  });
}

/// 基準と今の内容を比べて差分を作る（パターンは ID で比べる）
ShiftDraft computeShiftDraft({
  required Map<DateTime, ShiftPatternModel> base,
  required Map<DateTime, ShiftPatternModel> current,
}) {
  final entries = <DateTime, ShiftDraftEntry>{};
  base.forEach((date, basePattern) {
    final pattern = current[date];
    if (pattern == null) {
      entries[date] = ShiftDraftEntry(pattern: null, basePatternId: basePattern.id);
    } else if (pattern.id != basePattern.id) {
      entries[date] = ShiftDraftEntry(pattern: pattern, basePatternId: basePattern.id);
    }
  });
  current.forEach((date, pattern) {
    if (!base.containsKey(date)) {
      entries[date] = ShiftDraftEntry(pattern: pattern, basePatternId: null);
    }
  });
  return ShiftDraft(entries);
}

/// 基準を読む前に入れた変更を差分にする（基準がないあいだの _shiftMap には、入れた分しかない）
ShiftDraft editsWithoutBase(Map<DateTime, ShiftPatternModel> current) {
  return ShiftDraft({
    for (final entry in current.entries)
      entry.key: ShiftDraftEntry(pattern: entry.value, basePatternId: null, baseKnown: false),
  });
}

/// 古い差分の上に新しい差分を重ねる
/// 同じ日は新しい方の内容にし、基準は古い方を引き継ぐ（古い方の基準が不明なら新しい方）
ShiftDraft overlayShiftDraft(ShiftDraft older, ShiftDraft newer) {
  final entries = Map<DateTime, ShiftDraftEntry>.of(older.entries);
  newer.entries.forEach((date, entry) {
    final previous = older.entries[date];
    entries[date] = previous != null && previous.baseKnown
        ? ShiftDraftEntry(
            pattern: entry.pattern,
            basePatternId: previous.basePatternId,
          )
        : entry;
  });
  return ShiftDraft(entries);
}

/// DB の新しい内容の上に差分を重ねる
/// patterns：信用できるパターンの一覧。読めていないときは null（パターンの削除を判定しない）
ShiftDraftMergeResult mergeShiftDraft({
  required Map<DateTime, ShiftPatternModel> db,
  required ShiftDraft draft,
  required List<ShiftPatternModel>? patterns,
}) {
  final merged = Map<DateTime, ShiftPatternModel>.of(db);
  final conflictDates = <DateTime>[];
  final removedDates = <DateTime>[];

  final dates = draft.entries.keys.toList()..sort();
  for (final date in dates) {
    final entry = draft.entries[date]!;
    var target = entry.pattern;

    if (target != null && patterns != null) {
      // 同じ ID の最新のパターンにする（開始時刻の編集が pre に反映されるように）
      final latest = _findPattern(patterns, target.id);
      if (latest == null) {
        removedDates.add(date);
        continue;
      }
      target = latest;
    }

    final dbId = db[date]?.id;
    // DB がもう同じ内容（確定と入れ違いになった差分・すぐ消した行）なら捨てる
    if (dbId == target?.id) continue;

    if (entry.baseKnown && dbId != entry.basePatternId) {
      conflictDates.add(date);
    }
    if (target == null) {
      merged.remove(date);
    } else {
      merged[date] = target;
    }
  }

  return ShiftDraftMergeResult(
    merged: merged,
    conflictDates: conflictDates,
    removedDates: removedDates,
  );
}

ShiftPatternModel? _findPattern(List<ShiftPatternModel> patterns, String id) {
  for (final pattern in patterns) {
    if (pattern.id == id) return pattern;
  }
  return null;
}

/// マージの結果を知らせる文言。知らせることがなければ null
/// N140 3/4：有休・半休の衝突の日もまとめて数える（シフトと同じ日は 1 日）
String? draftMergeNotice(
  ShiftDraftMergeResult result, {
  Iterable<DateTime> vacationConflictDates = const [],
}) {
  final conflictDays = {...result.conflictDates, ...vacationConflictDates}.length;
  final lines = <String>[
    if (result.removedDates.isNotEmpty)
      '⚠️ 削除されたパターンの未確定シフト ${result.removedDates.length}日分を外しました',
    if (conflictDays > 0)
      '⚠️ 別の画面で変更された日の未確定シフト $conflictDays日分は、未確定の内容を残しました',
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

// ========== N140 3/4：有休・半休の未確定 ==========
// 有休・半休は「シフトを確定」まで DB に書かない。基準（DB から読めた日数）と今の日数を比べて差分にする
// 有休を読めるまでは画面で登録を止めるので、シフトの editsWithoutBase に当たるものはない

/// 1 日分の有休・半休の未確定の変更
class VacationDraftEntry {
  /// 未確定の日数（1.0 か 0.5）。null は削除
  final double? days;

  /// 差分を作ったときの基準の日数（行がなければ null）
  final double? baseDays;

  const VacationDraftEntry({required this.days, required this.baseDays});
}

/// 有休・半休の未確定の変更の一覧（日付は時刻なし）
class VacationDraft {
  final Map<DateTime, VacationDraftEntry> entries;

  const VacationDraft([this.entries = const {}]);

  bool get isEmpty => entries.isEmpty;
  int get length => entries.length;
}

/// 基準と今の日数を比べて差分を作る
VacationDraft computeVacationDraft({
  required Map<DateTime, double> base,
  required Map<DateTime, double> current,
}) {
  final entries = <DateTime, VacationDraftEntry>{};
  base.forEach((date, baseDays) {
    final days = current[date];
    if (days != baseDays) entries[date] = VacationDraftEntry(days: days, baseDays: baseDays);
  });
  current.forEach((date, days) {
    if (!base.containsKey(date)) entries[date] = VacationDraftEntry(days: days, baseDays: null);
  });
  return VacationDraft(entries);
}

/// mergeVacationDraft の結果
class VacationDraftMergeResult {
  /// _vacationMap の新しい中身
  final Map<DateTime, double> merged;

  /// 別の画面で変えられた日（未確定を優先した）
  final List<DateTime> conflictDates;

  const VacationDraftMergeResult({required this.merged, required this.conflictDates});
}

/// DB の新しい日数の上に差分を重ねる（規則はシフトの mergeShiftDraft と同じ）
/// - DB がもう未確定と同じなら捨てる
/// - DB が基準と違えば、未確定を優先して衝突に数える
VacationDraftMergeResult mergeVacationDraft({
  required Map<DateTime, double> db,
  required VacationDraft draft,
}) {
  final merged = Map<DateTime, double>.of(db);
  final conflictDates = <DateTime>[];
  final dates = draft.entries.keys.toList()..sort();
  for (final date in dates) {
    final entry = draft.entries[date]!;
    final dbDays = db[date];
    if (dbDays == entry.days) continue;
    if (dbDays != entry.baseDays) conflictDates.add(date);
    final days = entry.days;
    if (days == null) {
      merged.remove(date);
    } else {
      merged[date] = days;
    }
  }
  return VacationDraftMergeResult(merged: merged, conflictDates: conflictDates);
}

/// 未確定の日数（シフトと有休・半休の両方が変わった日も 1 日）
int draftDayCount(ShiftDraft shift, VacationDraft vacation) =>
    {...shift.entries.keys, ...vacation.entries.keys}.length;

/// 確定すると増える使用日数（減るときはマイナス）
double vacationDraftDelta(VacationDraft draft) => draft.entries.values
    .fold(0.0, (sum, entry) => sum + (entry.days ?? 0) - (entry.baseDays ?? 0));

/// 有休の統計に足す 1 行。未確定がなければ null
String? vacationPendingStatsText(VacationDraft draft) {
  if (draft.isEmpty) return null;
  final delta = vacationDraftDelta(draft);
  final sign = delta > 0 ? '+' : (delta < 0 ? '−' : '±');
  return '📝 未確定の有休・半休：使用 $sign${delta.abs().toStringAsFixed(1)}日（確定すると反映されます）';
}

/// 確定のときに vacation_usage へ書く変更（差分のある日だけ。日付順）。days が null の日は行を消す
List<({DateTime date, double? days})> vacationSaveChanges(VacationDraft draft) {
  final dates = draft.entries.keys.toList()..sort();
  return [for (final date in dates) (date: date, days: draft.entries[date]!.days)];
}

String _vacationLabel(double days) => days == 0.5 ? '🌤️ 半休' : '🏖️ 有休';

/// 1 日分の有休・半休の未確定を 1 行にする（例：11/7 🌤️ 半休を入れる）
String vacationDraftLine(DateTime date, VacationDraftEntry entry) {
  final days = entry.days;
  final baseDays = entry.baseDays;
  final String action;
  if (days == null) {
    action = '${_vacationLabel(baseDays ?? 1.0)}を消す';
  } else if (baseDays == null) {
    action = '${_vacationLabel(days)}を入れる';
  } else {
    action = '${_vacationLabel(days)}にする（${baseDays == 0.5 ? '半休' : '有休'}から）';
  }
  return '${date.month}/${date.day} $action';
}

/// 有休・半休の未確定の行（日付順）。exclude の日は出さない
List<String> vacationDraftLines(VacationDraft draft, {Set<DateTime> exclude = const {}}) {
  final dates = draft.entries.keys.where((date) => !exclude.contains(date)).toList()..sort();
  return [for (final date in dates) vacationDraftLine(date, draft.entries[date]!)];
}

/// 詳細確認の有休・半休の見出し
String vacationDraftHeader(int days) => '📝 有休・半休の未確定 $days日';

/// シフトを変えたあとのその日の有休・半休の日数（カレンダーと同じ規則）
/// - 有休パターンにしたら 1.0、半休パターンにしたら 0.5
/// - シフトを消したら、有休・半休パターンの日だけ有休・半休も消す（一覧の × と同じ）
/// - ほかのパターンにしたら、有休（1.0）だけ消す。半休はシフトと共存させる（N77）
double? vacationDaysAfterShiftEdit({
  required double? currentDays,
  required ShiftPatternModel? oldPattern,
  required ShiftPatternModel? newPattern,
}) {
  if (newPattern == null) {
    final oldType = oldPattern?.patternType;
    return oldType == ShiftType.vacation || oldType == ShiftType.halfVacation ? null : currentDays;
  }
  if (newPattern.patternType == ShiftType.vacation) return 1.0;
  if (newPattern.patternType == ShiftType.halfVacation) return 0.5;
  return currentDays == 1.0 ? null : currentDays;
}

// ========== N140 2/4：文言と判定 ==========

const String draftDiscardButtonLabel = '未確定を破棄';
const String draftDiscardDialogTitle = '未確定のシフトを破棄しますか？';
const String draftCloseDialogTitle = 'アプリを閉じますか？';
const String deleteAllDialogTitle = 'すべてのシフトを削除しますか？';

/// シフト管理画面のバナー
String draftBannerText(int count) =>
    '📝 未確定のシフトが $count日分あります。「確認へ進む」→「シフトを確定」で保存されます';

/// 下のタブのバッジの数字
String draftBadgeLabel(int count) => count > 99 ? '99+' : '$count';

/// カレンダーでシフトを入れたとき。pending：その日が未確定になったか（確定済みと同じなら false）
String shiftPlacedMessage(String patternName, {required bool pending}) => pending
    ? '📝 $patternNameを入れました（未確定）'
    : '✅ $patternNameは確定済みのシフトと同じです';

/// カレンダーで有休を入れたとき
/// replacedWork：出勤のシフトを置き換えたか（確定で出勤前アラームが取り消される）
String vacationPlacedMessage(
  String patternName, {
  required bool pending,
  required bool replacedWork,
}) {
  if (!pending) return shiftPlacedMessage(patternName, pending: false);
  return '📝 $patternNameを入れました（未確定）'
      '${replacedWork ? '\n「シフトを確定」を押すと出勤前アラームが取り消されます' : ''}';
}

/// 期間指定でシフトを入れたとき。label を渡すと「📝 半休 3日を入れました（未確定）」の形にする
String rangeAddedMessage(int days, {String? label}) =>
    label == null ? '📝 $days日入れました（未確定）' : '📝 $label $days日を入れました（未確定）';

/// 一覧の見出し（全部 × しても削除の日数が分かるようにする）
/// N140 3/4：有休・半休だけが変わった日を「有休・半休」に数える（未確定 = 追加・変更 + 削除 + 有休・半休）
String shiftListHeader(int totalDays, ShiftDraft draft, [VacationDraft vacation = const VacationDraft()]) {
  final vacationOnly = vacation.entries.keys.where((date) => !draft.entries.containsKey(date)).length;
  if (draft.isEmpty && vacationOnly == 0) return '登録中のシフト: $totalDays日';
  final deleted = draft.entries.values.where((entry) => entry.pattern == null).length;
  final addedOrChanged = draft.length - deleted;
  return '登録中のシフト: $totalDays日'
      '（📝 未確定 ${draft.length + vacationOnly}日：追加・変更 $addedOrChanged／削除 $deleted'
      '${vacationOnly > 0 ? '／有休・半休 $vacationOnly' : ''}）';
}

/// 未確定を破棄するダイアログの本文
String draftDiscardDialogBody(int count) =>
    '未確定の $count日分を取り消します。確定済みのシフトは変わりません。';

/// 破棄したあとの知らせ
String draftDiscardedMessage(int count) => '📝 未確定の $count日分を破棄しました';

/// 戻るボタンでアプリを閉じるときのダイアログの本文
String draftCloseDialogBody(int count) =>
    '未確定のシフトが $count日分あります。閉じると消えます。'
    '残すには「確認へ進む」→「シフトを確定」を押してください。';

/// 「確認へ進む」を押せるか（全部 × したあとも、削除を確定できるようにする）
bool canProceedToConfirm({required int totalDays, required int pendingDays}) =>
    totalDays > 0 || pendingDays > 0;

/// 「シフトを確定」の前に、全部消してよいか確かめるか
/// もともと確定済みのシフトがなければ、消えるものがないので確かめない
bool shouldConfirmDeleteAll({required int shiftDays, required int confirmedDays}) =>
    shiftDays == 0 && confirmedDays > 0;

/// 全部消すときのダイアログの本文
String deleteAllDialogBody(int confirmedDays) =>
    '確定済みのシフト $confirmedDays日分がすべて削除され、出勤前アラームも取り消されます。';

/// 戻るボタンで何をするか
enum ShiftBackAction {
  /// 詳細確認からカレンダーへ戻る（アプリは閉じない）
  backToCalendar,

  /// 未確定が消えることを確かめてから閉じる
  confirmClose,

  /// そのまま閉じる
  close,
}

ShiftBackAction shiftBackAction({required bool isDetails, required int pendingCount}) {
  if (isDetails) return ShiftBackAction.backToCalendar;
  return pendingCount > 0 ? ShiftBackAction.confirmClose : ShiftBackAction.close;
}

/// 未確定の差分の置き場所（home_screen が 1 つ持つ）
class ShiftDraftStore {
  ShiftDraft _draft = const ShiftDraft();
  Map<DateTime, ShiftPatternModel>? _base;
  VacationDraft _vacationDraft = const VacationDraft();  // N140 3/4
  Map<DateTime, double>? _vacationBase;  // N140 3/4
  bool _disposed = false;

  /// 未確定の日数（バッジが見る）。シフト管理画面の表示中は、画面が reportLive で伝える
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  ShiftDraft get draft => _draft;

  /// N140 3/4：有休・半休の未確定
  VacationDraft get vacationDraft => _vacationDraft;

  /// 確定済みのシフトの日数（預かった基準の日数）
  int get confirmedCount => _base?.length ?? 0;

  /// N140 3/4：その日の有休・半休の日数（未確定があればその日数、なければ基準の日数）
  double? vacationDaysOn(DateTime date) {
    final entry = _vacationDraft.entries[date];
    return entry != null ? entry.days : _vacationBase?[date];
  }

  void _publish() {
    if (_disposed) return;
    pendingCount.value = draftDayCount(_draft, _vacationDraft);
  }

  /// シフト管理画面の表示中の未確定の日数を伝える（件数だけ変える。預かっている差分には触らない）
  void reportLive(int count) {
    if (_disposed) return;
    pendingCount.value = count;
  }

  /// シフト管理画面の State が消えるときに、その内容を預かる
  /// base が null（この State で一度も読めていない）なら、入れた分だけを今の差分に重ねる
  /// N140 3/4：vacationBase が null（有休を読めていない）なら、有休の差分はそのまま残す
  void saveFromScreen({
    required Map<DateTime, ShiftPatternModel>? base,
    required Map<DateTime, ShiftPatternModel> current,
    Map<DateTime, double>? vacationBase,
    Map<DateTime, double> vacationCurrent = const {},
  }) {
    if (base == null) {
      _draft = overlayShiftDraft(_draft, editsWithoutBase(current));
    } else {
      _base = base;
      _draft = computeShiftDraft(base: base, current: current);
    }
    if (vacationBase != null) {
      _vacationBase = vacationBase;
      _vacationDraft = computeVacationDraft(base: vacationBase, current: vacationCurrent);
    }
    // dispose の中で呼ばれる。ウィジェットツリーのロック中に通知すると例外になるので遅らせる
    scheduleMicrotask(_publish);
  }

  /// 詳細確認での編集を預かる
  /// 基準がなければ（確定できて clear したあとも）何もしない
  void captureDetails(Map<DateTime, ShiftPatternModel> current) {
    final base = _base;
    if (base == null) return;
    _draft = computeShiftDraft(base: base, current: current);
    _publish();
  }

  /// N140 3/4：詳細確認でシフトを変えたときの、その日の有休・半休の日数を預かる
  /// 有休の基準がなければ（確定できて clear したあとも）何もしない
  void applyDetailVacationEdit(DateTime date, double? days) {
    final base = _vacationBase;
    if (base == null) return;
    final entries = Map<DateTime, VacationDraftEntry>.of(_vacationDraft.entries);
    final baseDays = base[date];
    if (days == baseDays) {
      entries.remove(date);
    } else {
      entries[date] = VacationDraftEntry(days: days, baseDays: baseDays);
    }
    _vacationDraft = VacationDraft(entries);
    _publish();
  }

  /// 確定できたとき・破棄したときに空にする
  void clear() {
    _draft = const ShiftDraft();
    _base = null;
    _vacationDraft = const VacationDraft();
    _vacationBase = null;
    _publish();
  }

  void dispose() {
    _disposed = true;
    pendingCount.dispose();
  }
}
