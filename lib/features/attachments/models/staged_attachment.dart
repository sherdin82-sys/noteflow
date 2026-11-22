class StagedAttachment {
  final String? stagingPath;
  final String originalName;
  final String mimeType;
  final int fileSizeBytes;
  final bool isSuccess;
  final String? errorCode;
  final String? errorMessage;

  const StagedAttachment({
    this.stagingPath,
    required this.originalName,
    this.mimeType = 'application/octet-stream',
    this.fileSizeBytes = 0,
    required this.isSuccess,
    this.errorCode,
    this.errorMessage,
  });

  bool get isSizeLimitExceeded => errorCode == 'SIZE_LIMIT_EXCEEDED';
  bool get isIoError => errorCode == 'IO_ERROR';

  factory StagedAttachment.fromMap(Map<String, dynamic> map) {
    final status = map['status'] as String? ?? 'SUCCESS';
    final isSuccess = status.toUpperCase() == 'SUCCESS';
    return StagedAttachment(
      stagingPath: map['stagingPath'] as String?,
      originalName: map['originalName'] as String? ?? 'attachment',
      mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
      fileSizeBytes: (map['fileSizeBytes'] as num?)?.toInt() ?? 0,
      isSuccess: isSuccess,
      errorCode: map['errorCode'] as String?,
      errorMessage: map['errorMessage'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': isSuccess ? 'SUCCESS' : 'ERROR',
      'stagingPath': stagingPath,
      'originalName': originalName,
      'mimeType': mimeType,
      'fileSizeBytes': fileSizeBytes,
      if (errorCode != null) 'errorCode': errorCode,
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }
}

class PickerResult {
  final String requestId;
  final bool isCancelled;
  final List<StagedAttachment> items;

  const PickerResult({
    required this.requestId,
    this.isCancelled = false,
    this.items = const [],
  });

  bool get hasErrors => items.any((item) => !item.isSuccess);
  List<StagedAttachment> get successfulItems => items.where((item) => item.isSuccess).toList();
  List<StagedAttachment> get failedItems => items.where((item) => !item.isSuccess).toList();

  factory PickerResult.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as List<dynamic>? ?? [];
    return PickerResult(
      requestId: map['requestId'] as String? ?? '',
      isCancelled: map['cancelled'] as bool? ?? false,
      items: rawItems
          .map((item) => StagedAttachment.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'cancelled': isCancelled,
      'items': items.map((e) => e.toMap()).toList(),
    };
  }
}
