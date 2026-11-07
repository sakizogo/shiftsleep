// シフト管理の未確定の差分（N140）
//
// DB から読めた内容（基準）と画面の内容を比べて、追加・変更・削除を差分にする
// 読み直したときは、DB の新しい内容の上に差分を重ねる
// 差分は ShiftDraftStore に入れて home_screen が持つ（シフト管理画面の State が作り直されても残る）
// DB・画面には依存しない
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
String? draftMergeNotice(ShiftDraftMergeResult result) {
  final lines = <String>[
    if (result.removedDates.isNotEmpty)
      '⚠️ 削除されたパターンの未確定シフト ${result.removedDates.length}日分を外しました',
    if (result.conflictDates.isNotEmpty)
      '⚠️ 別の画面で変更された日の未確定シフト ${result.conflictDates.length}日分は、未確定の内容を残しました',
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

/// 未確定の差分の置き場所（home_screen が 1 つ持つ）
class ShiftDraftStore {
  ShiftDraft _draft = const ShiftDraft();
  Map<DateTime, ShiftPatternModel>? _base;

  ShiftDraft get draft => _draft;

  /// シフト管理画面の State が消えるときに、その内容を預かる
  /// base が null（この State で一度も読めていない）なら、入れた分だけを今の差分に重ねる
  void saveFromScreen({
    required Map<DateTime, ShiftPatternModel>? base,
    required Map<DateTime, ShiftPatternModel> current,
  }) {
    if (base == null) {
      _draft = overlayShiftDraft(_draft, editsWithoutBase(current));
      return;
    }
    _base = base;
    _draft = computeShiftDraft(base: base, current: current);
  }

  /// State が消えたあとに終わった期間指定の分を重ねる
  void addLateEdits(ShiftDraft edits) {
    _draft = overlayShiftDraft(_draft, edits);
  }

  /// 詳細確認画面からタブを移動するときに、詳細確認での編集を預かる
  /// 基準がなければ（確定できて clear したあとも）何もしない
  void captureDetails(Map<DateTime, ShiftPatternModel> current) {
    final base = _base;
    if (base == null) return;
    _draft = computeShiftDraft(base: base, current: current);
  }

  /// 確定できたら空にする
  void clear() {
    _draft = const ShiftDraft();
    _base = null;
  }
}
