// N210：設定画面の「ℹ️ このアプリについて」の欄
// 幅は 360dp の端末の設定画面の中（360 − 左右の余白 16×2 = 328）。テスト用のフォントは 1 文字 1em 四方
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/about_app.dart';
import 'package:shiftsleep/widgets/about_app_section.dart';

/// 設定画面の中の幅（幅 360dp の端末）
const double _settingsWidth = 328;

/// 行の文字の大きさと行の高さ
const double _fontSize = 14;
const double _lineHeightRatio = 1.5;

void main() {
  /// 押す行（ListTile 全体）
  final row = find.byType(ListTile);

  Future<void> pumpSection(WidgetTester tester, UrlOpener opener, {double scale = 1.0}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: _settingsWidth, child: AboutAppSection(opener: opener)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 区切りの文言が 1 行に収まっている（action_tip_locked_label_test と同じ判定）
  /// 幅が 1 行ぶん（文字数 × 文字の大きさ）あり、高さが 2 行ぶんより低い（行の高さは端数が丸められることがある）
  void expectOneLine(WidgetTester tester, String part, double scale) {
    final size = tester.getSize(find.text(part));
    expect(size.width, greaterThanOrEqualTo(part.length * _fontSize * scale - 0.01), reason: '「$part」が折り返している（幅）');
    expect(size.height, lessThan(_fontSize * scale * _lineHeightRatio * 1.5), reason: '「$part」が折り返している（高さ）');
  }

  test('区切りの文言をつなげると privacyPolicyLabel と同じ', () {
    expect(privacyPolicyLabelParts.join(), privacyPolicyLabel);
  });

  testWidgets('見出し・「プライバシーポリシー」の行・外部リンクのアイコンが出る', (tester) async {
    await pumpSection(tester, (uri) async => true);
    expect(find.text(aboutAppSectionTitle), findsOneWidget);
    for (final part in privacyPolicyLabelParts) {
      expect(find.text(part), findsOneWidget);
    }
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('幅 360dp・倍率 $scale：区切りごとに 1 行に収まり、はみ出しの例外が出ない', (tester) async {
      await pumpSection(tester, (uri) async => true, scale: scale);
      expect(tester.takeException(), isNull);
      for (final part in privacyPolicyLabelParts) {
        expectOneLine(tester, part, scale);
      }
    });
  }

  testWidgets('読み上げは「プライバシーポリシー」の 1 つにまとまり、↗ は「外部のブラウザで開きます」', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSection(tester, (uri) async => true);
    expect(find.bySemanticsLabel(RegExp(privacyPolicyLabel)), findsOneWidget);
    for (final part in privacyPolicyLabelParts) {
      expect(find.bySemanticsLabel(part), findsNothing);
    }
    expect(find.bySemanticsLabel(RegExp(externalLinkSemanticLabel)), findsOneWidget);
    handle.dispose();
  });

  testWidgets('行を押すと URL を開き、SnackBar は出さない', (tester) async {
    final opened = <Uri>[];
    await pumpSection(tester, (uri) async {
      opened.add(uri);
      return true;
    });
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse(privacyPolicyUrl)]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('開けなかったら、URL つきの ⚠️ をオレンジで出す（［コピー］つき）', (tester) async {
    await pumpSection(tester, (uri) async => false);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text(privacyPolicyOpenFailedText), findsOneWidget);
    expect(privacyPolicyOpenFailedText, contains(privacyPolicyUrl));
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.backgroundColor, Colors.orange);
    expect(snackBar.duration, const Duration(seconds: 6));
    expect(find.text(copyUrlActionLabel), findsOneWidget);
  });

  testWidgets('開く関数が例外を出しても同じ ⚠️ で、例外の文字は出さない', (tester) async {
    await pumpSection(tester, (uri) async => throw Exception('secret detail'));
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text(privacyPolicyOpenFailedText), findsOneWidget);
    expect(find.textContaining('secret detail'), findsNothing);
  });

  testWidgets('［コピー］を押すと URL をクリップボードに入れ、「✅ URL をコピーしました」を出す', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpSection(tester, (uri) async => false);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text(copyUrlActionLabel));
    await tester.pumpAndSettle();

    expect(copied, privacyPolicyUrl);
    expect(find.text(urlCopiedText), findsOneWidget);
    expect(find.text(privacyPolicyOpenFailedText), findsNothing);
  });

  testWidgets('開いている途中にもう一度押しても、開く関数は 1 回だけ', (tester) async {
    var calls = 0;
    final completer = Completer<bool>();
    await pumpSection(tester, (uri) {
      calls++;
      return completer.future;
    });
    await tester.tap(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
    expect(calls, 1);

    completer.complete(true);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump();
    expect(calls, 2);
  });
}
