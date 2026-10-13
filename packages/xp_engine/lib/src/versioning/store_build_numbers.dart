import 'package:equatable/equatable.dart';

/// The build numbers a store has seen for an app.
class StoreBuilds extends Equatable {
  /// Creates the record of [used] build numbers.
  const new(this.used);

  /// Every build number the store has, on any track or version.
  final Set<int> used;

  /// The largest of [used], or 0 if the store has none.
  int get highest => used.fold(0, (a, b) => a > b ? a : b);

  @override
  List<Object?> get props => [used];
}

/// What the stores know about the build numbers of an app (D-11, D-22).
///
/// App Store Connect (builds) and Google Play (version codes) implement it in
/// Phase 10; [FakeStoreBuildNumbers] stands in until then.
abstract interface class StoreBuildNumbers {
  /// The build numbers of the app with iOS bundle id [iosBundleId] and
  /// Android application id [androidAppId], either of which may be absent.
  ///
  /// Returns `null` if the stores cannot be asked, for example because there
  /// are no credentials or the network is down. The caller then goes on with
  /// what tags and the counter say and tells the owner.
  Future<StoreBuilds?> lookup({String? iosBundleId, String? androidAppId});
}

/// A [StoreBuildNumbers] with the answer the test gives it.
class FakeStoreBuildNumbers implements StoreBuildNumbers {
  /// Creates a fake that answers [builds].
  new([this.builds]);

  /// The answer; `null` means the stores cannot be asked.
  StoreBuilds? builds;

  /// Every call as `iosBundleId androidAppId`, oldest first.
  final lookups = <String>[];

  @override
  Future<StoreBuilds?> lookup({
    String? iosBundleId,
    String? androidAppId,
  }) async {
    lookups.add('$iosBundleId $androidAppId');
    return builds;
  }
}
