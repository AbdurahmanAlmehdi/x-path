import 'dart:io' as io;

/// Asks the person at the terminal for a secret without showing what they
/// type, or for a plain answer. Tests pass a fake.
abstract interface class SecretPrompt {
  /// Whether there is a person to ask: standard input is a terminal.
  bool get interactive;

  /// Shows [question] and reads one line, with the echo off for a
  /// [secret]. The line break is not part of the answer.
  String ask(String question, {bool secret = true});
}

/// The [SecretPrompt] of the real terminal.
///
/// The question goes to standard error, so standard output stays clean for
/// `--json`.
class TerminalSecretPrompt implements SecretPrompt {
  /// Creates the prompt on `stdin` and `stderr`, the process's by default.
  const new({this._stdin, this._stderr});

  final io.Stdin? _stdin;
  final io.IOSink? _stderr;

  io.Stdin get _in => _stdin ?? io.stdin;
  io.IOSink get _out => _stderr ?? io.stderr;

  @override
  bool get interactive => _in.hasTerminal;

  @override
  String ask(String question, {bool secret = true}) {
    _out.write('$question: ');
    if (!secret) return _in.readLineSync() ?? '';
    final echo = _in.echoMode;
    _in.echoMode = false;
    try {
      return _in.readLineSync() ?? '';
    } finally {
      _in.echoMode = echo;
      _out.writeln();
    }
  }
}
