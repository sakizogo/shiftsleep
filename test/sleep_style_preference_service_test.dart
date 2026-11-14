// A-2 4/4：寝方のタイプの設定の保存（SleepStylePreferenceService）のテスト
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shiftsleep/services/sleep_plan.dart';
import 'package:shiftsleep/services/sleep_style_preference_service.dart';

/// 端末のファイルの偽物。読み込み・書き込みを失敗させられる
class _FakeStore extends SharedPreferencesStorePlatform {
  _FakeStore(Map<String, Object> initial)
      : data = {for (final entry in initial.entries) 'flutter.${entry.key}': entry.value};

  final Map<String, Object> data;
  bool throwOnRead = false;
  bool failWrite = false;
  bool throwOnWrite = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (throwOnWrite) throw PlatformException(code: 'WRITE_FAILED');
    if (failWrite) return false;
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (throwOnRead) throw PlatformException(code: 'READ_FAILED');
    return Map.of(data);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeStore store;

  void useStore(Map<String, Object> initial) {
    SharedPreferences.resetStatic();
    store = _FakeStore(initial);
    SharedPreferencesStorePlatform.instance = store;
  }

  const key = SleepStylePreferenceService.key;

  test('キーは shiftsleep_sleep_style_preference', () {
    expect(key, 'shiftsleep_sleep_style_preference');
  });

  test('12. 保存して読むと同じ値（3 種類）', () async {
    for (final preference in SleepStylePreference.values) {
      useStore({});
      await SleepStylePreferenceService.save(preference);
      expect(store.data['flutter.$key'], preference.name);
      SharedPreferences.resetStatic();
      expect(await SleepStylePreferenceService.load(), preference);
    }
  });

  test('13. 値がない・知らない値なら auto', () async {
    useStore({});
    expect(await SleepStylePreferenceService.load(), SleepStylePreference.auto);
    useStore({key: 'sometimes'});
    expect(await SleepStylePreferenceService.load(), SleepStylePreference.auto);
  });

  test('14. 読み込みで例外が起きたら auto（例外は外に出さない）', () async {
    useStore({key: 'lastMinute'});
    store.throwOnRead = true;
    expect(await SleepStylePreferenceService.load(), SleepStylePreference.auto);
    // 文字列でない値（型の違い）も auto
    useStore({key: 1});
    expect(await SleepStylePreferenceService.load(), SleepStylePreference.auto);
  });

  test('15. 保存で例外が起きたら外に出す（false が返ったときも）', () async {
    useStore({});
    store.throwOnWrite = true;
    await expectLater(SleepStylePreferenceService.save(SleepStylePreference.immediate), throwsA(isA<PlatformException>()));

    useStore({});
    store.failWrite = true;
    await expectLater(SleepStylePreferenceService.save(SleepStylePreference.immediate), throwsA(isA<StateError>()));
  });
}
