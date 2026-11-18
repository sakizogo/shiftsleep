// N190：設定タブで出た SnackBar が、ほかのタブに移っても残らないようにする
//
// 設定画面の SnackBar はルートの ScaffoldMessenger に出るので、タブを切り替えても消えない。
// 設定タブから離れるときだけ clearSnackBars を呼ぶ（ほかのタブ間の移動では消さない）

/// タブを from から to に切り替えるとき、SnackBar を消すか
/// 設定タブから、設定以外のタブへ移るときだけ true
bool shouldClearSnackBarsOnTabChange({required int from, required int to}) {
  const settingsTabIndex = 2;  // 下のタブの並び：0 ホーム・1 シフト管理・2 設定・3 詳細
  return from == settingsTabIndex && to != settingsTabIndex;
}
