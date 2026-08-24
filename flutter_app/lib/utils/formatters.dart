import 'package:intl/intl.dart';

final DateFormat _displayDate = DateFormat('dd/MM/yyyy');

/// Renders a stored date (an ISO `yyyy-MM-dd` string) in the day-first
/// form used everywhere in the UI, falling back to the raw value if it
/// cannot be parsed — dates are stored as text, so a malformed row
/// should still be readable rather than blank.
String formatDisplayDate(String stored) {
  try {
    return _displayDate.format(DateTime.parse(stored));
  } catch (_) {
    return stored;
  }
}
