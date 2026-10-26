import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:usync/data/datasources/remote/couple_channel_source.dart';

/// Uses the real Supabase client against an address nothing listens on, which is
/// exactly what having no connection looks like to the app.
void main() {
  late SupabaseClient client;
  late CoupleChannelSource source;

  setUp(() {
    HttpOverrides.global = null; // real sockets, not the test stub
    client = SupabaseClient('http://127.0.0.1:9', 'anon-key');
    source = CoupleChannelSource(client: client);
  });

  tearDown(() async {
    source.close();
    await client.dispose();
  });

  test('sending and announcing presence never hang or throw while offline', () async {
    final channel = source.open('couple-1');

    // Before the fix these waited for a connection that never came.
    await channel.send('touch', {'user_id': 'u', 'is_active': true}).timeout(const Duration(seconds: 6));
    await channel.track({'user_id': 'u', 'screen': 'touch'}).timeout(const Duration(seconds: 6));
    await channel.untrack().timeout(const Duration(seconds: 6));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('callers wait a bounded time for the channel, not forever', () async {
    final channel = source.open('couple-1');
    final watch = Stopwatch()..start();
    await channel.whenReady(const Duration(milliseconds: 300));
    expect(watch.elapsedMilliseconds, inInclusiveRange(250, 1500));
  });

  test('the same couple reuses one channel', () {
    expect(identical(source.open('couple-1'), source.open('couple-1')), isTrue);
    expect(client.realtime.channels, hasLength(1));
  });

  test('a channel the server closed is replaced by a fresh one', () async {
    source.open('couple-1');
    expect(client.realtime.channels, hasLength(1));
    final original = client.realtime.channels.single;

    // The library reports a server-side close exactly like this: the channel is
    // closed and dropped from the socket, and it is never rejoined.
    await client.removeChannel(original);
    expect(client.realtime.channels, isEmpty, reason: 'the library does not rejoin a closed channel');

    await Future<void>.delayed(const Duration(milliseconds: 1600)); // first retry after ~1s
    expect(client.realtime.channels, hasLength(1), reason: 'the app makes a new one');
    expect(identical(client.realtime.channels.single, original), isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('closing at sign-out leaves no channel behind, and the next session gets its own', () async {
    final first = source.open('couple-1');
    source.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(client.realtime.channels, isEmpty);

    final second = source.open('couple-1');
    expect(identical(first, second), isFalse);
    expect(client.realtime.channels, hasLength(1));
  });
}
