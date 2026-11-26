import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usync/core/services/chat_delivery_service.dart';

import '../data/repository_harness.dart';
import '../support/test_cipher.dart';

void main() {
  late FakeBackend backend;
  late ChatDeliveryService service;
  var waiting = <String>[];

  List<Map<String, dynamic>> sent() => [
        for (final r in backend.requests.where((r) => r.path.endsWith('/rpc/send_chat_message'))) r.json as Map<String, dynamic>,
      ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = FakeBackend();
    waiting = ['m1', 'm2'];
    backend.respond((req) => req.path.endsWith('/chat_messages')
        ? FakeBackend.ok([for (final id in waiting) {'id': id}])
        : FakeBackend.ok('2026-06-01T10:00:00+00:00'));
    service = ChatDeliveryService(client: backend.client, cipher: await readyCipher(), prefs: await SharedPreferences.getInstance());
  });

  tearDown(() => backend.dispose());

  test('sends one sealed delivered receipt for the waiting messages, and does not collect them', () async {
    await service.reportDelivered(coupleId: 'c1', senderId: 'partner');

    final rpcs = sent();
    expect(rpcs, hasLength(1));
    expect(rpcs.single['p_kind'], 'control');
    expect(bodyText(rpcs.single), isNot(contains('m1')), reason: 'the ids are sealed, not readable by the server');
    expect(backend.requests.where((r) => r.path.endsWith('/rpc/ack_chat_messages')), isEmpty);
  });

  test('a later push only reports the messages not reported before', () async {
    await service.reportDelivered(coupleId: 'c1', senderId: 'partner');
    backend.requests.clear();

    await service.reportDelivered(coupleId: 'c1', senderId: 'partner');
    expect(sent(), isEmpty);

    waiting = ['m1', 'm2', 'm3'];
    await service.reportDelivered(coupleId: 'c1', senderId: 'partner');
    expect(sent(), hasLength(1));
  });

  test('nothing waiting (the app already collected them) sends nothing', () async {
    waiting = [];
    await service.reportDelivered(coupleId: 'c1', senderId: 'partner');
    expect(sent(), isEmpty);
  });
}
