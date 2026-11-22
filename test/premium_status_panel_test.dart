// N138＋N139 3：設定画面の「💳 プレミアム版ステータス」の欄（PremiumStatusPanel）
// 幅は 360dp の端末の設定画面の中（360 − 左右の余白 16×2 = 328）。テスト用のフォントは 1 文字 1em 四方
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/screens/premium_purchase_screen.dart';
import 'package:shiftsleep/services/about_app.dart';
import 'package:shiftsleep/widgets/premium_status_panel.dart';

/// 設定画面の中の幅（幅 360dp の端末）
const double _settingsWidth = 328;

/// ボタンと「ご利用中」の文字の大きさと行の高さ
const double _fontSize = 14;
const double _lineHeightRatio = 1.5;

const _footerKey = Key('footer');

void main() {
  final button = find.byType(ElevatedButton);

  /// 枠（枠線のある Container）
  final frame = find.byWidgetPredicate(
    (widget) => widget is Container && widget.decoration is BoxDecoration && (widget.decoration as BoxDecoration).border != null,
  );

  Future<void> pumpPanel(
    WidgetTester tester, {
    required bool isPremium,
    VoidCallback? onUpgrade,
    bool isLoading = false,
    double scale = 1.0,
    UrlOpener? opener,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: _settingsWidth,
                  child: PremiumStatusPanel(
                    isPremium: isPremium,
                    onUpgrade: onUpgrade,
                    isLoading: isLoading,
                    footer: const Text('footer', key: _footerKey),
                    opener: opener ?? (uri) async => true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 枠線の色
  Color frameColor(WidgetTester tester) {
    final decoration = tester.widget<Container>(frame).decoration! as BoxDecoration;
    return (decoration.border! as Border).top.color;
  }

  /// 区切りの文言が 1 行に収まっている（about_app_section_test と同じ判定）
  /// 幅が 1 行ぶん（文字数 × 文字の大きさ）あり、高さが 2 行ぶんより低い（行の高さは端数が丸められることがある）
  void expectOneLine(WidgetTester tester, String part, double scale) {
    final size = tester.getSize(find.text(part));
    expect(size.width, greaterThanOrEqualTo(part.length * _fontSize * scale - 0.01), reason: '「$part」が折り返している（幅）');
    expect(size.height, lessThan(_fontSize * scale * _lineHeightRatio * 1.5), reason: '「$part」が折り返している（高さ）');
  }

  test('区切りの文言をつなげると、ボタンと「ご利用中」の文言と同じ', () {
    expect(premiumUpgradeLabelParts.join(), premiumUpgradeLabel);
    expect(premiumInUseLabelParts.join(), premiumInUseLabel);
  });

  testWidgets('無料：「無料版」のバッジ・できること・ボタンが出て、「ご利用中」は出ない。枠は灰色', (tester) async {
    await pumpPanel(tester, isPremium: false, onUpgrade: () {});

    expect(find.text(premiumStatusSectionTitle), findsOneWidget);
    expect(find.text(premiumPlanFreeLabel), findsOneWidget);
    expect(find.text(premiumPlanPremiumLabel), findsNothing);
    expect(find.byIcon(Icons.info), findsOneWidget);
    expect(find.text(premiumBenefitsIntro), findsOneWidget);
    for (final benefit in premiumBenefits) {
      expect(find.text(benefit), findsOneWidget);
    }
    expect(button, findsOneWidget);
    for (final part in premiumInUseLabelParts) {
      expect(find.text(part), findsNothing);
    }
    expect(frameColor(tester), AppColors.borderDefault);
  });

  testWidgets('プレミアム：「プレミアム版 ✨」のバッジと「ご利用中」が出て、ボタンとできることは出ない。枠は緑', (tester) async {
    await pumpPanel(tester, isPremium: true, onUpgrade: () {});

    expect(find.text(premiumPlanPremiumLabel), findsOneWidget);
    expect(find.text(premiumPlanFreeLabel), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    for (final part in premiumInUseLabelParts) {
      expect(find.text(part), findsOneWidget);
    }
    expect(button, findsNothing);
    expect(find.text(premiumBenefitsIntro), findsNothing);
    expect(frameColor(tester), Colors.green);
  });

  testWidgets('P2：ボタンの文字に値段がない', (tester) async {
    await pumpPanel(tester, isPremium: false, onUpgrade: () {});
    final price = RegExp(r'[¥円0-9０-９]|/月|／月');

    expect(premiumUpgradeLabel.contains(price), isFalse);
    final texts = tester.widgetList<Text>(find.descendant(of: button, matching: find.byType(Text)));
    expect(texts.map((text) => text.data), premiumUpgradeLabelParts);
    for (final text in texts) {
      expect(text.data!.contains(price), isFalse, reason: text.data);
    }
  });

  testWidgets('押すと onUpgrade が 1 回呼ばれる', (tester) async {
    var pressed = 0;
    await pumpPanel(tester, isPremium: false, onUpgrade: () => pressed++);

    await tester.tap(button);
    await tester.pump();

    expect(pressed, 1);
  });

  testWidgets('onUpgrade が null なら押せない', (tester) async {
    await pumpPanel(tester, isPremium: false, onUpgrade: null);

    expect(tester.widget<ElevatedButton>(button).enabled, isFalse);
  });

  testWidgets('isLoading のときは、ぐるぐるが出て文字は出ない', (tester) async {
    await pumpPanel(tester, isPremium: false, onUpgrade: null, isLoading: true);

    expect(find.descendant(of: button, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    for (final part in premiumUpgradeLabelParts) {
      expect(find.text(part), findsNothing);
    }
  });

  testWidgets('footer は枠の中の一番下に出る（無料・プレミアム）', (tester) async {
    for (final isPremium in [false, true]) {
      await pumpPanel(tester, isPremium: isPremium, onUpgrade: () {});
      final above = isPremium ? find.text(premiumInUseLabelParts.first) : button;
      final footerRect = tester.getRect(find.byKey(_footerKey));
      final frameRect = tester.getRect(frame);

      expect(find.descendant(of: frame, matching: find.byKey(_footerKey)), findsOneWidget, reason: '$isPremium');
      expect(footerRect.top, greaterThanOrEqualTo(tester.getRect(above).bottom), reason: '$isPremium');
      expect(footerRect.bottom, lessThanOrEqualTo(frameRect.bottom), reason: '$isPremium');
    }
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('無料・幅 360dp・倍率 $scale：はみ出しの例外がなく、ボタンの区切りがそれぞれ 1 行に収まる', (tester) async {
      await pumpPanel(tester, isPremium: false, onUpgrade: () {}, scale: scale);
      expect(tester.takeException(), isNull);
      for (final part in premiumUpgradeLabelParts) {
        expectOneLine(tester, part, scale);
      }
    });
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('プレミアム・幅 360dp・倍率 $scale：はみ出しの例外がなく、「ご利用中」の区切りがそれぞれ 1 行に収まる', (tester) async {
      await pumpPanel(tester, isPremium: true, onUpgrade: () {}, scale: scale);
      expect(tester.takeException(), isNull);
      for (final part in premiumInUseLabelParts) {
        expectOneLine(tester, part, scale);
      }
    });
  }

  testWidgets('P2：倍率 1.0 では、ボタンの 2 つの区切りが同じ行に並ぶ（全体が 1 行）', (tester) async {
    await pumpPanel(tester, isPremium: false, onUpgrade: () {});

    final first = tester.getRect(find.text(premiumUpgradeLabelParts.first));
    final second = tester.getRect(find.text(premiumUpgradeLabelParts.last));
    expect(second.top, closeTo(first.top, 0.01));
    expect(second.left, greaterThanOrEqualTo(first.right - 0.01));
  });

  testWidgets('読み上げ：ボタンは「✨ プレミアム版にアップグレード」の 1 つにまとまる', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPanel(tester, isPremium: false, onUpgrade: () {});

    expect(find.bySemanticsLabel(premiumUpgradeLabel), findsOneWidget);
    for (final part in premiumUpgradeLabelParts) {
      expect(find.bySemanticsLabel(part), findsNothing);
    }
    handle.dispose();
  });

  // 4c：プレミアムのときの［定期購入の管理］（Google Play の定期購入の画面へのリンク）
  group('4c：定期購入の管理のリンク', () {
    final link = find.text(manageSubscriptionLabelParts.first);

    testWidgets('プレミアム：「ご利用中」の下・footer の上に、区切りの文言と ↗ のリンクが出る', (tester) async {
      await pumpPanel(tester, isPremium: true, onUpgrade: () {});

      for (final part in manageSubscriptionLabelParts) {
        expect(find.text(part), findsOneWidget);
      }
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      expect(find.byIcon(Icons.subscriptions_outlined), findsOneWidget);
      final linkRect = tester.getRect(link);
      expect(linkRect.top, greaterThanOrEqualTo(tester.getRect(find.text(premiumInUseLabelParts.last)).bottom));
      expect(tester.getRect(find.byKey(_footerKey)).top, greaterThanOrEqualTo(linkRect.bottom));
      expect(find.descendant(of: frame, matching: link), findsOneWidget);
    });

    testWidgets('無料：リンクは出ない', (tester) async {
      await pumpPanel(tester, isPremium: false, onUpgrade: () {});

      for (final part in manageSubscriptionLabelParts) {
        expect(find.text(part), findsNothing);
      }
      expect(find.byIcon(Icons.open_in_new), findsNothing);
    });

    testWidgets('押すと定期購入の画面の URL を 1 回開き、SnackBar は出ない', (tester) async {
      final opened = <Uri>[];
      await pumpPanel(tester, isPremium: true, onUpgrade: () {}, opener: (uri) async {
        opened.add(uri);
        return true;
      });

      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(opened, [Uri.parse(playSubscriptionsUrl)]);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('D38 A：開けなかったら、URL つきの ⚠️ をオレンジで出す（［コピー］つき）', (tester) async {
      await pumpPanel(tester, isPremium: true, onUpgrade: () {}, opener: (uri) async => false);

      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.text(manageSubscriptionOpenFailedText), findsOneWidget);
      expect(manageSubscriptionOpenFailedText, contains(playSubscriptionsUrl));
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.orange);
      expect(find.text(copyUrlActionLabel), findsOneWidget);
    });

    testWidgets('倍率 1.0：リンクの区切りがそれぞれ 1 行に収まる', (tester) async {
      await pumpPanel(tester, isPremium: true, onUpgrade: () {});

      for (final part in manageSubscriptionLabelParts) {
        expectOneLine(tester, part, 1.0);
      }
    });

    testWidgets('読み上げ：リンクは「Google Play で定期購入を管理する」の 1 つにまとまり、↗ は「外部のブラウザで開きます」', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPanel(tester, isPremium: true, onUpgrade: () {});

      // about_app_section_test と同じく、行の読み上げは ↗ の文と 1 つの節にまとまるので RegExp で探す
      expect(find.bySemanticsLabel(RegExp(manageSubscriptionLabel)), findsOneWidget);
      for (final part in manageSubscriptionLabelParts) {
        expect(find.bySemanticsLabel(part), findsNothing);
      }
      expect(find.bySemanticsLabel(RegExp(externalLinkSemanticLabel)), findsOneWidget);
      handle.dispose();
    });
  });
}
