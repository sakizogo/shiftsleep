import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/screens/home_screen.dart';
import 'package:shiftsleep/services/body_clock_level.dart';

// N213：体内時計の段階・言葉・色（良い結果を赤系で出さない）

void main() {
  group('bodyClockLevel', () {
    test('SJL が null なら判定できない', () {
      expect(bodyClockLevel(null), BodyClockLevel.notJudgeable);
    });

    test('境目はちょうどの値を上の段階に入れる', () {
      expect(bodyClockLevel(2.0), BodyClockLevel.disrupted);
      expect(bodyClockLevel(5.0), BodyClockLevel.disrupted);
      expect(bodyClockLevel(1.99), BodyClockLevel.slightlyDisrupted);
      expect(bodyClockLevel(1.0), BodyClockLevel.slightlyDisrupted);
      expect(bodyClockLevel(0.99), BodyClockLevel.normal);
      expect(bodyClockLevel(0.0), BodyClockLevel.normal);
    });
  });

  test('段階の言葉', () {
    expect(bodyClockLevelLabel(BodyClockLevel.disrupted), '大きく乱れている');
    expect(bodyClockLevelLabel(BodyClockLevel.slightlyDisrupted), 'やや乱れている');
    expect(bodyClockLevelLabel(BodyClockLevel.normal), '正常範囲');
    expect(bodyClockLevelLabel(BodyClockLevel.notJudgeable), '判定できません');
  });

  group('bodyClockCardColors', () {
    test('大きく乱れている＝朱色、やや乱れている＝オレンジ', () {
      expect(bodyClockCardColors(BodyClockLevel.disrupted).border, const Color(0xFFD55E00));
      expect(bodyClockCardColors(BodyClockLevel.slightlyDisrupted).border, const Color(0xFFE69F00));
    });

    test('正常範囲・判定できないは灰色（赤系にしない）', () {
      for (final level in [BodyClockLevel.normal, BodyClockLevel.notJudgeable]) {
        final colors = bodyClockCardColors(level);
        expect(colors.background, const Color(0xFFF5F5F5));
        expect(colors.border, const Color(0xFF9E9E9E));
      }
    });
  });

  test('段階ごとにアイコンが違う（色だけに頼らない）', () {
    final icons = BodyClockLevel.values.map(bodyClockIcon).toSet();
    expect(icons.length, BodyClockLevel.values.length);
    expect(bodyClockIcon(BodyClockLevel.normal), Icons.check_circle_outline);
  });
}
