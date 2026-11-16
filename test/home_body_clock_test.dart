import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/screens/home_screen.dart';

// N196 A 2/2：ホームの「あなたの体内時計」の文は SJL だけで判定する

void main() {
  test('SJL が null なら、分けて寝る場合も含めて計算できない文', () {
    expect(
      bodyClockMessage(null),
      '記録が足りないか、寝る時刻がばらばらなため、体内時計のズレ（SJL）を計算できません。'
      '5時間未満に分けて寝ている場合も計算できません。',
    );
  });

  test('SJL の値で分ける（2 以上・1 以上・1 未満。境目はちょうどを含む）', () {
    expect(bodyClockMessage(2.0), startsWith('SJLが2時間以上'));
    expect(bodyClockMessage(1.0), startsWith('SJLが1時間以上'));
    expect(bodyClockMessage(1.99), startsWith('SJLが1時間以上'));
    expect(bodyClockMessage(0.0), startsWith('体内時計は正常範囲'));
  });
}
