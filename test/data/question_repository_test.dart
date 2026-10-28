import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/crypto/content_cipher.dart';
import 'package:usync/data/repositories/question_repository.dart';
import 'package:usync/domain/entities/daily_question.dart';
import 'package:usync/domain/entities/notification_item.dart';

import '../support/test_cipher.dart';
import 'repository_harness.dart';

void main() {
  late FakeBackend backend;
  late RecordingNotifications notifications;
  late ContentCipher cipher;
  late QuestionRepository repo;
  final question = DailyQuestion.forDay(DateTime(2026, 3, 4));

  QuestionRepository build(ContentCipher c) => QuestionRepository(client: backend.client, notifications: notifications, cipher: c);

  setUp(() async {
    backend = FakeBackend();
    notifications = RecordingNotifications();
    cipher = await readyCipher();
    repo = build(cipher);
  });

  tearDown(() => backend.dispose());

  group('answer', () {
    test('sends the answer only as ciphertext and notifies the partner with a fixed sentence', () async {
      backend.respond((_) => FakeBackend.ok([], status: 201));

      await repo.answer('c1', 'u1', question, '  I love our walks  ');

      final insert = backend.requests.single;
      expect(insert.path, endsWith('/question_answers'));
      final row = insert.json as Map;
      expect(row['answer'], startsWith('u1:'));
      expect(bodyText(insert.json), isNot(contains('walks')));
      expect(row['user_id'], 'u1');
      expect(row['day'], question.day);

      final opened = await cipher.openText(row['answer'] as String, coupleId: 'c1', table: 'question_answers', rowId: 'u1:${question.day}', field: 'answer');
      expect(opened, 'I love our walks', reason: 'trimmed, then sealed');

      expect(notifications.sent.single.type, NotifType.question);
      expect(notifications.sent.single.body, contains('answered'));
    });

    test('without the couple key nothing is sent, and the caller is told', () async {
      repo = build(notReadyCipher());
      backend.respond((_) => FakeBackend.ok([]));

      await expectLater(repo.answer('c1', 'u1', question, 'hello'), throwsA(isA<EncryptionNotReady>()));

      expect(backend.requests, isEmpty);
      expect(notifications.sent, isEmpty);
    });

    test('an answer already given is kept and the partner is not told twice', () async {
      backend.respond((_) => FakeBackend.error('23505', 'duplicate key value'));
      await repo.answer('c1', 'u1', question, 'again');
      expect(notifications.sent, isEmpty);
    });
  });

  group('getState', () {
    Future<String> sealed(String author, String text, {ContentCipher? by}) => (by ?? cipher)
        .sealText(text, coupleId: 'c1', table: 'question_answers', rowId: '$author:${question.day}', field: 'answer');

    test('opens my answer and the partner\'s', () async {
      final mine = await sealed('u1', 'mine');
      final theirs = await sealed('u2', 'theirs');
      backend.respond((_) => FakeBackend.ok([
            {'my_answer': mine, 'partner_answered': true, 'partner_answer': theirs},
          ]));

      final state = await repo.getState('c1', question, userId: 'u1', partnerId: 'u2');

      expect(state.myAnswer, 'mine');
      expect(state.partnerAnswered, isTrue);
      expect(state.partnerAnswer, 'theirs');
    });

    test('an older readable answer is still shown, and a hidden partner answer stays null', () async {
      backend.respond((_) => FakeBackend.ok([
            {'my_answer': 'old plain', 'partner_answered': true, 'partner_answer': null},
          ]));

      final state = await repo.getState('c1', question, userId: 'u1', partnerId: 'u2');

      expect(state.myAnswer, 'old plain');
      expect(state.partnerAnswer, isNull);
    });

    test('an answer placed under the wrong author does not open', () async {
      final theirs = await sealed('u2', 'theirs');
      backend.respond((_) => FakeBackend.ok([
            {'my_answer': null, 'partner_answered': true, 'partner_answer': theirs},
          ]));

      // Reading it as if the partner were someone else breaks the binding.
      final state = await repo.getState('c1', question, userId: 'u1', partnerId: 'u3');

      expect(state.partnerAnswer, isNot('theirs'));
    });

    test('without the couple key an answer shows as locked', () async {
      final mine = await sealed('u1', 'mine');
      repo = build(notReadyCipher());
      backend.respond((_) => FakeBackend.ok([
            {'my_answer': mine, 'partner_answered': false, 'partner_answer': null},
          ]));

      final state = await repo.getState('c1', question, userId: 'u1', partnerId: 'u2');

      expect(state.myAnswer, isNot('mine'));
      expect(state.myAnswer, isNotNull);
    });
  });
}
