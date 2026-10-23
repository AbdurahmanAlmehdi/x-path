import 'dart:convert';

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

/// `2026-10-14 09:30` (UTC), or `-` if there is no time.
String formatTime(DateTime? time) {
  if (time == null) return '-';
  final utc = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)}';
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
