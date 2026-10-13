import 'package:equatable/equatable.dart';

/// The build numbers a store has seen for an app.
class StoreBuilds extends Equatable {
  /// Creates the record of [used] build numbers. [unreadable] names the
  /// stores that were asked and could not answer.
  const new(this.used, {this.unreadable = const {}});

  /// Every build number the stores have, on any track or version.
  final Set<int> used;

  /// The stores that could not be read, such as `Google Play`. [used] lacks
  /// their build numbers.
  final Set<String> unreadable;

  /// The largest of [used], or 0 if the store has none.
  int get highest => used.fold(0, (a, b) => a > b ? a : b);

  @override
  List<Object?> get props => [used, unreadable];
}

/// What the stores know about the build numbers of an app (D-11, D-22).
///
/// App Store Connect (builds) and Google Play (version codes) implement it;
/// [CombinedStoreBuildNumbers] asks both.
abstract interface class StoreBuildNumbers {
  /// The build numbers of the app with iOS bundle id [iosBundleId] and
  /// Android application id [androidAppId], either of which may be absent.
  ///
  /// Returns `null` if the stores cannot be asked, for example because there
  /// are no credentials or the network is down. The caller then goes on with
  /// what tags and the counter say and tells the owner.
  Future<StoreBuilds?> lookup({String? iosBundleId, String? androidAppId});
}

/// The build numbers of both stores: App Store Connect for the iOS bundle id,
/// Google Play for the Android application id (D-22).
///
/// A store is asked only when the app has an id on it. One that cannot be
/// read is named in [StoreBuilds.unreadable], and the build numbers of the
/// other still count. The answer is `null` if the app has an id on a store and
/// no store could be read, or on none.
class CombinedStoreBuildNumbers implements StoreBuildNumbers {
  /// Creates the combination of [apple] and [play].
  const new({required this.apple, required this.play});

  /// The name [StoreBuilds.unreadable] uses for App Store Connect.
  static const appleName = 'App Store Connect';

  /// The name [StoreBuilds.unreadable] uses for Google Play.
  static const playName = 'Google Play';

  /// Answers for iOS.
  final StoreBuildNumbers apple;

  /// Answers for Android.
  final StoreBuildNumbers play;

  @override
  Future<StoreBuilds?> lookup({
    String? iosBundleId,
    String? androidAppId,
  }) async {
    final used = <int>{};
    final unreadable = <String>{};
    var read = false;
    for (final (name, source, ios, android) in [
      if (iosBundleId != null) (appleName, apple, iosBundleId, null),
      if (androidAppId != null) (playName, play, null, androidAppId),
    ]) {
      final builds = await source.lookup(
        iosBundleId: ios,
        androidAppId: android,
      );
      if (builds == null) {
        unreadable.add(name);
      } else {
        read = true;
        used.addAll(builds.used);
      }
    }
    return read ? StoreBuilds(used, unreadable: unreadable) : null;
  }
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
