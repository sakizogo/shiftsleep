// 1a：ShiftRepository.writeIsPremiumUser（is_premium_user の列だけを書く）
//
// 偽の Transaction を渡して、update・insert に渡る値を確かめる（本物の DB は開かない）
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/models/app_settings.dart';
import 'package:shiftsleep/repositories/shift_repository.dart';
import 'package:sqflite/sqflite.dart';

/// update・insert の引数を記録する偽の Transaction（ほかのメソッドは使わない）
class _FakeTransaction implements Transaction {
  _FakeTransaction({this.updatedRows = 1, this.updateError, this.insertError});

  /// update が返す件数（0 なら行がない）
  final int updatedRows;
  final Object? updateError;
  final Object? insertError;

  final updates = <({String table, Map<String, Object?> values, String? where, List<Object?>? whereArgs})>[];
  final inserts = <({String table, Map<String, Object?> values})>[];

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    updates.add((table: table, values: values, where: where, whereArgs: whereArgs));
    if (updateError != null) throw updateError!;
    return updatedRows;
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    inserts.add((table: table, values: values));
    if (insertError != null) throw insertError!;
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 11, 21, 9, 30);

  test('行あり・true：is_premium_user = 1 で update し、insert はしない', () async {
    final txn = _FakeTransaction();

    await ShiftRepository.writeIsPremiumUser(txn, 'test_user', true, now);

    expect(txn.updates, hasLength(1));
    final update = txn.updates.single;
    expect(update.table, 'app_settings');
    expect(update.values, {'is_premium_user': 1, 'updated_at': now.toIso8601String()});
    expect(update.where, 'user_id = ?');
    expect(update.whereArgs, ['test_user']);
    expect(txn.inserts, isEmpty);
  });

  test('行あり・false：is_premium_user = 0 で update し、insert はしない', () async {
    final txn = _FakeTransaction();

    await ShiftRepository.writeIsPremiumUser(txn, 'test_user', false, now);

    expect(txn.updates.single.values['is_premium_user'], 0);
    expect(txn.inserts, isEmpty);
  });

  test('行なし・true：既定の行に is_premium_user = 1 を入れて insert する', () async {
    final txn = _FakeTransaction(updatedRows: 0);

    await ShiftRepository.writeIsPremiumUser(txn, 'test_user', true, now);

    expect(txn.updates, hasLength(1));
    expect(txn.inserts, hasLength(1));
    final insert = txn.inserts.single;
    expect(insert.table, 'app_settings');
    expect(insert.values['user_id'], 'test_user');
    expect(insert.values['is_premium_user'], 1);
    expect(insert.values['created_at'], now.toIso8601String());
    expect(insert.values['updated_at'], now.toIso8601String());
  });

  test('ほかの列を変えない：update は 2 列だけ、insert のほかの列は既定の行のまま', () async {
    final rowExists = _FakeTransaction();
    await ShiftRepository.writeIsPremiumUser(rowExists, 'test_user', true, now);
    expect(rowExists.updates.single.values.keys, unorderedEquals(['is_premium_user', 'updated_at']));

    final noRow = _FakeTransaction(updatedRows: 0);
    await ShiftRepository.writeIsPremiumUser(noRow, 'test_user', true, now);
    final expected = {...AppSettings.defaultRow('test_user', now), 'is_premium_user': 1};
    expect(noRow.inserts.single.values, expected);
  });

  test('update が失敗したら例外が外に伝わり、insert はしない', () async {
    final error = Exception('update');
    final txn = _FakeTransaction(updateError: error);

    await expectLater(
      ShiftRepository.writeIsPremiumUser(txn, 'test_user', true, now),
      throwsA(same(error)),
    );
    expect(txn.inserts, isEmpty);
  });

  test('insert が失敗したら例外が外に伝わる', () async {
    final error = Exception('insert');
    final txn = _FakeTransaction(updatedRows: 0, insertError: error);

    await expectLater(
      ShiftRepository.writeIsPremiumUser(txn, 'test_user', true, now),
      throwsA(same(error)),
    );
    expect(txn.inserts, hasLength(1));
  });
}
