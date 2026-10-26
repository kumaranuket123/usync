import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/utils/signed_url_cache.dart';

void main() {
  late DateTime clock;
  late SignedUrlCache cache;
  late List<List<String>> signCalls;

  Future<Map<String, String>> sign(List<String> paths) async {
    signCalls.add(List.of(paths));
    return {for (final p in paths) p: 'https://signed/$p?t=${signCalls.length}'};
  }

  setUp(() {
    clock = DateTime(2026, 1, 1, 12);
    cache = SignedUrlCache(now: () => clock); // 1 h links, renewed 10 min early
    signCalls = [];
  });

  test('signs everything the first time', () async {
    final urls = await cache.resolve(['a.png', 'b.png'], sign);
    expect(urls.keys, containsAll(['a.png', 'b.png']));
    expect(signCalls, hasLength(1));
  });

  test('a repeat with the same paths signs nothing', () async {
    final first  = await cache.resolve(['a.png', 'b.png'], sign);
    final second = await cache.resolve(['a.png', 'b.png'], sign);
    expect(signCalls, hasLength(1));
    expect(second, first); // identical links, so images keep their cache entry
  });

  test('only a new path is signed when the list grows', () async {
    await cache.resolve(['a.png', 'b.png'], sign);
    await cache.resolve(['a.png', 'b.png', 'c.png'], sign);
    expect(signCalls, hasLength(2));
    expect(signCalls.last, ['c.png']);
  });

  test('links are signed again shortly before they expire, not after', () async {
    await cache.resolve(['a.png'], sign);

    clock = clock.add(const Duration(minutes: 49)); // 11 min left: still good
    await cache.resolve(['a.png'], sign);
    expect(signCalls, hasLength(1));

    clock = clock.add(const Duration(minutes: 2)); // 9 min left: renew now
    final renewed = await cache.resolve(['a.png'], sign);
    expect(signCalls, hasLength(2));
    expect(renewed['a.png'], contains('t=2'));
  });

  test('a path the server could not sign is left out and asked for again later', () async {
    Future<Map<String, String>> partial(List<String> paths) async =>
        {for (final p in paths) if (p != 'bad.png') p: 'https://signed/$p'};
    final urls = await cache.resolve(['ok.png', 'bad.png'], partial);
    expect(urls.keys, ['ok.png']);

    var asked = <String>[];
    await cache.resolve(['ok.png', 'bad.png'], (m) async {
      asked = m;
      return {};
    });
    expect(asked, ['bad.png']);
  });

  test('nothing to sign means no request', () async {
    expect(await cache.resolve(const [], sign), isEmpty);
    expect(signCalls, isEmpty);
  });
}
