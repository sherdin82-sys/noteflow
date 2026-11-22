import 'dart:async';
import 'package:flutter/services.dart';
import '../models/staged_attachment.dart';
import 'attachment_picker_service.dart';

export '../models/staged_attachment.dart';
export 'attachment_picker_service.dart';

class AttachmentNativeBridge implements AttachmentPickerService {
  static const MethodChannel _channel = MethodChannel('com.noteflow.app/attachments');
  final Set<String> _processedRequestIds = {};

  @override
  Future<PickerResult> pickAttachments({
    String category = 'all',
    int maxSingleFileBytes = 25 * 1024 * 1024,
  }) async {
    final requestId = MockAttachmentPickerService.generateUuidV4();
    try {
      final rawResult = await _channel.invokeMethod<Map<dynamic, dynamic>>('pickAttachments', {
        'requestId': requestId,
        'category': category,
        'maxSingleFileBytes': maxSingleFileBytes,
      });

      if (rawResult == null) {
        return PickerResult(requestId: requestId, isCancelled: true);
      }

      final result = PickerResult.fromMap(Map<String, dynamic>.from(rawResult));
      _processedRequestIds.add(result.requestId);
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'PICKER_ACTIVE') {
        throw const AttachmentPickerActiveException('A picker operation is already in progress');
      }
      rethrow;
    }
  }

  @override
  Future<PickerResult?> getPendingPickerResult() async {
    try {
      final rawResult = await _channel.invokeMethod<Map<dynamic, dynamic>>('getPendingPickerResult');
      if (rawResult == null) return null;

      final result = PickerResult.fromMap(Map<String, dynamic>.from(rawResult));
      // Duplicate-delivery protection: if this request ID was already processed, ignore it
      if (_processedRequestIds.contains(result.requestId)) {
        await clearPendingPickerResult();
        return null;
      }

      _processedRequestIds.add(result.requestId);
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearPendingPickerResult() async {
    try {
      await _channel.invokeMethod('clearPendingPickerResult');
    } catch (_) {}
  }

  /// Opens an attachment using an Android Intent (ACTION_VIEW) via FileProvider
  Future<bool> openAttachment({
    required String relativePath,
    required String mimeType,
    String? originalName,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('openAttachment', {
        'relativePath': relativePath,
        'mimeType': mimeType,
        'originalName': originalName,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shares an attachment using Android Sharesheet (ACTION_SEND) via FileProvider
  Future<bool> shareAttachment({
    required String relativePath,
    required String mimeType,
    String? originalName,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('shareAttachment', {
        'relativePath': relativePath,
        'mimeType': mimeType,
        'originalName': originalName,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
