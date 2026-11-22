import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../../shared/models/attachment_entity.dart';
import '../services/attachment_native_bridge.dart';

/// Provider for the singleton attachment picker service
final attachmentPickerServiceProvider =
    Provider<AttachmentPickerService>((ref) {
  return AttachmentNativeBridge();
});

/// Reactive stream of attachments for a given note
final noteAttachmentsStreamProvider =
    StreamProvider.family<List<AttachmentEntity>, String>((ref, noteId) {
  final repo = ref.watch(noteRepositoryProvider);
  return repo.watchAttachments(noteId);
});

/// Reactive count of attachments for a given note
final noteAttachmentCountProvider = Provider.family<int, String>((ref, noteId) {
  final asyncAtts = ref.watch(noteAttachmentsStreamProvider(noteId));
  return asyncAtts.maybeWhen(
    data: (atts) => atts.length,
    orElse: () => 0,
  );
});

/// Reactive provider for the documents directory base path
final documentsBasePathProvider = FutureProvider<String?>((ref) async {
  final repo = ref.watch(noteRepositoryProvider);
  return repo.getBaseDirectory();
});
