import 'package:intl/intl.dart';

/// Error whose message is safe to show to the user.
class AppException implements Exception {
  final String message;
  AppException(this.message);
  @override
  String toString() => message;
}

// ---------------------------------------------------------------- money
// All amounts are stored as integer paisa (1 PKR = 100 paisa) so that
// no floating point rounding can ever affect a balance.

/// Parses user input such as "1,250.50" into paisa. Returns null if invalid.
int? parseMoney(String input) {
  var s = input.trim().replaceAll(',', '').replaceAll(' ', '');
  s = s.replaceFirst(RegExp(r'^(pkr|rs\.?)', caseSensitive: false), '');
  final m = RegExp(r'^(\d{1,12})(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final frac = m.group(2) == null ? 0 : int.parse(m.group(2)!.padRight(2, '0'));
  return whole * 100 + frac;
}

/// Plain number for text fields (no currency, no grouping).
String moneyInput(int paisa) {
  final whole = paisa ~/ 100;
  final frac = paisa % 100;
  return frac == 0 ? '$whole' : '$whole.${frac.toString().padLeft(2, '0')}';
}

String formatMoney(int paisa, {String currency = 'PKR'}) {
  final neg = paisa < 0;
  final a = paisa.abs();
  final w = NumberFormat('#,##0').format(a ~/ 100);
  final f = a % 100 == 0 ? '' : '.${(a % 100).toString().padLeft(2, '0')}';
  return '${neg ? '-' : ''}$currency $w$f';
}

// ---------------------------------------------------------------- dates
// Dates are stored as local-time text: 'yyyy-MM-dd', 'HH:mm' and
// 'yyyy-MM-ddTHH:mm:ss' (these sort correctly as plain strings).

String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String monthKey(DateTime d) => DateFormat('yyyy-MM').format(d);
String isoLocal(DateTime d) => DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(d);
String timeKey(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime combine(String date, String? time) {
  final d = DateTime.parse(date);
  if (time == null) return d;
  final p = time.split(':');
  return DateTime(d.year, d.month, d.day, int.parse(p[0]), int.parse(p[1]));
}

/// Half-open range [start, end).
class Range {
  final DateTime start;
  final DateTime end;
  const Range(this.start, this.end);
}

Range dayRange(DateTime d) =>
    Range(DateTime(d.year, d.month, d.day), DateTime(d.year, d.month, d.day + 1));

/// Monday to Sunday.
Range weekRange(DateTime d) {
  final s = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  return Range(s, DateTime(s.year, s.month, s.day + 7));
}

Range monthRange(DateTime d) =>
    Range(DateTime(d.year, d.month, 1), DateTime(d.year, d.month + 1, 1));

// ---------------------------------------------------------------- budget

class MonthSummary {
  final int income;
  final int expense;
  final int budget;
  const MonthSummary(this.income, this.expense, this.budget);

  /// Budget left to spend (negative when over budget).
  int get remainingBudget => budget - expense;

  /// Income minus expenses.
  int get net => income - expense;
}

// ---------------------------------------------------------------- loans

bool isOverdue(String? dueDate, int outstanding, DateTime now) {
  if (dueDate == null || outstanding <= 0) return false;
  return dueDate.compareTo(dateKey(now)) < 0;
}

// ---------------------------------------------------------------- reminders

/// n-th occurrence (0 = the original date) of a repeating reminder.
DateTime occurrenceAt(DateTime at, String repeat, int n) {
  switch (repeat) {
    case 'daily':
      return DateTime(at.year, at.month, at.day + n, at.hour, at.minute);
    case 'weekly':
      return DateTime(at.year, at.month, at.day + 7 * n, at.hour, at.minute);
    case 'monthly':
      final total = at.month - 1 + n;
      final y = at.year + total ~/ 12;
      final m = total % 12 + 1;
      final last = DateTime(y, m + 1, 0).day;
      return DateTime(y, m, at.day > last ? last : at.day, at.hour, at.minute);
    default:
      return at;
  }
}

/// Up to [max] occurrences that are not before [from].
List<DateTime> upcomingOccurrences(
    DateTime at, String repeat, DateTime from, int max) {
  final out = <DateTime>[];
  if (repeat == 'none') {
    if (!at.isBefore(from)) out.add(at);
    return out;
  }
  var n = 0;
  if (at.isBefore(from)) {
    final gap = from.difference(at).inDays;
    n = repeat == 'daily'
        ? gap - 1
        : (repeat == 'weekly' ? gap ~/ 7 - 1 : gap ~/ 31 - 1);
    if (n < 0) n = 0;
  }
  var guard = 0;
  while (out.length < max && guard++ < 100000) {
    final o = occurrenceAt(at, repeat, n++);
    if (!o.isBefore(from)) out.add(o);
  }
  return out;
}

// ---------------------------------------------------------------- display

String fmtDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);
String fmtTime(DateTime d) => DateFormat('h:mm a').format(d);
String fmtDateTime(DateTime d) => DateFormat('d MMM yyyy, h:mm a').format(d);
