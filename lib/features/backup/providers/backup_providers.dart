import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/database/local_note_repository.dart';
import '../services/backup_service.dart';
import '../services/restore_service.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  final repo = ref.watch(noteRepositoryProvider);
  return BackupService(repository: repo as LocalNoteRepository);
});

final restoreServiceProvider = Provider<RestoreService>((ref) {
  final repo = ref.watch(noteRepositoryProvider);
  return RestoreService(repository: repo as LocalNoteRepository);
});

final localBackupsProvider = FutureProvider<List<File>>((ref) async {
  final service = ref.watch(backupServiceProvider);
  return service.listLocalBackups();
});
