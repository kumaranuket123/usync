import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/utils/ttl_cache.dart';

void main() {
  late DateTime clock;
  late TtlCache<String> cache;
  var loads = 0;

  setUp(() {
    clock = DateTime(2026, 1, 1, 12);
    cache = TtlCache<String>(ttl: const Duration(minutes: 5), now: () => clock);
    loads = 0;
  });

  Future<String> load() async {
    loads++;
    return 'v$loads';
  }

  test('a fresh value is reused without loading again', () async {
    expect(await cache.get('k', load), 'v1');
    expect(await cache.get('k', load), 'v1');
    expect(loads, 1);
  });

  test('an expired value is loaded again', () async {
    await cache.get('k', load);
    clock = clock.add(const Duration(minutes: 6));
    expect(await cache.get('k', load), 'v2');
    expect(loads, 2);
  });

  test('several callers at once share one load', () async {
    final gate = Completer<String>();
    var calls = 0;
    Future<String> slow() {
      calls++;
      return gate.future;
    }

    final a = cache.get('k', slow);
    final b = cache.get('k', slow);
    final c = cache.get('k', slow);
    gate.complete('shared');
    expect(await Future.wait([a, b, c]), ['shared', 'shared', 'shared']);
    expect(calls, 1);
  });

  test('a failed load is not kept; the next call tries again', () async {
    var attempt = 0;
    Future<String> flaky() async {
      attempt++;
      if (attempt == 1) throw StateError('offline');
      return 'ok';
    }

    await expectLater(cache.get('k', flaky), throwsStateError);
    expect(await cache.get('k', flaky), 'ok');
    expect(attempt, 2);
  });

  test('keys are independent, invalidate and clear force a reload', () async {
    await cache.get('a', load);
    await cache.get('b', load);
    expect(loads, 2);

    cache.invalidate('a');
    await cache.get('a', load);
    await cache.get('b', load);
    expect(loads, 3); // only "a" reloaded

    cache.clear();
    await cache.get('b', load);
    expect(loads, 4);
  });

  test('put stores a value learned elsewhere (a live update)', () async {
    cache.put('k', 'live');
    expect(await cache.get('k', load), 'live');
    expect(loads, 0);
  });
}
