import 'package:flutter_test/flutter_test.dart';
import 'package:usync/data/datasources/local/identity_cache.dart';
import 'package:usync/data/datasources/remote/couple_channel_source.dart';
import 'package:usync/data/datasources/remote/storage_source.dart';
import 'package:usync/data/repositories/couple_repository.dart';
import 'package:usync/domain/entities/couple.dart';

import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late LocalStorage local;
  late IdentityCache identity;
  late CoupleChannelSource channels;
  late CoupleRepository repo;

  setUp(() async {
    backend = FakeBackend();
    local = LocalStorage();
    await local.setUp();
    identity = IdentityCache();
    channels = CoupleChannelSource(client: backend.client);
    repo = CoupleRepository(
      client: backend.client,
      channelSource: channels,
      notifications: RecordingNotifications(),
      storage: StorageSource(client: backend.client),
      sessionCache: local.sessionCache,
      identity: identity,
    );
  });

  tearDown(() async {
    channels.close();
    await local.tearDown();
    await backend.dispose();
  });

  group('generateInviteCode', () {
    test('stores a 4-character code from the unambiguous alphabet, valid for 24 hours', () async {
      backend.respond((_) => FakeBackend.ok([]));
      final before = DateTime.now().toUtc();

      final code = await repo.generateInviteCode('user-1');

      expect(code, matches(RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}$')));
      final insert = backend.requests.single;
      expect(insert.method, 'POST');
      expect(insert.path, endsWith('/invite_codes'));
      final row = insert.json as Map;
      expect(row['code'], code);
      expect(row['user_id'], 'user-1');
      final expiry = DateTime.parse(row['expires_at'] as String);
      expect(expiry.difference(before).inHours, inInclusiveRange(23, 24));
    });

    test('retries with a new code when one is already taken', () async {
      var calls = 0;
      backend.respond((_) => ++calls < 3
          ? FakeBackend.error('23505', 'duplicate key value')
          : FakeBackend.ok([]));

      final code = await repo.generateInviteCode('user-1');

      expect(backend.requests, hasLength(3));
      expect((backend.requests.last.json as Map)['code'], code);
    });

    test('gives up after 5 collisions', () async {
      backend.respond((_) => FakeBackend.error('23505', 'duplicate key value'));
      await expectLater(repo.generateInviteCode('user-1'), throwsException);
      expect(backend.requests, hasLength(5));
    });

    test('does not retry errors that are not collisions', () async {
      backend.respond((_) => FakeBackend.error('42501', 'permission denied', status: 403));
      await expectLater(repo.generateInviteCode('user-1'), throwsA(anything));
      expect(backend.requests, hasLength(1));
    });
  });

  group('joinWithCode', () {
    final row = {
      'id': 'couple-1',
      'user_a_id': 'inviter',
      'user_b_id': 'joiner',
      'paired_at': '2026-01-01T00:00:00Z',
      'streak_days': 0,
      'total_moments': 0,
    };

    test('calls the join_with_code function and returns the couple', () async {
      backend.respond((_) => FakeBackend.ok(row));

      final couple = await repo.joinWithCode('AB12', 'joiner');

      final call = backend.requests.single;
      expect(call.path, endsWith('/rpc/join_with_code'));
      expect((call.json as Map)['p_code'], 'AB12');
      expect(couple.id, 'couple-1');
      expect(couple.partnerIdFor('joiner'), 'inviter');
    });

    test('clears the identity cache because both profiles changed', () async {
      backend.respond((_) => FakeBackend.ok(row));
      final stale = Couple(id: 'old', userAId: 'a', userBId: 'b', pairedAt: DateTime(2025));
      var loads = 0;
      Future<Couple> load() async {
        loads++;
        return stale;
      }

      await identity.couples.get('me', load);
      await identity.couples.get('me', load);
      expect(loads, 1, reason: 'cached before pairing');

      await repo.joinWithCode('AB12', 'joiner');

      await identity.couples.get('me', load);
      expect(loads, 2, reason: 'cache was cleared by pairing');
    });

    test('surfaces the server message for an invalid code', () async {
      backend.respond((_) => FakeBackend.error('P0001', 'Invalid invite code', status: 400));
      await expectLater(
        repo.joinWithCode('ZZZZ', 'joiner'),
        throwsA(predicate((e) => e.toString().contains('Invalid invite code'))),
      );
    });
  });
}
