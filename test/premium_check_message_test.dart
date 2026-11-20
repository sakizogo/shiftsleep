// N191 3/3：［アップグレード］で確かめたあとの SnackBar の出し分け（Provider の値で決める。D15 B）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/premium_check_message.dart';

void main() {
  test('プレミアム → 「✨ プレミアム版をご利用中です！」と緑', () {
    final message = premiumCheckMessage(true);
    expect(message.text, '✨ プレミアム版をご利用中です！');
    expect(message.text, premiumCheckPremiumText);
    expect(message.color, Colors.green);
  });

  test('無料 → 「無料版をご利用中です。…」と青', () {
    final message = premiumCheckMessage(false);
    expect(message.text, '無料版をご利用中です。プレミアム版でさらに多くの機能をご利用いただけます。');
    expect(message.text, premiumCheckFreeText);
    expect(message.color, Colors.blue);
  });
}
