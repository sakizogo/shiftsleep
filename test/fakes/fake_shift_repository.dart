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

  // A-3 1/3：睡眠プランの読み込みのテスト用
  List<ShiftPatternModel> patterns = [];  // getAllPatterns が返すもの
  bool failSettings = false;  // 設定の読み込みだけを例外にする
  bool failShifts = false;  // シフトの読み込みだけを例外にする
  bool failPatterns = false;  // getAllPatterns だけを例外にする
  DateTime? lastRangeStart;  // getShiftsForDateRange に渡された範囲
  DateTime? lastRangeEnd;
  // A-4 1/3：getShiftsForDateRange に渡された範囲の始まり（呼んだ順）と、この始まりのときだけ例外にする
  final List<DateTime> rangeStarts = [];
  DateTime? failRangeStart;

  @override
  Future<AppSettings?> getAppSettings(String userId) async {
    if (failRead || failSettings) throw Exception('settings read failed');
    return settings;
  }

  @override
  Future<List<Map<String, dynamic>>> getShiftsForDateRange(DateTime startDate, DateTime endDate) async {
    lastRangeStart = startDate;
    lastRangeEnd = endDate;
    rangeStarts.add(startDate);
    if (failRead || failShifts || startDate == failRangeStart) throw Exception('shifts read failed');
    return rows;
  }

  @override
  Future<List<ShiftPatternModel>> getAllPatterns() async {
    if (failRead || failPatterns) throw Exception('patterns read failed');
    return patterns;
  }

  @override
  Future<ShiftPatternModel?> getPatternById(String patternId) async {
    if (failRead) throw Exception('pattern read failed');
    return pattern;
  }
}
