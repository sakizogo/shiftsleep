import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/screens/home_screen.dart';
import 'package:shiftsleep/services/sleep_debt.dart';

// N198 2/2：ホームの睡眠負債のカード（色・計算できないときの文・目標の表示）

/// 明るさの差（WCAG のコントラスト比）
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('sleepDebtCardColors', () {
    test('要注意は朱色系、改善推奨はオレンジ系の枠', () {
      expect(sleepDebtCardColors(SleepDebtLevel.alert).border, const Color(0xFFD55E00));
      expect(sleepDebtCardColors(SleepDebtLevel.improve).border, const Color(0xFFE69F00));
    });

    test('少し不足・十分・判定できないは同じ灰色系', () {
      final neutral = sleepDebtCardColors(SleepDebtLevel.enough);
      for (final level in [SleepDebtLevel.slight, SleepDebtLevel.notJudgeable]) {
        final colors = sleepDebtCardColors(level);
        expect(colors.border, neutral.border);
        expect(colors.background, neutral.background);
        expect(colors.text, neutral.text);
      }
    });

    test('段階ごとに枠の色が違う（要注意・改善推奨・灰色）', () {
      final borders = {
        sleepDebtCardColors(SleepDebtLevel.alert).border,
        sleepDebtCardColors(SleepDebtLevel.improve).border,
        sleepDebtCardColors(SleepDebtLevel.enough).border,
      };
      expect(borders.length, 3);
    });

    test('文字と背景の明るさの差はどの段階も 4.5:1 以上', () {
      for (final level in SleepDebtLevel.values) {
        final colors = sleepDebtCardColors(level);
        expect(contrast(colors.text, colors.background), greaterThanOrEqualTo(4.5), reason: '$level');
      }
    });
  });

  group('sleepDebtUnavailableText', () {
    test('0 日は記録がない文', () {
      expect(sleepDebtUnavailableText(0), '直近4週間の記録がないため、睡眠負債を計算できません。');
    });

    test('1〜6 日は日数つき', () {
      expect(sleepDebtUnavailableText(1), '記録のある日が 7 日以上になると計算できます（いまは 1 日）。');
      expect(sleepDebtUnavailableText(6), '記録のある日が 7 日以上になると計算できます（いまは 6 日）。');
    });
  });

  test('目標は定数から 7h 00m の形', () {
    expect(formatSleepDebtTarget(sleepDebtTarget), '7h 00m');
    expect(formatSleepDebtTarget(const Duration(hours: 6, minutes: 5)), '6h 05m');
  });

  test('※の一言', () {
    expect(sleepDebtCapNote, '※寝すぎた日の分は 1 日 1 時間までしか差し引いていません');
  });
}
