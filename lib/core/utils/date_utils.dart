import 'package:intl/intl.dart';

extension DateTimeFormatting on DateTime {
  String toDisplayDate() => DateFormat('dd/MM/yyyy').format(this);
  String toDisplayTime() => DateFormat('HH:mm:ss').format(this);
  String toDisplayDateTime() => DateFormat('dd/MM/yyyy HH:mm').format(this);
  String toIso8601Short() => toIso8601String().substring(0, 19);
}

class AppDateUtils {
  static String formatDate(DateTime dt) =>
      DateFormat('dd/MM/yyyy').format(dt);

  static String formatTime(DateTime dt) =>
      DateFormat('HH:mm:ss').format(dt);

  static String formatDateTime(DateTime dt) =>
      DateFormat('dd/MM/yyyy HH:mm').format(dt);

  static String formatIso(DateTime dt) =>
      dt.toIso8601String().substring(0, 19);

  static DateTime? tryParseIso(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static String todayIso() =>
      DateTime.now().toIso8601String().substring(0, 10);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
