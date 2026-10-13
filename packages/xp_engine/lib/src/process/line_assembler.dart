/// Cuts text that arrives in pieces into lines.
///
/// `\n`, `\r\n` and a lone `\r` (progress bars rewrite their line with it) end
/// a line. A line longer than [maxLength] characters is cut there, so that a
/// process that never prints a newline cannot grow the engine's memory.
class LineAssembler {
  /// Creates an assembler that cuts lines at [maxLength] characters.
  new({this.maxLength = defaultMaxLength}) : assert(maxLength > 0, 'positive');

  /// The longest line, in characters, unless told otherwise.
  static const defaultMaxLength = 16384;

  /// The longest line, in characters.
  final int maxLength;

  final _line = StringBuffer();
  var _length = 0;
  var _afterCarriageReturn = false;
  var _afterCut = false;

  /// Adds [piece] and returns the lines it completed, without line endings.
  List<String> add(String piece) {
    final lines = <String>[];
    for (final unit in piece.codeUnits) {
      if (unit == 0x0A && _afterCarriageReturn) {
        _afterCarriageReturn = false;
        continue;
      }
      _afterCarriageReturn = unit == 0x0D;
      if (unit == 0x0A || unit == 0x0D) {
        // A line that was cut exactly at its end has no rest to emit.
        if (!(_afterCut && _length == 0)) lines.add(_take());
        _afterCut = false;
        continue;
      }
      _afterCut = false;
      _line.writeCharCode(unit);
      if (++_length >= maxLength) {
        lines.add(_take());
        _afterCut = true;
      }
    }
    return lines;
  }

  /// Ends the text: returns the unfinished line, or `null` if there is none.
  String? flush() {
    if (_length == 0) return null;
    return _take();
  }

  String _take() {
    final text = _line.toString();
    _line.clear();
    _length = 0;
    return text;
  }
}
