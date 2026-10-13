import 'dart:async';

/// Hides known secret values in process output before it is stored or
/// streamed.
///
/// A masker knows a set of secret values. [mask] replaces every occurrence of
/// one with [replacement]. For output that arrives in pieces, a
/// [MaskingStream] also catches a secret that is split between two pieces.
///
/// - **Multi-line secrets** (PEM keys, JSON service accounts) are masked line
///   by line: each line of the secret is a pattern of its own, trimmed of
///   surrounding whitespace, so output that is re-indented or has its line
///   endings changed is still masked.
/// - **Overlapping secrets** are masked as one: the matches are merged, so a
///   secret that overlaps another one leaves no tail showing.
/// - **Short values** are ignored. A value shorter than [minLength] characters
///   (after trimming) would match ordinary text, such as `true` or `1`, and
///   hide far more than it protects. A short secret is not protected by the
///   masker at all, so credentials must be longer than that.
class SecretMasker {
  /// Creates a masker that knows [secrets].
  new({
    Iterable<String> secrets = const [],
    this.replacement = '***',
    this.minLength = defaultMinLength,
  }) {
    secrets.forEach(add);
  }

  /// Secrets shorter than this many characters are not masked.
  static const defaultMinLength = 6;

  /// What a secret is replaced with.
  final String replacement;

  /// The shortest line of a secret that is masked.
  final int minLength;

  final _patterns = <String>{};

  /// The patterns, longest first.
  List<String> _sorted = const [];

  /// Starts masking [secret], one pattern for each of its lines.
  void add(String secret) {
    for (final line in secret.split(RegExp(r'\r\n|\r|\n'))) {
      final trimmed = line.trim();
      if (trimmed.length >= minLength) _patterns.add(trimmed);
    }
    _sorted = _patterns.toList()..sort((a, b) => b.length - a.length);
  }

  /// Replaces every known secret in [text].
  String mask(String text) => _replace(text, _matches(text));

  /// Masks a stream of text pieces, for example a process's output.
  ///
  /// A secret split between two pieces is still masked. The stream ends with
  /// whatever was held back.
  Stream<String> maskStream(Stream<String> pieces) async* {
    final masking = MaskingStream(this);
    await for (final piece in pieces) {
      final safe = masking.add(piece);
      if (safe.isNotEmpty) yield safe;
    }
    final rest = masking.flush();
    if (rest.isNotEmpty) yield rest;
  }

  /// The merged `[start, end)` ranges of [text] that hold a secret.
  List<(int, int)> _matches(String text) {
    final ranges = <(int, int)>[];
    for (final pattern in _sorted) {
      for (var at = text.indexOf(pattern); at >= 0;) {
        ranges.add((at, at + pattern.length));
        at = text.indexOf(pattern, at + 1);
      }
    }
    ranges.sort((a, b) => a.$1 - b.$1);
    final merged = <(int, int)>[];
    for (final range in ranges) {
      if (merged.isNotEmpty && range.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, range.$2 > last.$2 ? range.$2 : last.$2));
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  String _replace(String text, List<(int, int)> ranges) {
    final out = StringBuffer();
    var from = 0;
    for (final (start, end) in ranges) {
      out
        ..write(text.substring(from, start))
        ..write(replacement);
      from = end;
    }
    return (out..write(text.substring(from))).toString();
  }

  /// How many characters at the end of [text] could still turn into a secret
  /// once more text follows: the longest suffix that is a proper prefix of a
  /// pattern.
  int _pendingLength(String text) {
    var longest = 0;
    for (final pattern in _sorted) {
      final most = pattern.length - 1 < text.length
          ? pattern.length - 1
          : text.length;
      for (var length = most; length > longest; length--) {
        if (text.endsWith(pattern.substring(0, length))) {
          longest = length;
          break;
        }
      }
    }
    return longest;
  }
}

/// Masks one stream of output that arrives in pieces.
///
/// Use one for standard output and another for standard error. Secrets added
/// to the masker later apply to the pieces that follow.
///
/// A piece may end in the middle of a secret. [add] holds back the end of the
/// text for as long as it could still become a secret, and releases it with
/// the next piece, or with [flush] when the stream ends.
class MaskingStream {
  /// Creates a stream that masks with the secrets of [_masker].
  new(this._masker);

  final SecretMasker _masker;
  var _held = '';

  /// Adds [piece] and returns the text that is now safe to show.
  String add(String piece) {
    final text = _held + piece;
    final matches = _masker._matches(text);
    var safeEnd = text.length - _masker._pendingLength(text);
    // Never cut through a secret that was found: hold all of it back.
    for (final (start, end) in matches) {
      if (start < safeEnd && safeEnd < end) safeEnd = start;
    }
    _held = text.substring(safeEnd);
    return _masker._replace(text.substring(0, safeEnd), [
      for (final (start, end) in matches)
        if (end <= safeEnd) (start, end),
    ]);
  }

  /// Ends the stream: returns everything still held back, masked.
  String flush() {
    final rest = _masker.mask(_held);
    _held = '';
    return rest;
  }
}
