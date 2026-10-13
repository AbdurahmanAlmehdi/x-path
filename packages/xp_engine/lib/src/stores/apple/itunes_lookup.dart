import 'package:equatable/equatable.dart';

/// An app on the App Store as the iTunes lookup describes it.
class ItunesApp extends Equatable {
  /// Creates a description.
  const new({
    required this.bundleId,
    required this.trackId,
    required this.version,
    this.currentVersionReleaseDate,
  });

  /// The bundle id.
  final String bundleId;

  /// The numeric Apple id of the app (what altool calls `--apple-id`).
  final String trackId;

  /// The version on sale in the storefront.
  final String version;

  /// When that version went on sale.
  final DateTime? currentVersionReleaseDate;

  @override
  List<Object?> get props => [
    bundleId,
    trackId,
    version,
    currentVersionReleaseDate,
  ];
}

/// The iTunes lookup could not be read.
class ItunesLookupException implements Exception {
  /// Creates an exception with [message].
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'ItunesLookupException: $message';
}

/// The public iTunes lookup: what is on sale in a storefront.
///
/// It needs no credentials, which makes it the only source for an Apple ID
/// flavor (D-14). It is "live somewhere", not precise: Apple's CDN keeps an
/// answer for hours. `xp_adapters` has the HTTP implementation.
abstract interface class ItunesLookup {
  /// The app with [bundleId] in the storefront [country] (`us`, `sa`, ...), or
  /// `null` if the storefront has no such app.
  ///
  /// Throws an [ItunesLookupException] if the answer cannot be read.
  Future<ItunesApp?> lookup({
    required String bundleId,
    required String country,
  });
}

/// An [ItunesLookup] with the answer the test gives it.
class FakeItunesLookup implements ItunesLookup {
  /// Creates a fake that answers [answer].
  new([this.answer]);

  /// The answer; `null` means the app is not on sale.
  ItunesApp? answer;

  /// What the next call throws, once.
  ItunesLookupException? failure;

  /// Every call as `bundleId country`, oldest first.
  final lookups = <String>[];

  @override
  Future<ItunesApp?> lookup({
    required String bundleId,
    required String country,
  }) async {
    lookups.add('$bundleId $country');
    final error = failure;
    if (error != null) {
      failure = null;
      throw error;
    }
    return answer;
  }
}
