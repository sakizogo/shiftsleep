// N210：プライバシーポリシーの URL と、開く処理（開く関数は偽物に差し替える）
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/about_app.dart';

void main() {
  test('URL は https・sites.google.com・/view/shiftsleep-privacy', () {
    final uri = Uri.parse(privacyPolicyUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, 'sites.google.com');
    expect(uri.path, '/view/shiftsleep-privacy');
  });

  test('開けたら true で、開く関数にその URL が渡る', () async {
    final opened = <Uri>[];
    final result = await openPrivacyPolicy(open: (uri) async {
      opened.add(uri);
      return true;
    });
    expect(result, isTrue);
    expect(opened, [Uri.parse(privacyPolicyUrl)]);
  });

  test('開く関数が false なら false', () async {
    expect(await openPrivacyPolicy(open: (uri) async => false), isFalse);
  });

  test('開く関数が例外を出しても外に出さず false', () async {
    expect(await openPrivacyPolicy(open: (uri) async => throw Exception('no browser')), isFalse);
  });
}
