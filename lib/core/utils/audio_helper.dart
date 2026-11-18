class AudioHelper {
  const AudioHelper._();

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
