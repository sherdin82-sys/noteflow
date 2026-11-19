import 'dart:io';

class AudioHelper {
  const AudioHelper._();

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
