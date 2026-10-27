import 'dart:typed_data';

import '../entities/memory.dart';

abstract interface class IMemoryRepository {
  Stream<List<Memory>>  watchMemories(String coupleId);
  Future<List<Memory>>  getMemories(String coupleId);
  Future<Memory>        saveMemory(Memory memory);
  /// Uploads the drawing and saves it as a canvas memory, notifying the partner.
  /// Returns true when it reached the server, false when it was saved on the
  /// device to be sent once there is a connection.
  Future<bool>          saveDoodle({
    required String    coupleId,
    required String    userId,
    required Uint8List png,
    required String    title,
  });
  Future<void>          toggleFavourite(String memoryId, String coupleId, {required bool isFavourited});
  /// Keeps only the newest [MemoryRepository.keepOnServer] pictures on the server:
  /// older ones are saved on this phone and, once both partners hold a copy,
  /// deleted from the server. Returns how many were newly saved on this phone.
  Future<int>           archiveOlderImages(String coupleId);
  /// Copies every picture kept on this phone to the gallery's "Usync" album,
  /// skipping ones already copied. Returns how many were copied; throws a
  /// `GalException` when photo access is denied.
  Future<int>           backupArchivedToGallery();
  Future<void>          deleteMemory(String memoryId, String coupleId);
  Future<String>        uploadCanvasBitmap(String coupleId, Uint8List bytes);
}
