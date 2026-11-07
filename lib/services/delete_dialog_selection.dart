// N140 4/4：長押しの削除ダイアログで、最初にどの項目へチェックを入れるか・案内を出すか

/// 案内の文言（チェックが 0 個のあいだ、項目の下に出す）
const String deleteSelectionHint = 'ℹ️ 削除するものにチェックを入れてください';

/// 最初にチェックを入れる項目
/// 項目が 1 つならその 1 つ（今までどおり）、2 つ以上なら全部チェックなし（消しすぎを防ぐ）
/// 返すのは毎回新しい Set（ダイアログの中で足したり外したりしてよい）
Set<String> initialDeleteSelection(Iterable<String> keys) {
  final list = keys.toList();
  return list.length == 1 ? {list.single} : <String>{};
}

/// 「削除するものにチェックを入れてください」を出すか（チェックが 0 個のあいだだけ）
bool showDeleteSelectionHint(Set<String> selected) => selected.isEmpty;
