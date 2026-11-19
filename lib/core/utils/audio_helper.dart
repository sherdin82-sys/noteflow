import 'dart:io';
import 'dart:math' as math;

class AudioHelper {
  const AudioHelper._();

  /// Creates a valid PCM 8-bit Mono RIFF WAVE audio byte buffer.
  /// Useful for pre-seeding playable demo audio or audio test fixtures.
  static List<int> createSampleWavBytes({
    int durationSeconds = 3,
    int sampleRate = 8000,
    double frequency = 440.0,
  }) {
    final numSamples = durationSeconds * sampleRate;
    final subChunk2Size = numSamples;
    final chunkSize = 36 + subChunk2Size;

    final bytes = <int>[
      // "RIFF"
      0x52, 0x49, 0x46, 0x46,
      chunkSize & 0xFF, (chunkSize >> 8) & 0xFF, (chunkSize >> 16) & 0xFF, (chunkSize >> 24) & 0xFF,
      // "WAVE"
      0x57, 0x41, 0x56, 0x45,
      // "fmt "
      0x66, 0x6D, 0x74, 0x20,
      // Subchunk1Size (16 for PCM)
      16, 0, 0, 0,
      // AudioFormat (1 for PCM)
      1, 0,
      // NumChannels (1 for Mono)
      1, 0,
      // SampleRate
      sampleRate & 0xFF, (sampleRate >> 8) & 0xFF, (sampleRate >> 16) & 0xFF, (sampleRate >> 24) & 0xFF,
      // ByteRate (SampleRate * NumChannels * BitsPerSample/8)
      sampleRate & 0xFF, (sampleRate >> 8) & 0xFF, (sampleRate >> 16) & 0xFF, (sampleRate >> 24) & 0xFF,
      // BlockAlign (NumChannels * BitsPerSample/8)
      1, 0,
      // BitsPerSample (8 bits)
      8, 0,
      // "data"
      0x64, 0x61, 0x74, 0x61,
      // Subchunk2Size
      subChunk2Size & 0xFF, (subChunk2Size >> 8) & 0xFF, (subChunk2Size >> 16) & 0xFF, (subChunk2Size >> 24) & 0xFF,
    ];

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final sample = (128 + 40 * math.sin(2 * math.pi * frequency * t)).toInt().clamp(0, 255);
      bytes.add(sample);
    }

