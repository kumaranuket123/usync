import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crypto/content_cipher.dart';
import '../../domain/entities/daily_question.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../../domain/repositories/i_question_repository.dart';

class QuestionRepository implements IQuestionRepository {
  QuestionRepository({required this.client, required this.notifications, required this.cipher});

  final SupabaseClient          client;
  final INotificationRepository notifications;
  final ContentCipher           cipher;

  /// What an answer's text is bound to: its author and the day.
  static String _rowId(String authorId, DailyQuestion question) => '$authorId:${question.day}';

  /// An answer from the server: sealed ones are opened, older readable ones are used as they are.
  /// One this phone cannot open (no key yet) shows as locked.
  Future<String?> _read(String? value, String coupleId, String authorId, DailyQuestion question) async {
    if (value == null || !ContentCipher.isEncrypted(value)) return value;
    try {
      return await cipher.openText(value, coupleId: coupleId, table: 'question_answers', rowId: _rowId(authorId, question), field: 'answer');
    } catch (e) {
      debugPrint('Could not read an answer: ${e.runtimeType}');
      return '🔒 Locked until your key arrives';
    }
  }

  @override
  Future<QuestionState> getState(String coupleId, DailyQuestion question, {required String userId, required String partnerId}) async {
    final rows = await client.rpc('get_question_state', params: {
      'p_couple': coupleId,
      'p_day':    question.day,
    }) as List<dynamic>;
    if (rows.isEmpty) return const QuestionState();
    final row = rows.first as Map<String, dynamic>;
    return QuestionState(
      myAnswer:        await _read(row['my_answer'] as String?, coupleId, userId, question),
      partnerAnswered: row['partner_answered'] as bool? ?? false,
      partnerAnswer:   await _read(row['partner_answer'] as String?, coupleId, partnerId, question),
    );
  }

  @override
  Future<void> answer(String coupleId, String userId, DailyQuestion question, String text) async {
    // Sealed before it leaves the phone: without the couple key this throws and nothing is saved.
    final sealed = await cipher.sealText(text.trim(), coupleId: coupleId, table: 'question_answers', rowId: _rowId(userId, question), field: 'answer');
    try {
      await client.from('question_answers').insert({
        'couple_id':    coupleId,
        'user_id':      userId,
        'day':          question.day,
        'question_idx': question.index,
        'answer':       sealed,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // already answered today: keep the first answer
      rethrow;
    }
    await notifications.notifyPartner(
      coupleId:   coupleId,
      fromUserId: userId,
      type:       NotifType.question,
      body:       (name) => '$name answered today\'s question 💬',
    );
  }
}
