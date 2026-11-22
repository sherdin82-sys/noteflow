import 'dart:io';
import 'dart:math';

import '../../shared/models/attachment_entity.dart';

/// Exception thrown when an attempted filesystem access violates path confinement.
class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}

/// Helper class providing secure path resolution, file lifecycle operations,
/// and orphan cleanup for NoteFlow note attachments.
class AttachmentHelper {
  const AttachmentHelper._();

  static const String attachmentsDirName = 'attachments';
  static final RegExp _safeIdRegex = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');

  /// Validates an ID string against path traversal injections and malformed characters.
  /// Throws [ArgumentError] if the ID contains path traversal sequences, slashes,
  /// whitespace, control characters, or is empty / exceeds 64 characters.
  static void validateIdentifier(String id, String fieldName) {
    if (!_safeIdRegex.hasMatch(id)) {
      throw ArgumentError(
        'Invalid $fieldName: contains illegal characters or path traversal attempt',
      );
    }
  }

  /// Sanitizes file extensions to strictly alphanumeric characters, converted to lowercase,
  /// and truncated to a maximum of 10 characters.
  static String sanitizeExtension(String ext) {
    final clean = ext.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    return clean.length > 10 ? clean.substring(0, 10) : clean;
  }

  /// Normalizes a path string, resolving backslashes and relative segments.
  static String normalizePath(String path) {
    final forwardSlashes = path.replaceAll('\\', '/');
    return Uri.file(forwardSlashes).normalizePath().toFilePath();
  }

  /// Resolves an absolute path from a relative path and verifies that it is strictly
  /// confined within the attachments root directory: `<documentsBasePath>/attachments/`.
  /// Throws [SecurityException] if path traversal or escaping is detected.
  static String resolveAndVerifyPath({
    required String relativePath,
    required String documentsBasePath,
  }) {
    if (relativePath.contains('\x00')) {
      throw const SecurityException(
        'Path traversal detected: null byte in path',
      );
    }

    final rootDir = Directory('$documentsBasePath/$attachmentsDirName');
    final rawTarget = '$documentsBasePath/$relativePath';

    final canonicalRoot = normalizePath(rootDir.absolute.path);
    final canonicalTarget = normalizePath(File(rawTarget).absolute.path);

    if (!canonicalTarget.startsWith('$canonicalRoot/') && canonicalTarget != canonicalRoot) {
      throw const SecurityException(
        'Path traversal detected: attempted access outside attachments directory',
      );
    }
    return canonicalTarget;
  }

