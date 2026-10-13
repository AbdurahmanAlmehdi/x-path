/// Masks one stream of output that arrives in pieces.
abstract interface class StreamMasker {
  /// Adds [piece] and returns the text that is safe to show now. The end of
  /// the text may be held back while it could still turn into a secret.
  String add(String piece);

  /// Ends the stream: returns everything still held back, masked.
  String flush();
}

/// Hides known secret values in process output before it is stored or
/// streamed.
///
/// `xp_secrets` has the implementation, `SecretMasker`.
abstract interface class OutputMasker {
  /// Starts masking [secret] in all output that follows.
  void add(String secret);

  /// A masker for one stream of output, such as standard output.
  StreamMasker newStream();
}

/// An [OutputMasker] that masks nothing, for output that holds no secrets.
class NoMasking implements OutputMasker {
  /// Creates the masker.
  const new();

  @override
  void add(String secret) {}

  @override
  StreamMasker newStream() => _Unmasked();
}

class _Unmasked implements StreamMasker {
  @override
  String add(String piece) => piece;

  @override
  String flush() => '';
}
