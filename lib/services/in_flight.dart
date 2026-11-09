// N160：同じ key の処理を 1 回にまとめる（N62 の自動生成で使う）
//
// DB・画面には依存しない

/// 同じ key の処理が走っているあいだは、新しく走らせずに同じ Future を返す（N62・N160）
/// 終わったら（成功でも失敗でも）inFlight から消す。結果も例外も、そのまま呼び出し元に届く
Future<T> runOnce<T>(
  Map<String, Future<T>> inFlight,
  String key,
  Future<T> Function() start,
) {
  final running = inFlight[key];
  if (running != null) return running;
  final future = start().whenComplete(() {
    // N160：戻り値を返さない（=> で remove の戻り値を返すと、自分自身を待って終わらなくなる）
    inFlight.remove(key);
  });
  inFlight[key] = future;
  return future;
}
