import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/memory.dart';
import '../../domain/repositories/i_memory_repository.dart';
import '../datasources/remote/firestore_source.dart';
import '../models/memory_model.dart';

class MemoryRepository implements IMemoryRepository {
  MemoryRepository({required this.firestoreSource, Object? storage});

  final FirestoreSource firestoreSource;

  @override
  Stream<List<Memory>> watchMemories(String coupleId) {
    return firestoreSource
        .memoryItems(coupleId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => MemoryModel.fromJson(d.id, d.data()))
            .toList());
  }

  @override
  Future<List<Memory>> getMemories(String coupleId) async {
    final snap = await firestoreSource
        .memoryItems(coupleId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => MemoryModel.fromJson(d.id, d.data())).toList();
  }

  @override
  Future<Memory> saveMemory(Memory memory) async {
    final ref  = firestoreSource.memoryItems(memory.coupleId).doc();
    final model = MemoryModel.fromEntity(memory.copyWith());
    await ref.set(model.toJson());
    return MemoryModel.fromJson(ref.id, model.toJson());
  }

  @override
  Future<void> toggleFavourite(String memoryId, String coupleId, {required bool isFavourited}) =>
      firestoreSource.memoryDoc(coupleId, memoryId).update({'isFavourited': isFavourited});

  @override
  Future<void> deleteMemory(String memoryId, String coupleId) =>
      firestoreSource.memoryDoc(coupleId, memoryId).delete();

  @override
  Future<String> uploadCanvasBitmap(String coupleId, Uint8List bytes) async {
    // Storage requires Blaze plan — returns empty string; UI falls back to emoji thumbnail.
    return '';
  }

  @override
  Future<int> getDoodleCount(String coupleId) async {
    final snap = await firestoreSource
        .memoryItems(coupleId)
        .where('type', isEqualTo: 'canvas')
        .count()
        .get();
    return snap.count ?? 0;
  }
}
