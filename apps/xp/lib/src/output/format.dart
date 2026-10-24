import 'dart:convert';

import 'package:mason_logger/mason_logger.dart';

/// Lays [rows] out under [headers] in aligned columns, two spaces apart.
///
/// The last column is not padded, so lines have no trailing blanks.
String renderTable(List<String> headers, List<List<String>> rows) {
  final widths = [
    for (var column = 0; column < headers.length; column++)
      [
        headers[column],
        for (final row in rows) row[column],
      ].map((cell) => cell.length).reduce((a, b) => a > b ? a : b),
  ];
  String line(List<String> cells) => [
    for (var column = 0; column < cells.length; column++)
      if (column == cells.length - 1)
        cells[column]
      else
        cells[column].padRight(widths[column]),
  ].join('  ');
  return [line(headers), for (final row in rows) line(row)].join('\n');
}

/// Whether [formatTime] shows times in UTC rather than the local zone. Tests
/// set it, so that what they print does not depend on the machine.
bool formatTimesInUtc = false;

/// `2026-10-14 11:30 CEST`: [time] in the local zone, with its name, to the
/// minute; `-` if there is no time.
String formatTime(DateTime? time) {
  if (time == null) return '-';
  final shown = formatTimesInUtc ? time.toUtc() : time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${shown.year}-${two(shown.month)}-${two(shown.day)} '
      '${two(shown.hour)}:${two(shown.minute)} '
      '${shown.isUtc ? 'UTC' : shown.timeZoneName}';
}

/// `1.5 MB`: a size in bytes in the largest unit that keeps it above 1.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0 ? '$bytes B' : '${value.toStringAsFixed(1)} ${units[unit]}';
}

/// A name as the wire spells job states: `waitingForApproval` reads
/// `waiting_for_approval`.
String snakeCase(String name) => name.replaceAllMapped(
  RegExp('[A-Z]'),
  (match) => '_${match[0]!.toLowerCase()}',
);

/// [value] as indented JSON, the form of `--json`.
String prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

/// [state] (a run or job state on the wire) coloured by what it means, when
/// [ansi]: green done, red failed, grey cancelled, cyan running, yellow
/// waiting.
String paintState(String state, {required bool ansi}) {
  if (!ansi) return state;
  final pen = switch (state) {
    'succeeded' => lightGreen,
    'failed' => lightRed,
    'cancelled' => darkGray,
    'running' => lightCyan,
    'waiting_for_approval' ||
    'waiting_for_resume' ||
    'interrupted' => lightYellow,
    _ => null,
  };
  return pen?.wrap(state) ?? state;
}
