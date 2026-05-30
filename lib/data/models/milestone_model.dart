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
  });

  factory MilestoneModel.fromJson(String id, Map<String, dynamic> json) => MilestoneModel(
    id:             id,
    coupleId:       json['coupleId']       as String,
    type:           MilestoneType.fromString(json['type'] as String),
    title:          json['title']          as String,
    occurredAt:     DateTime.parse(json['occurredAt'] as String),
    note:           json['note']           as String?,
    linkedMemoryId: json['linkedMemoryId'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'coupleId':       coupleId,
    'type':           type.name,
    'title':          title,
    'occurredAt':     occurredAt.toIso8601String(),
    'note':           note,
    'linkedMemoryId': linkedMemoryId,
  };
}
