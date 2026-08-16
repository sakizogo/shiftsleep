import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';  // ========== Week 7 Phase 3 追加 ==========
import 'package:shiftsleep/database/database_helper.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';
import 'screens/home_screen.dart';

// ========== Week 7 Phase 3: RevenueCat API キー（テスト環境） ==========
// 本番環境では environment variable から読み込むことを推奨
const String REVENUECAT_API_KEY = 'test_UbjlWenDYu2XCqxFqxQpEWCJcZpH';
// ====================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ========== Week 7 Phase 3: RevenueCat 初期化 ==========
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
  // ====================================================
  
  try {
    await AlarmService.initialize();
    print('[main] ✅ AlarmService initialized successfully');
  } catch (e) {
    print('[main] ❌ AlarmService initialization failed: $e');
  }
  
  runApp(const MyApp());
}

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
        home: const HomeScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}