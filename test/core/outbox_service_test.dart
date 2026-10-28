import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/core/services/outbox_service.dart';

class _FakeConnectivity implements Connectivity {
  _FakeConnectivity(this._current);
  List<ConnectivityResult> _current;
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  void set(List<ConnectivityResult> r) {
    _current = r;
    _controller.add(r);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;
}

/// A background send kicked off by `submit` may still be running with the state
/// from before the test changed it; the second call starts a fresh run.
Future<void> drain(OutboxService o) async {
  await o.flush();
  await o.flush();
}

void main() {
  late Directory dir;
  late Box<dynamic> box;
  late _FakeConnectivity net;
  late OutboxService outbox;
  final delivered = <String>[];
  var serverUp = true;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('outbox_test');
    Hive.init(dir.path);
    box = await Hive.openBox<dynamic>('outbox_${DateTime.now().microsecondsSinceEpoch}');
    net = _FakeConnectivity([ConnectivityResult.wifi]);
    outbox = OutboxService(box: box, connectivity: net, retryEvery: const Duration(hours: 1));
    delivered.clear();
    serverUp = true;
    outbox.register('note', (p) async {
      if (!serverUp) throw const SocketException('Failed host lookup');
      delivered.add(p['text'] as String);
    });
    await outbox.init();
  });

  tearDown(() async {
    if (box.isOpen) await outbox.flush(); // let any background send finish before closing
    outbox.dispose();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('sends straight away when online', () async {
    final sent = await outbox.submit('note', {'text': 'a'});
    expect(sent, isTrue);
    expect(delivered, ['a']);
    expect(outbox.pending, 0);
  });

  test('queues while offline and sends in order when back online', () async {
    net.set([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);

    expect(await outbox.submit('note', {'text': 'a'}), isFalse);
    expect(await outbox.submit('note', {'text': 'b'}), isFalse);
    expect(await outbox.submit('note', {'text': 'c'}), isFalse);
    expect(outbox.pending, 3);
    expect(delivered, isEmpty);

    net.set([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(delivered, ['a', 'b', 'c']);
    expect(outbox.pending, 0);
  });

  test('queues when the connection fails mid-send, and keeps order', () async {
    serverUp = false; // plugin says online but the server is unreachable
    expect(await outbox.submit('note', {'text': 'a'}), isFalse);
    expect(await outbox.submit('note', {'text': 'b'}), isFalse);
    expect(outbox.pending, 2);

    serverUp = true;
    await drain(outbox);
    expect(delivered, ['a', 'b']);
    expect(outbox.pending, 0);
  });

  test('a new change waits behind queued ones instead of jumping ahead', () async {
    serverUp = false;
    await outbox.submit('note', {'text': 'old'});
    serverUp = true;
    // Online again, but "old" has not been flushed yet: "new" must not overtake it.
    await outbox.submit('note', {'text': 'new'});
    await drain(outbox);
    expect(delivered, ['old', 'new']);
  });

  test('stops at the first connection failure and keeps the rest', () async {
    serverUp = false;
    await outbox.submit('note', {'text': 'a'});
    await outbox.submit('note', {'text': 'b'});
    await outbox.flush();
    expect(delivered, isEmpty);
    expect(outbox.pending, 2);
  });

  test('survives a restart: queued changes are still there', () async {
    serverUp = false;
    await outbox.submit('note', {'text': 'kept'});
    await outbox.flush();
    final name = box.name;
    await box.close(); // the app quitting; tearDown disposes the old service

    final reopened = await Hive.openBox<dynamic>(name);
    final fresh = OutboxService(box: reopened, connectivity: net, retryEvery: const Duration(hours: 1));
    fresh.register('note', (p) async => delivered.add(p['text'] as String));
    expect(fresh.pending, 1);
    serverUp = true;
    await drain(fresh);
    expect(delivered, ['kept']);
    expect(fresh.pending, 0);
    fresh.dispose();
  });

  test('a change the server rejects is retried, then dropped, and does not block others', () async {
    final failing = OutboxService(
      box: box,
      connectivity: net,
      retryEvery: const Duration(hours: 1),
      maxAttempts: 2,
    );
    failing.register('bad', (_) async => throw StateError('rejected'));
    failing.register('note', (p) async => delivered.add(p['text'] as String));
    net.set([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    // Put both in the queue by hand, as if made offline.
    await box.add({'type': 'bad', 'payload': <String, dynamic>{}, 'createdAt': '', 'attempts': 0});
    await box.add({'type': 'note', 'payload': {'text': 'ok'}, 'createdAt': '', 'attempts': 0});

    await failing.flush();
    expect(delivered, ['ok']); // not blocked by the bad one
    expect(failing.pending, 1);
    await failing.flush();     // second failure reaches maxAttempts
    expect(failing.pending, 0);
    failing.dispose();
  });

  test('a send that hangs counts as a lost connection and is queued', () async {
    final slow = OutboxService(
      box: box,
      connectivity: net,
      retryEvery: const Duration(hours: 1),
      sendTimeout: const Duration(milliseconds: 50),
    );
    slow.register('hang', (_) => Completer<void>().future); // never finishes
    expect(await slow.submit('hang', {}), isFalse);
    expect(slow.pending, 1);
    await slow.flush(); // the background retry also times out; let it finish
    slow.dispose();
  });

  test('errors that are not about the connection reach the caller', () async {
    outbox.register('boom', (_) async => throw StateError('nope'));
    expect(() => outbox.submit('boom', {}), throwsStateError);
    expect(outbox.pending, 0);
  });

  test('binary data (a doodle) survives the queue', () async {
    final seen = <List<int>>[];
    outbox.register('png', (p) async => seen.add(p['bytes'] as List<int>));
    serverUp = false;
    net.set([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    await outbox.submit('png', {'bytes': [1, 2, 3, 4]});
    net.set([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen.single, [1, 2, 3, 4]);
  });

  test('a change waiting for the couple key is kept, never counted as failed, and sent once the key arrives', () async {
    var keyArrived = false;
    outbox.register('sealed', (p) async {
      if (!keyArrived) throw const EncryptionNotReady();
      delivered.add(p['text'] as String);
    });

    await expectLater(outbox.submit('sealed', {'text': 'a'}), throwsA(isA<EncryptionNotReady>()), reason: 'the first try tells the caller');
    expect(outbox.pending, 0);

    // Queued while offline, then the connection returns before the key does.
    net.set([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    expect(await outbox.submit('sealed', {'text': 'b'}), isFalse);
    net.set([ConnectivityResult.wifi]);
    for (var i = 0; i < outbox.maxAttempts + 2; i++) {
      await drain(outbox);
    }
    expect(outbox.pending, 1, reason: 'still waiting, not dropped');
    expect(delivered, isEmpty);

    keyArrived = true;
    await drain(outbox);
    expect(delivered, ['b']);
    expect(outbox.pending, 0);
  });
}