  /// Generates a standard RFC 4122 version 4 UUID string.
  static String generateUuidV4() {
    final random = Random();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // RFC 4122 version 4
    values[8] = (values[8] & 0x3f) | 0x80; // RFC 4122 variant
    return [
      values.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(4, 6).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(6, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(8, 10).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(10, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    ].join('-');
  }

  /// Finalizes import from a staging file into permanent application-private storage:
  /// `<documentsBasePath>/attachments/<noteId>/<attachmentId>.<ext>`.
  ///
  /// Returns the newly created [AttachmentEntity], or `null` if the staging file is
  /// missing or empty.
  static Future<AttachmentEntity?> commitStagedAttachment({
    required String stagingPath,
    required String originalName,
    required String noteId,
    required String documentsBasePath,
    String? mimeType,
    String Function()? idGenerator,
  }) async {
    validateIdentifier(noteId, 'noteId');

    final stagingFile = File(stagingPath);
    if (!await stagingFile.exists()) return null;
    final size = await stagingFile.length();
    if (size == 0) return null;

    final rawExt = originalName.contains('.')
        ? originalName.split('.').last
        : '';
    final ext = sanitizeExtension(rawExt);
    final attachmentId = idGenerator != null ? idGenerator() : generateUuidV4();
    validateIdentifier(attachmentId, 'attachmentId');

    final storedName = ext.isNotEmpty ? '$attachmentId.$ext' : attachmentId;
    final relPath = '$attachmentsDirName/$noteId/$storedName';

    final targetDir = Directory('$documentsBasePath/$attachmentsDirName/$noteId');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final targetPath = resolveAndVerifyPath(
      relativePath: relPath,
      documentsBasePath: documentsBasePath,
    );

    // Atomic move from staging to permanent storage.
    // If moving across different filesystem mounts, fallback to copy + delete.
    try {
      await stagingFile.rename(targetPath);
    } on FileSystemException {
      await stagingFile.copy(targetPath);
      try {
        await stagingFile.delete();
      } catch (_) {}
    }

    final resolvedMime = (mimeType != null && mimeType.isNotEmpty)
        ? mimeType
        : inferMimeType(ext);
    final category = AttachmentCategory.fromMime(resolvedMime, ext);

    return AttachmentEntity(
      id: attachmentId,
      noteId: noteId,
      originalName: originalName,
      storedName: storedName,
      relativePath: relPath,
      mimeType: resolvedMime,
      fileExtension: ext,
      fileSizeBytes: size,
      category: category,
      createdAt: DateTime.now(),
    );
  }

  /// Safely deletes a physical attachment file and prunes its parent directory if empty.
  /// Returns `true` if deletion succeeded or file was absent, `false` on unexpected error.
  static Future<bool> deleteAttachmentFile({
    required String relativePath,
    required String documentsBasePath,
  }) async {
    try {
      final absPath = resolveAndVerifyPath(
        relativePath: relativePath,
        documentsBasePath: documentsBasePath,
      );
      final file = File(absPath);
      if (await file.exists()) {
        await file.delete();
      }
      final parentDir = file.parent;
      if (await parentDir.exists() && await parentDir.list().isEmpty) {
        await parentDir.delete(recursive: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cascades deletion of all attachments belonging to a parent note directory:
  /// `<documentsBasePath>/attachments/<noteId>/`.
  static Future<void> deleteNoteAttachmentDirectory({
    required String noteId,
    required String documentsBasePath,
  }) async {
    validateIdentifier(noteId, 'noteId');
    try {
      final noteDir = Directory('$documentsBasePath/$attachmentsDirName/$noteId');
      if (await noteDir.exists()) {
        await noteDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Startup orphan reconciliation routine.
  /// Scans `<documentsBasePath>/attachments/`, deletes leftover `.tmp` files,
  /// purges files not listed in [activeRelativePaths], and removes empty subdirectories.
  static Future<void> reconcileAttachments({
    required String documentsBasePath,
    required List<String> activeRelativePaths,
    String? stagingBasePath,
  }) async {
    // 1. Clean up staging directory if provided
    if (stagingBasePath != null) {
      try {
        final stagingDir = Directory(stagingBasePath);
        if (await stagingDir.exists()) {
          final stagedEntities = await stagingDir.list().toList();
          for (final entity in stagedEntities) {
            if (entity is File) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }

    // 2. Reconcile permanent attachments directory
    try {
      final rootDir = Directory('$documentsBasePath/$attachmentsDirName');
      if (!await rootDir.exists()) return;

      final activeSet = activeRelativePaths.toSet();
      final entities = await rootDir.list(recursive: true).toList();

      for (final entity in entities) {
        if (entity is File) {
          // Delete leftover .tmp files
          if (entity.path.endsWith('.tmp')) {
            try {
              await entity.delete();
            } catch (_) {}
            continue;
          }
          final normEntityPath = normalizePath(entity.path);
          final normDocsPath = normalizePath(documentsBasePath);
          final rel = normEntityPath.startsWith('$normDocsPath/')
              ? normEntityPath.substring(normDocsPath.length + 1)
              : normEntityPath;
          if (!activeSet.contains(rel)) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }

      // Prune empty note directories
      final subDirs = await rootDir.list().toList();
      for (final subDir in subDirs) {
        if (subDir is Directory) {
          try {
            if (await subDir.list().isEmpty) {
              await subDir.delete(recursive: true);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Infers standard MIME type from a sanitized file extension.
  static String inferMimeType(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'csv':
        return 'text/csv';
      default:
        return 'application/octet-stream';
    }
  }
}
