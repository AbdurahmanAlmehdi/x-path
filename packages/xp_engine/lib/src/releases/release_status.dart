import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/releases/release_record.dart';
import 'package:xp_engine/src/stores/apple/app_store_connect.dart';
import 'package:xp_engine/src/stores/apple/asc_credential_source.dart';
import 'package:xp_engine/src/stores/apple/asc_exceptions.dart';
import 'package:xp_engine/src/stores/apple/asc_key.dart';
import 'package:xp_engine/src/stores/apple/asc_models.dart';
import 'package:xp_engine/src/stores/apple/itunes_lookup.dart';
import 'package:xp_engine/src/stores/play/google_play.dart';
import 'package:xp_engine/src/stores/play/play_credential_source.dart';
import 'package:xp_engine/src/stores/play/play_exceptions.dart';
import 'package:xp_engine/src/stores/play/play_models.dart';
import 'package:xp_engine/src/versioning/app_version.dart';

/// How long an answer of a store counts as fresh. The engine asks a store
/// about a release at most this often, unless the owner refreshes (D-14).
const storeStatusCacheFor = Duration(minutes: 10);

/// What a store said about a release.
class StoreReading extends Equatable {
  /// Creates a reading.
  const new({required this.source, required this.detail, this.state});

  /// The status the store reports, or `null` when what it said does not
  /// change the status (an App Store version that is not submitted yet, a
  /// version the store does not know yet).
  final StoreState? state;

  /// Where the answer came from.
  final StatusSource source;

  /// What the store said, as it said it.
  final String detail;

  @override
  List<Object?> get props => [state, source, detail];
}

/// Asks one store about a release.
abstract interface class StoreStatusSource {
  /// The store it asks.
  ReleaseStore get store;

  /// What the store says about [release], whose entry for the store is
  /// [entry], or `null` if the store cannot be read: there is no API key or
  /// service account, and the owner presses the button instead (D-14, D-15).
  ///
  /// Throws what the store's client throws when the store fails.
  Future<StoreReading?> read(ReleaseRecord release, StoreEntry entry);
}

/// App Store Connect (an API key: the `appVersionState` of the version), or
/// the iTunes lookup when there is no key (an Apple ID flavor: the version is
/// on sale or it is not) (D-14).
class AppleStatusSource implements StoreStatusSource {
  /// Creates the source.
  const new({
    required this._credentials,
    required this._connect,
    required this._itunes,
  });

  final AscCredentialSource _credentials;
  final AppStoreConnectFactory _connect;
  final ItunesLookup _itunes;

  @override
  ReleaseStore get store => ReleaseStore.apple;

  @override
  Future<StoreReading?> read(ReleaseRecord release, StoreEntry entry) async {
    final bundleId = entry.identity['bundleId']!;
    final key = await _credentials.forBundleId(bundleId);
    if (key != null) return await _fromConnect(release, bundleId, key);
    return await _fromLookup(release, bundleId, entry.identity['country']!);
  }

  Future<StoreReading> _fromConnect(
    ReleaseRecord release,
    String bundleId,
    AscKey key,
  ) async {
    final client = _connect(key);
    final app = await client.findApp(bundleId);
    if (app == null) {
      return StoreReading(
        source: StatusSource.api,
        detail: 'App Store Connect has no app with bundle id $bundleId.',
      );
    }
    final versions = await client.versions(app.id);
    final version = versions
        .where((version) => version.versionString == release.version)
        .firstOrNull;
    if (version == null) {
      return StoreReading(
        source: StatusSource.api,
        detail: 'App Store Connect has no version ${release.version} yet.',
      );
    }
    final state = version.state;
    return StoreReading(
      source: StatusSource.api,
      detail: state == AppVersionState.unknown ? 'UNKNOWN' : state.wire,
      state: switch (state) {
        _ when state.isLive => StoreState.live,
        _ when state.isApprovedNotLive => StoreState.approved,
        _ when state.isInReview => StoreState.inReview,
        _ when state.isRejected => StoreState.rejected,
        _ => null,
      },
    );
  }

  Future<StoreReading> _fromLookup(
    ReleaseRecord release,
    String bundleId,
    String country,
  ) async {
    final app = await _itunes.lookup(bundleId: bundleId, country: country);
    if (app == null) {
      return StoreReading(
        source: StatusSource.lookup,
        detail: 'Not on sale in the $country storefront.',
      );
    }
    final wanted = VersionName.parse(release.version);
    VersionName? onSale;
    try {
      onSale = VersionName.parse(app.version);
    } on FormatException {
      // A version string this engine cannot read says nothing about ours.
    }
    return StoreReading(
      source: StatusSource.lookup,
      detail: 'On sale: ${app.version}',
      // A higher version on sale replaced ours, which went live before it.
      state: onSale != null && !(wanted > onSale) ? StoreState.live : null,
    );
  }
}

