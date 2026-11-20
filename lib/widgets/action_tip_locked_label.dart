// P1：実行ヒントの 🔒 の案内（「実行ヒント（プレミアム版で解放）」）の行
//
// ホームと改善アドバイスの詳細のダイアログで共通（外側の囲みは、それぞれの画面に残す）
// - 文言は actionTipLockedParts の区切りで Wrap に並べ、大きい文字でも区切りの中ではできるだけ割らない（D17 B）
// - 区切り 1 つが 1 行に入らないときは、その中でふつうに折り返す（D18 A）
// - 🔒 は 16px のまま（D19 A）。何行になっても 1 行目の高さの真ん中に置く
// - 読み上げは actionTipLockedLabel の 1 つにまとめる（区切りごとに切れて読まれないように）
import 'package:flutter/material.dart';
import 'package:shiftsleep/constants/colors.dart';
import 'package:shiftsleep/constants/text_styles.dart';
import 'package:shiftsleep/services/sleep_advisory_service.dart';

class ActionTipLockedLabel extends StatelessWidget {
  const ActionTipLockedLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.descriptionStyle.copyWith(color: AppColors.textSecondary);
    // 1 行目の高さ（文字の大きさ × 倍率 × 行の高さ）
    final lineHeight = MediaQuery.textScalerOf(context).scale(style.fontSize!) * (style.height ?? 1.0);
    return Semantics(
      label: actionTipLockedLabel,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: lineHeight,
            child: const Center(
              child: Icon(Icons.lock, size: 16, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Wrap(
              children: [for (final part in actionTipLockedParts) Text(part, style: style)],
            ),
          ),
        ],
      ),
    );
  }
}
