// プレミアム表示の切り替え（テスト用。A-3 3/3）
//
// デバッグ版（kDebugMode）のときだけ設定画面に出し、押すと SleepProvider.togglePremiumStatusForTest を呼ぶ
// リリース版では何も出さない（SizedBox.shrink）
// デバッグ版では、切り替えた値をもう一度押すまで保つ（loadAllSleepData などで PremiumService の値に戻らない。F6）
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';

/// ボタンの文字
const String premiumDebugToggleLabel = '🧪 プレミアム表示の切り替え（テスト用）';

/// 切り替えたあとの SnackBar の文
String premiumDebugToggledText(bool isPremium) => '🧪 プレミアム表示：${isPremium ? 'プレミアム' : '無料'}';

class PremiumDebugToggleButton extends StatelessWidget {
  const PremiumDebugToggleButton({super.key, this.visible = kDebugMode});

  /// 出すか（既定は kDebugMode。テストで false にできる）
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final isPremium = context.watch<SleepProvider>().isPremiumUser;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () {
            final provider = context.read<SleepProvider>();
            provider.togglePremiumStatusForTest();
            final messenger = ScaffoldMessenger.of(context);
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(content: Text(premiumDebugToggledText(provider.isPremiumUser))),
            );
          },
          child: Text('$premiumDebugToggleLabel　今：${isPremium ? 'プレミアム' : '無料'}'),
        ),
      ),
    );
  }
}
