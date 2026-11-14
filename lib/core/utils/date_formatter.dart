class DateFormatter {
  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static const List<String> _fullMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static const List<String> _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  static String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  static String formatSmart(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24 && dateTime.day == now.day && dateTime.month == now.month && dateTime.year == now.year) {
      return _formatTime(dateTime);
    } else if (difference.inDays < 2 && now.day - dateTime.day == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return _weekdays[dateTime.weekday - 1];
    } else if (dateTime.year == now.year) {
      return '${_months[dateTime.month - 1]} ${dateTime.day}';
    } else {
      return '${_months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
    }
  }

  static String formatFull(DateTime dateTime) {
    final month = _fullMonths[dateTime.month - 1];
    final time = _formatTime(dateTime);
    return '$month ${dateTime.day}, ${dateTime.year} • $time';
  }
}