    return bytes;
  }

  /// Safely copies an audio recording from temporary storage to the permanent
  /// application documents directory: voice_notes/{voiceNoteId}/{recordingId}.{format}.
  /// Verifies file existence and non-zero size before and after transfer.
  static Future<String?> saveRecordingToPermanentStorage({
    required String tempPath,
    required String voiceNoteId,
    required String recordingId,
    required String documentsBasePath,
    String format = 'm4a',
  }) async {
    final tempFile = File(tempPath);
    if (!await tempFile.exists()) {
      return null;
    }
    final tempSize = await tempFile.length();
    if (tempSize == 0) {
      return null;
    }

    final permanentDir = Directory('$documentsBasePath/voice_notes/$voiceNoteId');
    if (!await permanentDir.exists()) {
      await permanentDir.create(recursive: true);
    }

    final permanentFile = File('${permanentDir.path}/$recordingId.$format');

    // Safely copy temporary file to permanent storage
    await tempFile.copy(permanentFile.path);

    // Verify permanent file exists and is not empty
    if (!await permanentFile.exists() || await permanentFile.length() == 0) {
      return null;
    }

    // Only after permanent file is verified, clean up temporary file
    try {
      if (tempFile.path != permanentFile.path && await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (_) {}

    return permanentFile.path;
  }

  /// Attempts to recover or migrate an existing recording file if it has moved,
  /// is located in a temporary directory, or has a relative or outdated path.
  /// If recovered to permanent storage, returns the new permanent path.
  /// If the file cannot be found in any candidate location, returns null.
  static Future<String?> recoverOrMigrateAudioFile({
    required String storedPath,
    required String voiceNoteId,
    required String recordingId,
    required String documentsBasePath,
    String? tempBasePath,
    String format = 'm4a',
  }) async {
    final permanentDir = Directory('$documentsBasePath/voice_notes/$voiceNoteId');
    final expectedPermanentFile = File('${permanentDir.path}/$recordingId.$format');

    // Case 1: Already at expected permanent destination and valid
    if (await expectedPermanentFile.exists() && await expectedPermanentFile.length() > 0) {
      return expectedPermanentFile.path;
    }

    // Case 2: Stored path exists on disk
    if (storedPath.isNotEmpty) {
      final directFile = File(storedPath);
      if (await directFile.exists() && await directFile.length() > 0) {
        // If not already in permanent dir, migrate it
        if (!directFile.path.startsWith(permanentDir.path)) {
          if (!await permanentDir.exists()) {
            await permanentDir.create(recursive: true);
          }
          final copied = await directFile.copy(expectedPermanentFile.path);
          if (await copied.exists() && await copied.length() > 0) {
            return copied.path;
          }
        }
        return directFile.path;
      }
    }

    // Case 3: Search candidates in tempBasePath or alternate locations
    final candidatePaths = <String>[];
    if (tempBasePath != null && tempBasePath.isNotEmpty) {
      candidatePaths.add('$tempBasePath/voice_recordings_temp/$recordingId.$format');
      candidatePaths.add('$tempBasePath/voice_notes/$voiceNoteId/$recordingId.$format');
      candidatePaths.add('$tempBasePath/$recordingId.$format');
    }
    if (storedPath.isNotEmpty) {
      final fileName = storedPath.split(Platform.pathSeparator).last;
      candidatePaths.add('$documentsBasePath/voice_notes/$fileName');
      if (tempBasePath != null) {
        candidatePaths.add('$tempBasePath/$fileName');
      }
    }

    for (final candidatePath in candidatePaths) {
      final candidateFile = File(candidatePath);
      if (await candidateFile.exists() && await candidateFile.length() > 0) {
        if (!await permanentDir.exists()) {
          await permanentDir.create(recursive: true);
        }
        final copied = await candidateFile.copy(expectedPermanentFile.path);
        if (await copied.exists() && await copied.length() > 0) {
          try {
            await candidateFile.delete();
          } catch (_) {}
          return copied.path;
        }
      }
    }

    return null;
  }

  /// Resolves an audio file path, handling absolute paths as well as
  /// paths that may have migrated or moved across app reinstalls or updates.
  static Future<String?> resolveAudioPath(String storedPath, [String? baseDirectory]) async {
    if (storedPath.isEmpty) return null;

    final directFile = File(storedPath);
    if (await directFile.exists()) {
      return directFile.path;
    }

    if (baseDirectory != null && baseDirectory.isNotEmpty) {
      // Check if path contains voice_notes/...
      const marker = 'voice_notes/';
      final idx = storedPath.indexOf(marker);
      if (idx != -1) {
        final rel = storedPath.substring(idx);
        final candidate = File('$baseDirectory/$rel');
        if (await candidate.exists()) {
          return candidate.path;
        }
      }

      // Check flat filename under baseDirectory/voice_notes/
      final fileName = storedPath.split(Platform.pathSeparator).last;
      final flatCandidate = File('$baseDirectory/voice_notes/$fileName');
      if (await flatCandidate.exists()) {
        return flatCandidate.path;
      }
    }

    return null;
  }

  /// Checks if an audio file exists and has size > 0.
  static Future<bool> isAudioFileValid(String storedPath, [String? baseDirectory]) async {
    final resolved = await resolveAudioPath(storedPath, baseDirectory);
    if (resolved == null) return false;
    final file = File(resolved);
    return await file.exists() && await file.length() > 0;
  }

  /// Formats duration into a readable string: "m:ss" or "h:mm:ss"
  static String formatDuration(Duration duration) {
    if (duration.isNegative) {
      return '0:00';
    }

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final secondsStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      final minutesStr = minutes.toString().padLeft(2, '0');
      return '$hours:$minutesStr:$secondsStr';
    } else {
      return '$minutes:$secondsStr';
    }
  }

  /// Formats milliseconds into readable duration string: "m:ss" or "h:mm:ss"
  static String formatDurationMs(int milliseconds) {
    if (milliseconds <= 0) return '0:00';
    return formatDuration(Duration(milliseconds: milliseconds));
  }

  /// Formats duration with two-digit minutes: "mm:ss"
  static String formatTwoDigits(Duration duration) {
    if (duration.isNegative) {
      return '00:00';
    }
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;

    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
