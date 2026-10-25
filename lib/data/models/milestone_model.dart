import '../../domain/entities/milestone.dart';

class MilestoneModel extends Milestone {
  const MilestoneModel({
    required super.id,
    required super.coupleId,
    required super.type,
    required super.title,
    required super.occurredAt,
    super.note,
    super.linkedMemoryId,
    super.emoji,
    super.repeatsYearly,
  });

  /// Row from the Supabase `milestones` table.
  factory MilestoneModel.fromRow(Map<String, dynamic> row) => MilestoneModel(
    id:             row['id']               as String,
    coupleId:       row['couple_id']        as String,
    type:           MilestoneType.fromString(row['type'] as String),
    title:          row['title']            as String,
    occurredAt:     DateTime.parse(row['occurred_at'] as String),
    note:           row['note']             as String?,
    linkedMemoryId: row['linked_memory_id'] as String?,
    emoji:          row['emoji']            as String?,
    repeatsYearly:  row['repeats_yearly']   as bool? ?? false,
  );
}
