import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shiftsleep/database/database_helper.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'package:shiftsleep/services/wake_up_service.dart';
import 'screens/home_screen.dart';


// N26：Test Store のキーは release で使うと SDK がアプリを閉じるので、デバッグ版だけで使う
const String _revenueCatTestApiKey = 'test_UbjlWenDYu2XCqxFqxQpEWCJcZpH';
// N26：Google Play 用のキー（goog_）。発行するまでは空のままで、その間はプレミアムなしで動く
const String _revenueCatProductionApiKey = '';

void main() {
  // N26：ensureInitialized と runApp が同じ Zone に入るよう、起動処理を丸ごと包む
  runZoned<Future<void>>(
    _startApp,
    zoneSpecification: kDebugMode
        ? null
        : ZoneSpecification(print: (self, parent, zone, line) {}),
  );
}

Future<void> _startApp() async {
  // N26：デバッグ版以外（release・profile）では print と debugPrint を止める（print は main の Zone で止める）
  if (!kDebugMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  WidgetsFlutterBinding.ensureInitialized();

  const revenueCatApiKey =
      kDebugMode ? _revenueCatTestApiKey : _revenueCatProductionApiKey;
  // N26：キーが空なら configure しない（PremiumService が Purchases.isConfigured を見て無料版として扱う）
  if (revenueCatApiKey.isEmpty) {
    debugPrint('[main] ℹ️ RevenueCat のキーが空のため configure しません');
  } else {
    try {
      await Purchases.configure(
        PurchasesConfiguration(
          revenueCatApiKey,
        ),
      );
      debugPrint('[main] ✅ RevenueCat initialized');
    } catch (e) {
      print('[main] ❌ RevenueCat initialization failed: $e');
    }
  }


  try {
    await AlarmService.initialize();
    print('[main] ✅ AlarmService initialized successfully');
  } catch (e) {
    print('[main] ❌ AlarmService initialization failed: $e');
  }

  // N126：force-stop などで消えたアラームを控えから登録し直す（失敗しても起動は止めない）
  await AlarmService.restoreSavedAlarms();

  // ========== Week 14 追加：日本語ロケール初期化 ==========
  try {
    await initializeDateFormatting('ja_JP');
    print('[main] ✅ DateFormatting initialized for ja_JP');
  } catch (e) {
    print('[main] ⚠️ DateFormatting initialization failed: $e');
  }
  // ================================================================
  
  runApp(const MyApp());
}

// ========== Week 8 Phase 4 修正: MultiProvider を MyApp の外側に配置 ==========
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // SleepRepository を登録
        Provider<SleepRepository>(
          create: (_) => SleepRepository(),
        ),
        // SleepProvider を登録（SleepRepository に依存）
        ChangeNotifierProxyProvider<SleepRepository, SleepProvider>(
          create: (context) => SleepProvider(
            context.read<SleepRepository>(),
          ),
          update: (context, sleepRepository, previous) =>
              previous ?? SleepProvider(sleepRepository),
        ),
      ],
      child: MaterialApp(
        title: 'ShiftSleep',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const _HomeScreenWrapper(),  // ← 元に戻す
        // home: const _HomeScreenWrapper(),  // ← 元の画面（コメントアウト）
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

// ========== Week 8 Phase 4 追加: ホーム画面ラッパー（ここで初期化を実行） ==========
class _HomeScreenWrapper extends StatefulWidget {
  const _HomeScreenWrapper({Key? key}) : super(key: key);

  @override
  State<_HomeScreenWrapper> createState() => _HomeScreenWrapperState();
}

class _HomeScreenWrapperState extends State<_HomeScreenWrapper> {
  @override
  void initState() {
    super.initState();
    
    // ========== Week 8 Phase 4 追加: アプリ起動時に睡眠状態を復元 ==========
    _initializeSleep();
  }

  /// 睡眠状態を復元
  Future<void> _initializeSleep() async {
    print('[_HomeScreenWrapperState] 🛏️  睡眠状態の初期化を開始...');
    
    // ここで MultiProvider が存在するので、SleepProvider にアクセス可能
    await Future.delayed(Duration(milliseconds: 500), () async {
      try {
        final sleepProvider = 
          Provider.of<SleepProvider>(context, listen: false);
        // await の前に取得（通知停止で起床した場合の SnackBar 用）
        final messenger = ScaffoldMessenger.of(context);
        await sleepProvider.initializeSleepState();
        print('[_HomeScreenWrapperState] ✅ 睡眠状態の初期化完了');

        // ========== 通知の「停止」ボタンで保存された停止時刻で起床処理 ==========
        final result = await WakeUpService.processPendingAlarmStop(sleepProvider);
        if (result != PendingAlarmStopResult.notProcessed) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('⏰ アラーム停止時刻で起床を記録しました'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        // N19：起床は記録できているので、続けて知らせる
        if (result == PendingAlarmStopResult.wokeButAlarmCancelFailed) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(alarmCancelFailedText),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 6),
            ),
          );
        }
        // ======================================================================
      } catch (e) {
        print('[_HomeScreenWrapperState] ❌ 睡眠状態の初期化エラー: $e');
      }
    });
  }
  // ======================================================================

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
// ====================================================================================