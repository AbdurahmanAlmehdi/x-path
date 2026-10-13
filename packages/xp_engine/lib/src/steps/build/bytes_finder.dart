/// Looks for several byte strings in a stream of chunks, in one pass.
///
/// A match may span chunks. The search is a plain byte comparison, which is
/// what `strings -a | grep` finds for text that is printable ASCII.
class BytesFinder {
  /// Creates a finder for [needles]. An empty needle is found at once.
  new(Iterable<List<int>> needles)
    : _states = [for (final needle in needles) _Needle(needle)];

  final List<_Needle> _states;

  /// Looks at the next [chunk].
  void add(List<int> chunk) {
    for (final state in _states) {
      state.add(chunk);
    }
  }

  /// The needles that were not found so far, in the order they were given.
  List<List<int>> get missing => [
    for (final state in _states)
      if (!state.found) state.needle,
  ];
}

/// One needle, matched with the Knuth-Morris-Pratt automaton.
class _Needle {
  new(this.needle) : _failure = _failureTable(needle);

  final List<int> needle;
  final List<int> _failure;
  var _matched = 0;

  bool get found => _matched == needle.length;

  void add(List<int> chunk) {
    if (found) return;
    for (final byte in chunk) {
      while (_matched > 0 && needle[_matched] != byte) {
        _matched = _failure[_matched - 1];
      }
      if (needle[_matched] == byte) _matched++;
      if (found) return;
    }
  }

  static List<int> _failureTable(List<int> needle) {
    final table = List.filled(needle.length, 0);
    var k = 0;
    for (var i = 1; i < needle.length; i++) {
      while (k > 0 && needle[k] != needle[i]) {
        k = table[k - 1];
      }
      if (needle[k] == needle[i]) k++;
      table[i] = k;
    }
    return table;
  }
}
