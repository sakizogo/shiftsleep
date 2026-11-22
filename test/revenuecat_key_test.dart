// N138＋N139 5a：RevenueCat の API キーの選び方（revenueCatApiKeyFor）
// デバッグ版は Test Store（test_）、それ以外は Google Play（goog_）。貼り間違いを防ぐ
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/revenuecat_key.dart';

void main() {
  test('デバッグ版は Test Store のキー（test_ で始まる）', () {
    expect(revenueCatApiKeyFor(debug: true), startsWith('test_'));
  });

  test('デバッグ版以外は Google Play のキー（goog_ で始まり、空ではなく、test_ で始まらない）', () {
    final key = revenueCatApiKeyFor(debug: false);

    expect(key, isNotEmpty);
    expect(key, startsWith('goog_'));
    expect(key, isNot(startsWith('test_')));
  });
}
