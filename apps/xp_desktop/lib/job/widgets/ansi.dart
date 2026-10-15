import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';

/// A run of log text with the SGR attributes in force for it.
class AnsiRun extends Equatable {
  const new(
    this.text, {
    this.foreground,
    this.background,
    this.bold = false,
    this.dim = false,
    this.italic = false,
    this.underline = false,
    this.inverse = false,
  });

  final String text;

  /// The ANSI colour 0–15 (8–15 bright), or `null` for the default.
  final int? foreground;
  final int? background;
  final bool bold;
  final bool dim;
  final bool italic;
  final bool underline;
  final bool inverse;

  @override
  List<Object?> get props => [
    text,
    foreground,
    background,
    bold,
    dim,
    italic,
    underline,
    inverse,
  ];
}

final _escape = RegExp(r'\x1B\[([0-9;]*)([A-Za-z])');

/// Splits [line] into runs by its SGR sequences (`ESC [ … m`). Other escape
/// sequences are dropped; blink is ignored.
List<AnsiRun> parseAnsi(String line) {
  final runs = <AnsiRun>[];
  var current = const AnsiRun('');
  var start = 0;
  void flush(int end) {
    if (end > start) {
      runs.add(_with(current, text: line.substring(start, end)));
    }
  }

  for (final match in _escape.allMatches(line)) {
    flush(match.start);
    start = match.end;
    if (match.group(2) != 'm') continue;
    final codes = match.group(1)!.isEmpty
        ? const [0]
        : [
            for (final code in match.group(1)!.split(';'))
              int.tryParse(code) ?? 0,
          ];
    for (final code in codes) {
      current = _apply(current, code);
    }
  }
  flush(line.length);
  return runs;
}

AnsiRun _with(
  AnsiRun run, {
  String? text,
  int? Function()? foreground,
  int? Function()? background,
  bool? bold,
  bool? dim,
  bool? italic,
  bool? underline,
  bool? inverse,
}) => AnsiRun(
  text ?? run.text,
  foreground: foreground == null ? run.foreground : foreground(),
  background: background == null ? run.background : background(),
  bold: bold ?? run.bold,
  dim: dim ?? run.dim,
  italic: italic ?? run.italic,
  underline: underline ?? run.underline,
  inverse: inverse ?? run.inverse,
);

AnsiRun _apply(AnsiRun run, int code) => switch (code) {
  0 => const AnsiRun(''),
  1 => _with(run, bold: true),
  2 => _with(run, dim: true),
  3 => _with(run, italic: true),
  4 => _with(run, underline: true),
  7 => _with(run, inverse: true),
  22 => _with(run, bold: false, dim: false),
  23 => _with(run, italic: false),
  24 => _with(run, underline: false),
  27 => _with(run, inverse: false),
  >= 30 && <= 37 => _with(run, foreground: () => code - 30),
  39 => _with(run, foreground: () => null),
  >= 40 && <= 47 => _with(run, background: () => code - 40),
  49 => _with(run, background: () => null),
  >= 90 && <= 97 => _with(run, foreground: () => code - 90 + 8),
  >= 100 && <= 107 => _with(run, background: () => code - 100 + 8),
  _ => run,
};

/// The sixteen ANSI colours of the log (`color.log.ansi.*`).
List<Color> ansiPalette(XpColors colors) => [
  colors.logAnsiBlack,
  colors.logAnsiRed,
  colors.logAnsiGreen,
  colors.logAnsiYellow,
  colors.logAnsiBlue,
  colors.logAnsiMagenta,
  colors.logAnsiCyan,
  colors.logAnsiWhite,
  colors.logAnsiBrightBlack,
  colors.logAnsiBrightRed,
  colors.logAnsiBrightGreen,
  colors.logAnsiBrightYellow,
  colors.logAnsiBrightBlue,
  colors.logAnsiBrightMagenta,
  colors.logAnsiBrightCyan,
  colors.logAnsiBrightWhite,
];

/// [runs] as text spans in [base] (Type, "ANSI colour mapping"): bold is
/// weight 600, dim is `log.dim` on default text and unchanged on colour, a
/// background is its colour at 16% over the log, inverse is `log.text` on
/// `log.match`.
TextSpan ansiSpan(List<AnsiRun> runs, TextStyle base, XpColors colors) {
  final palette = ansiPalette(colors);
  return TextSpan(
    style: base,
    children: [
      for (final run in runs)
        TextSpan(
          text: run.text,
          style: TextStyle(
            color: run.inverse
                ? colors.logText
                : run.foreground != null
                ? palette[run.foreground!]
                : run.dim
                ? colors.logDim
                : null,
            backgroundColor: run.inverse
                ? colors.logMatch
                : run.background == null
                ? null
                : palette[run.background!].withValues(alpha: 0.16),
            fontWeight: run.bold ? FontWeight.w600 : null,
            fontStyle: run.italic ? FontStyle.italic : null,
            decoration: run.underline ? TextDecoration.underline : null,
          ),
        ),
    ],
  );
}
