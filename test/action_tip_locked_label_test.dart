// P1：実行ヒントの 🔒 の案内が、大きい文字（font_scale 1.3・2.0）でも区切りの中で割れない
// テスト用のフォントは 1 文字 1em 四方なので、幅と高さで 1 行かどうかを確かめる（sleep_button_text_scale_test と同じ）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/sleep_advisory_service.dart';
import 'package:shiftsleep/widgets/action_tip_locked_label.dart';

/// 文字の大きさ（descriptionStyle）と行の高さ
const double _fontSize = 13;
const double _lineHeightRatio = 1.5;

/// ホームの囲みの中の幅（幅 360dp の端末：360 − 20×2 − 16×2 − 12×2）
const double _homeWidth = 264;

/// 詳細のダイアログの囲みの中の幅（幅 360dp の端末：360 − 40×2 − 24×2 − (12＋1)×2）
const double _dialogWidth = 206;

void main() {
  Future<void> pumpLabel(WidgetTester tester, {required double width, required double scale}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: const ActionTipLockedLabel()),
            ),
          ),
        ),
      ),
    );
  }

  /// 区切りの文言が 1 行に収まっている
  /// 幅が 1 行ぶん（文字数 × 文字の大きさ）あり、高さが 2 行ぶんより低い（行の高さは端数が丸められることがある）
  void expectOneLine(WidgetTester tester, String part, double scale) {
    final size = tester.getSize(find.text(part));
    expect(size.width, greaterThanOrEqualTo(part.length * _fontSize * scale - 0.01), reason: '「$part」が折り返している（幅）');
    expect(size.height, lessThan(_fontSize * scale * _lineHeightRatio * 1.5), reason: '「$part」が折り返している（高さ）');
  }

  test('区切りの文言をつなげると、読み上げの文言と同じ', () {
    expect(actionTipLockedParts.join(), actionTipLockedLabel);
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('ホームの幅・倍率 $scale：どの区切りも 1 行に収まる', (tester) async {
      await pumpLabel(tester, width: _homeWidth, scale: scale);
      expect(tester.takeException(), isNull);
      for (final part in actionTipLockedParts) {
        expectOneLine(tester, part, scale);
      }
    });
  }

  testWidgets('ダイアログの幅・倍率 2.0：「解放）」は割れない（D18 A：「（プレミアム版で」の中は割れてよい）', (tester) async {
    await pumpLabel(tester, width: _dialogWidth, scale: 2.0);
    expect(tester.takeException(), isNull);
    expectOneLine(tester, '解放）', 2.0);
  });

  testWidgets('読み上げは 1 つにまとまり、文言は actionTipLockedLabel', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpLabel(tester, width: _homeWidth, scale: 1.3);
    expect(find.bySemanticsLabel(actionTipLockedLabel), findsOneWidget);
    for (final part in actionTipLockedParts) {
      expect(find.bySemanticsLabel(part), findsNothing);
    }
    handle.dispose();
  });

  testWidgets('倍率 2.0：🔒 は 1 行目の高さの真ん中にある', (tester) async {
    await pumpLabel(tester, width: _homeWidth, scale: 2.0);
    final lock = tester.getRect(find.byIcon(Icons.lock));
    final firstLine = tester.getRect(find.text(actionTipLockedParts.first));
    expect(lock.center.dy, closeTo(firstLine.center.dy, 0.01));
  });
}