/// Google Play (`tracks.releases.list`: the review state of the release that
/// holds the version code), or nothing when there is no service account and
/// the owner presses "Play: live" (D-15).
class PlayStatusSource implements StoreStatusSource {
  /// Creates the source.
  const new({required this._credentials, required this._connect});

  final PlayCredentialSource _credentials;
  final GooglePlayFactory _connect;

  @override
  ReleaseStore get store => ReleaseStore.play;

  @override
  Future<StoreReading?> read(ReleaseRecord release, StoreEntry entry) async {
    final packageName = entry.identity['packageName']!;
    final track = entry.identity['track']!;
    final account = await _credentials.forAndroidAppId(packageName);
    if (account == null) return null;
    final releases = await _connect(account).releases(packageName, track);
    final found = releases
        .where((summary) => summary.versionCodes.contains(release.build))
        .firstOrNull;
    if (found == null) {
      return StoreReading(
        source: StatusSource.api,
        detail:
            'Google Play has no release with version code ${release.build} '
            'on the $track track.',
      );
    }
    final state = found.state;
    return StoreReading(
      source: StatusSource.api,
      detail: state == PlayLifecycleState.unknown ? 'UNKNOWN' : state.wire,
      state: switch (state) {
        PlayLifecycleState.published => StoreState.live,
        PlayLifecycleState.approvedNotPublished => StoreState.approved,
        PlayLifecycleState.inReview => StoreState.inReview,
        PlayLifecycleState.notApproved => StoreState.rejected,
        _ => null,
      },
    );
  }
}

/// What asking a store came to.
class StorePoll extends Equatable {
  /// Creates a poll.
  const new({this.reading, this.note});

  /// What the store said, or `null` if it could not be read.
  final StoreReading? reading;

  /// Why it could not be read.
  final String? note;

  @override
  List<Object?> get props => [reading, note];
}

/// Asks the stores how their reviews of a release stand (D-14, D-15).
///
/// The engine asks at most every [cacheFor] (ten minutes): an entry that was
/// checked more recently is not due. A failing store is checked just as
/// rarely, so a store that is down is not hammered.
class ReleaseStatusPoller {
  /// Creates the poller over the [sources] of the stores.
  new({
    required Iterable<StoreStatusSource> sources,
    required this._clock,
    this.cacheFor = storeStatusCacheFor,
  }) : _sources = {for (final source in sources) source.store: source};

  /// How long an answer counts as fresh.
  final Duration cacheFor;

  final Map<ReleaseStore, StoreStatusSource> _sources;
  final Clock _clock;

  /// Whether the store of [entry] should be asked now: never, or not within
  /// [cacheFor].
  bool isDue(StoreEntry entry) {
    final checked = entry.checkedAt;
    return checked == null || !checked.add(cacheFor).isAfter(_clock.now());
  }

  /// Asks the store of [entry] about [release].
  ///
  /// A store that fails is reported in the [StorePoll.note], never thrown:
  /// the release keeps its status.
  Future<StorePoll> poll(ReleaseRecord release, StoreEntry entry) async {
    final source = _sources[entry.store];
    if (source == null) {
      return StorePoll(
        note: 'This engine cannot read ${entry.store.wire} yet.',
      );
    }
    try {
      final reading = await source.read(release, entry);
      return reading == null
          ? StorePoll(note: _unreadable(entry.store))
          : StorePoll(reading: reading);
    } on AppStoreConnectException catch (error) {
      return StorePoll(note: 'App Store Connect: ${error.message}');
    } on ItunesLookupException catch (error) {
      return StorePoll(note: 'iTunes lookup: ${error.message}');
    } on PlayException catch (error) {
      return StorePoll(note: 'Google Play: ${error.message}');
    }
  }

  static String _unreadable(ReleaseStore store) => switch (store) {
    ReleaseStore.apple =>
      'No App Store Connect API key: press "Apple approved" / "Apple live".',
    ReleaseStore.play =>
      'No Google Play service account: press "Play: live" when it is.',
  };
}

/// A [StoreStatusSource] that says what the test tells it to.
class FakeStoreStatusSource implements StoreStatusSource {
  /// Creates a source for [store] that answers [reading].
  new(this.store, [this.reading]);

  @override
  final ReleaseStore store;

  /// The answer; `null` means the store cannot be read.
  StoreReading? reading;

  /// What the next call throws, once.
  Object? failure;

  /// Every call as the release id and the build, oldest first.
  final reads = <String>[];

  @override
  Future<StoreReading?> read(ReleaseRecord release, StoreEntry entry) async {
    reads.add('${release.id} ${release.build}');
    final error = failure;
    if (error != null) {
      failure = null;
      // The test hands over a store exception.
      // ignore: only_throw_errors
      throw error;
    }
    return reading;
  }
}
