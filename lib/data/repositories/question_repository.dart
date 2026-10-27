import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/daily_question.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../../domain/repositories/i_question_repository.dart';

class QuestionRepository implements IQuestionRepository {
  QuestionRepository({required this.client, required this.notifications});

  final SupabaseClient          client;
  final INotificationRepository notifications;

  @override
  Future<QuestionState> getState(String coupleId, DailyQuestion question) async {
    final rows = await client.rpc('get_question_state', params: {
      'p_couple': coupleId,
      'p_day':    question.day,
    }) as List<dynamic>;
    if (rows.isEmpty) return const QuestionState();
    final row = rows.first as Map<String, dynamic>;
    return QuestionState(
      myAnswer:        row['my_answer'] as String?,
      partnerAnswered: row['partner_answered'] as bool? ?? false,
      partnerAnswer:   row['partner_answer'] as String?,
    );
  }

  @override
  Future<void> answer(String coupleId, String userId, DailyQuestion question, String text) async {
    try {
      await client.from('question_answers').insert({
        'couple_id':    coupleId,
        'user_id':      userId,
        'day':          question.day,
        'question_idx': question.index,
        'answer':       text.trim(),
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
