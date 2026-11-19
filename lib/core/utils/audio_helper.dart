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
