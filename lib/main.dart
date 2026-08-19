import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shiftsleep/database/database_helper.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'screens/home_screen.dart';

const String REVENUECAT_API_KEY = 'test_UbjlWenDYu2XCqxFqxQpEWCJcZpH';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Purchases.configure(
      PurchasesConfiguration(
        REVENUECAT_API_KEY,
      ),
    );
    print('[main] ✅ RevenueCat initialized successfully with API Key: $REVENUECAT_API_KEY');
  } catch (e) {
    print('[main] ❌ RevenueCat initialization failed: $e');
  }
  
  try {
    await AlarmService.initialize();
    print('[main] ✅ AlarmService initialized successfully');
  } catch (e) {
    print('[main] ❌ AlarmService initialization failed: $e');
  }
  
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
        home: const _HomeScreenWrapper(),  // ← ホーム画面をラッパーに
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
        await sleepProvider.initializeSleepState();
        print('[_HomeScreenWrapperState] ✅ 睡眠状態の初期化完了');
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