import '../entities/milestone.dart';

abstract interface class IMilestoneRepository {
  /// The couple's milestones, oldest first. Offline, the last copy is returned.
  Future<List<Milestone>> getMilestones(String coupleId);

  /// Adds a special date and tells the partner. [sentNow] is false when there
  /// was no connection: the date is saved on the device and sent later, and
  /// [milestone] is what to show meanwhile.
  Future<({bool sentNow, Milestone milestone})> addDate({
    required String   coupleId,
    required String   userId,
    required String   title,
    required DateTime date,
    String?           note,
    required String   emoji,
    required bool     repeatsYearly,
  });

  Future<void> deleteMilestone(String id);
}
