import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftsleep/services/in_flight.dart';

// N160：同じ key の処理を 1 回にまとめる runOnce のテスト
// 終わらない不具合（whenComplete が自分自身の Future を待つ）をすぐ見つけられるよう、待つときは timeout を付ける

const _wait = Duration(seconds: 1);

void main() {
  test('1. 成功したら終わり、値が呼び出し元に届く', () async {
    final inFlight = <String, Future<int>>{};
    final completer = Completer<int>();
    final future = runOnce(inFlight, 'a', () => completer.future);
    completer.complete(3);
    expect(await future.timeout(_wait), 3);
  });

  test('2. 失敗したら例外が呼び出し元に届く', () async {
    final inFlight = <String, Future<int>>{};
    final completer = Completer<int>();
    final future = runOnce(inFlight, 'a', () => completer.future);
    completer.completeError(StateError('失敗'));
    await expectLater(future.timeout(_wait), throwsA(isA<StateError>()));
  });

  test('3. 成功して終わったら map から消える', () async {
    final inFlight = <String, Future<int>>{};
    final completer = Completer<int>();
    final future = runOnce(inFlight, 'a', () => completer.future);
    expect(inFlight.containsKey('a'), isTrue);
    completer.complete(1);
    await future.timeout(_wait);
    expect(inFlight.containsKey('a'), isFalse);
  });

  test('4. 失敗して終わったときも map から消える', () async {
    final inFlight = <String, Future<int>>{};
    final completer = Completer<int>();
    final future = runOnce(inFlight, 'a', () => completer.future);
    completer.completeError(StateError('失敗'));
    await expectLater(future.timeout(_wait), throwsA(isA<StateError>()));
    expect(inFlight.containsKey('a'), isFalse);
  });

  test('5. 走っているあいだに 2 回呼ぶと同じ Future が返り、start は 1 回だけ', () async {
    final inFlight = <String, Future<int>>{};
    final completer = Completer<int>();
    var starts = 0;
    Future<int> start() {
      starts++;
      return completer.future;
    }

    final first = runOnce(inFlight, 'a', start);
    final second = runOnce(inFlight, 'a', start);
    expect(identical(first, second), isTrue);
    expect(starts, 1);
    completer.complete(1);
    await first.timeout(_wait);
  });

  test('6. 終わったあとにもう一度呼ぶと新しく走る', () async {
    final inFlight = <String, Future<int>>{};
    var starts = 0;
    Future<int> start() async {
      starts++;
      return starts;
    }

    expect(await runOnce(inFlight, 'a', start).timeout(_wait), 1);
    expect(await runOnce(inFlight, 'a', start).timeout(_wait), 2);
    expect(starts, 2);
  });

  test('7. 別の key は別に走る', () async {
    final inFlight = <String, Future<int>>{};
    final a = Completer<int>();
    final b = Completer<int>();
    final futureA = runOnce(inFlight, 'a', () => a.future);
    final futureB = runOnce(inFlight, 'b', () => b.future);
    expect(identical(futureA, futureB), isFalse);
    a.complete(1);
    b.complete(2);
    expect(await futureA.timeout(_wait), 1);
    expect(await futureB.timeout(_wait), 2);
  });

  test('8. すぐ終わる Future でも終わり、map に残らない', () async {
    final inFlight = <String, Future<int>>{};
    final future = runOnce(inFlight, 'a', () => Future.value(5));
    expect(await future.timeout(_wait), 5);
    expect(inFlight.containsKey('a'), isFalse);
  });
}
