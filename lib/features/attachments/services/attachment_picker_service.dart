import 'dart:async';
import 'dart:math';
import '../models/staged_attachment.dart';

abstract class AttachmentPickerService {
  Future<PickerResult> pickAttachments({
    String category = 'all',
    int maxSingleFileBytes = 25 * 1024 * 1024,
  });

  Future<PickerResult?> getPendingPickerResult();

  Future<void> clearPendingPickerResult();
}

class MockAttachmentPickerService implements AttachmentPickerService {
  PickerResult? simulatedNextResult;
  PickerResult? simulatedPendingResult;
  bool isPickerActive = false;
  final Set<String> processedRequestIds = {};

  static String generateUuidV4() {
    final random = Random();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
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

  @override
  Future<PickerResult> pickAttachments({
    String category = 'all',
    int maxSingleFileBytes = 25 * 1024 * 1024,
  }) async {
    if (isPickerActive) {
      throw const AttachmentPickerActiveException('A picker operation is already in progress');
    }
    isPickerActive = true;
    try {
      final result = simulatedNextResult ??
          PickerResult(
            requestId: generateUuidV4(),
            isCancelled: false,
            items: const [],
          );
      processedRequestIds.add(result.requestId);
      return result;
    } finally {
      isPickerActive = false;
    }
  }

  @override
  Future<PickerResult?> getPendingPickerResult() async {
    final pending = simulatedPendingResult;
    if (pending == null) return null;
    if (processedRequestIds.contains(pending.requestId)) {
      simulatedPendingResult = null;
      return null;
    }
    processedRequestIds.add(pending.requestId);
    simulatedPendingResult = null;
    return pending;
  }

  @override
  Future<void> clearPendingPickerResult() async {
    simulatedPendingResult = null;
  }
}

class AttachmentPickerActiveException implements Exception {
  final String message;
  const AttachmentPickerActiveException(this.message);
  @override
  String toString() => 'AttachmentPickerActiveException: $message';
}
