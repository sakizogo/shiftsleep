import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shiftsleep/database/database_helper.dart';
import 'package:shiftsleep/providers/sleep_provider.dart';
import 'package:shiftsleep/repositories/sleep_repository.dart';
import 'package:shiftsleep/services/alarm_service.dart';  // ✅ 追加
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await AlarmService.initialize();  // ← () を削除
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