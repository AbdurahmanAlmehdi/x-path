/// Formats from the Run Sheet's Formatting guide.
library;

import 'package:intl/intl.dart';

/// A duration: `0.4s` under a second, `41s`, `6m 12s`, `1h 04m` (seconds
/// dropped from an hour up).
String formatDuration(Duration duration) {
  if (duration.isNegative) return '0s';
  if (duration < const Duration(seconds: 1)) {
    return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  if (minutes > 0) return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  return '${seconds}s';
}

/// How long something that started at [start] ran: until [end], or until
/// [now] while it runs. `null` when it never started.
Duration? elapsed(DateTime? start, DateTime? end, DateTime now) {
  if (start == null) return null;
  return (end ?? now).difference(start);
}

String _two(int value) => value.toString().padLeft(2, '0');

/// A time of day in the 24-hour clock of this Mac: `14:02`.
String formatTime(DateTime time) {
  final local = time.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// A time of day with seconds, as logs show it: `14:02:41`.
String formatClock(DateTime time) {
  final local = time.toLocal();
  return '${formatTime(local)}:${_two(local.second)}';
}

/// The seven characters of a commit that the UI shows: `9a3bc0d`.
String shortSha(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;

/// A version and its build: `5.4.1 (3283)`.
String versionLabel(String version, [int? build]) =>
    build == null ? version : '$version ($build)';

/// A pubspec version (`5.5.0+3284`) as the UI writes it: `5.5.0 (3284)`.
String pubspecLabel(String pubspec) {
  final [name, ...rest] = pubspec.split('+');
  return rest.isEmpty ? name : '$name (${rest.join('+')})';
}

/// A size in decimal units, as Finder writes it: `812 KB`, `38.9 GB`. One
/// decimal below 100, none from 100 up; a non-breaking space before the unit.
String formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final number = unit == 0 || value >= 100
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$number ${units[unit]}';
}

/// What is left until [deadline], for an expiry: `23h 51m`, `42m`, `0m`.
String formatCountdown(DateTime deadline, DateTime now) {
  final left = deadline.difference(now);
  if (left.isNegative) return '0m';
  final hours = left.inHours;
  final minutes = left.inMinutes.remainder(60);
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A date and time for timelines, in this Mac's time zone: `Oct 13 14:09`.
String formatDateTime(DateTime time) {
  final local = time.toLocal();
  return '${_months[local.month - 1]} ${local.day} ${formatTime(local)}';
}

/// A time as a list shows it: `14:02` within a day of [now], else
/// `Oct 11 14:02`.
String formatWhen(DateTime time, DateTime now) =>
    now.difference(time) < const Duration(hours: 24)
    ? formatTime(time)
    : formatDateTime(time);

/// A time in full, for a tooltip, in this Mac's time zone:
/// `Tue, Oct 13, 2026 14:02:41 CEST`.
String formatAbsolute(DateTime time) {
  final local = time.toLocal();
  return '${DateFormat('EEE, MMM d, y HH:mm:ss').format(local)} '
      '${local.timeZoneName}';
}

/// A count with thousands separators: `1,284`.
String formatCount(int count) => NumberFormat.decimalPattern().format(count);

/// When something happened, relative to [now] for the last day (Formatting,
/// Times): `just now`, `4m ago`, `2h ago`; then `Yesterday 14:02`, then
/// `Oct 11 14:02`.
String formatRelative(
  DateTime time,
  DateTime now, {
  required String justNow,
  required String Function(String duration) ago,
  required String Function(String time) yesterday,
}) {
  final since = now.difference(time);
  if (since < const Duration(minutes: 1)) return justNow;
  if (since < const Duration(hours: 1)) return ago('${since.inMinutes}m');
  if (since < const Duration(hours: 24)) return ago('${since.inHours}h');
  final day = DateTime(now.year, now.month, now.day);
  final local = time.toLocal();
  if (!local.isBefore(day.subtract(const Duration(days: 1)))) {
    return yesterday(formatTime(local));
  }
  return formatDateTime(local);
}
