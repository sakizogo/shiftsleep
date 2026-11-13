// N180 2/3：起床のテストで WakeUpService.shiftRepositoryForTest に入れる、DB の偽物
//
// 何も入れなければ「設定の行なし（30 分）・シフトなし」（pre は取り消さない）
// rows は範囲を見ずにそのまま返す（どの日を読んでも同じ行）
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/models/shift_pattern_model.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';

class FakeShiftRepository extends ShiftRepository {
  AppSettings? settings;
  List<Map<String, dynamic>> rows = [];
  ShiftPatternModel? pattern;
  bool failRead = false;  // 設定・シフト・パターンの読み込みをすべて例外にする

  @override
  Future<AppSettings?> getAppSettings(String userId) async {
    if (failRead) throw Exception('settings read failed');
    return settings;
  }

  @override
  Future<List<Map<String, dynamic>>> getShiftsForDateRange(DateTime startDate, DateTime endDate) async {
    if (failRead) throw Exception('shifts read failed');
    return rows;
  }

  @override
  Future<ShiftPatternModel?> getPatternById(String patternId) async {
    if (failRead) throw Exception('pattern read failed');
    return pattern;
  }
}
