/// Keeps the machine awake.
///
/// A job in the middle of a build must not be put to sleep (D-18).
/// `xp_adapters` has implementations for macOS and Linux.
abstract interface class PowerAssertion {
  /// Starts keeping the machine awake.
  Future<void> hold();

  /// Stops keeping the machine awake.
  Future<void> release();
}

/// Shares one [PowerAssertion] between callers: the machine is kept awake
/// from the first [hold] to the matching last [release].
class ReferenceCountedPowerAssertion implements PowerAssertion {
  /// Creates an assertion that holds [_inner] while anyone holds this one.
  new(this._inner);

  final PowerAssertion _inner;
  var _holders = 0;

  /// How many holds have not been released.
  int get holders => _holders;

  @override
  Future<void> hold() async {
    if (_holders++ == 0) await _inner.hold();
  }

  @override
  Future<void> release() async {
    if (_holders == 0) return;
    if (--_holders == 0) await _inner.release();
  }
}

/// A [PowerAssertion] that keeps nothing awake, for machines that cannot and
/// for tests. It counts what it was asked.
class NoPowerAssertion implements PowerAssertion {
  /// Creates the assertion.
  new();

  /// How many times [hold] was called.
  int holds = 0;

  /// How many times [release] was called.
  int releases = 0;

  @override
  Future<void> hold() async => holds++;

  @override
  Future<void> release() async => releases++;
}
