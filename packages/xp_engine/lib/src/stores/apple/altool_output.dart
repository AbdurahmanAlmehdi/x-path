import 'package:equatable/equatable.dart';

/// The lines altool prints when Apple or altool refused something. altool can
/// exit 0 after printing one (a closed version train, for example), so the
/// output decides, not the exit code (C:752-762, K:559-569).
///
/// - `ERROR:` marks a line of altool 27, after a timestamp; `ERROR ITMS-90186:`
///   is Apple's own marker;
/// - `*** Error:`, `Validation failed`, `UPLOAD FAILED` and `VALIDATION_ERROR`
///   are the markers of the older altool and of the reference scripts;
/// - `The upload failed`, `Failed to upload package`, `Failed to validate
///   package` and `Unable to authenticate` are the messages around them.
final _errorMarkers = [
  RegExp(r'\bERROR\b[: ]'),
  RegExp(r'\*\*\* Error:'),
  RegExp('validation failed', caseSensitive: false),
  RegExp('upload failed', caseSensitive: false),
  RegExp('VALIDATION_ERROR'),
  RegExp('failed to (upload|validate) package', caseSensitive: false),
  RegExp('unable to authenticate', caseSensitive: false),
];

final _successMarkers = [
  RegExp('UPLOAD SUCCEEDED'),
  RegExp('No errors uploading', caseSensitive: false),
  RegExp('upload succeeded', caseSensitive: false),
  RegExp('upload complete', caseSensitive: false),
];

final _itmsCode = RegExp(r'ITMS-(\d{5})');
final _leadingCode = RegExp(r'^(\d{5}):');
final _parenthesizedCode = RegExp(r'\((\d{5})\)');
final _deliveryId = RegExp(
  r'Delivery (?:UUID|ID):\s*([0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})',
);

/// What the output of an altool upload says.
class AltoolOutput extends Equatable {
  /// Creates a reading.
  const new({
    this.errors = const [],
    this.codes = const [],
    this.confirmed = false,
    this.deliveryId,
  });

  /// Reads the [lines] altool printed.
  factory parse(Iterable<String> lines) {
    final errors = <String>[];
    final codes = <String>[];
    var confirmed = false;
    String? deliveryId;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (_errorMarkers.any((marker) => marker.hasMatch(line))) {
        errors.add(line);
        for (final match in [
          ..._itmsCode.allMatches(line),
          ..._parenthesizedCode.allMatches(line),
        ]) {
          if (!codes.contains(match[1])) codes.add(match[1]!);
        }
        continue;
      }
      if (_successMarkers.any((marker) => marker.hasMatch(line))) {
        confirmed = true;
      }
      deliveryId ??= _deliveryId.firstMatch(line)?[1];
    }
    return AltoolOutput(
      errors: errors,
      codes: codes,
      confirmed: confirmed,
      deliveryId: deliveryId,
    );
  }

  /// Reads the errors App Store Connect reported about a build upload, or
  /// its refusal of one, so that they are told and cured the way altool's
  /// are. A code may lead an error (`90189: ...`), be `ITMS-90189` or be in
  /// parentheses.
  factory ofUploadErrors(Iterable<String> errors) {
    final codes = <String>[];
    for (final error in errors) {
      for (final match in [
        ..._leadingCode.allMatches(error),
        ..._itmsCode.allMatches(error),
        ..._parenthesizedCode.allMatches(error),
      ]) {
        if (!codes.contains(match[1])) codes.add(match[1]!);
      }
    }
    return AltoolOutput(errors: [...errors], codes: codes);
  }

  /// The lines that report an error, in order.
  final List<String> errors;

  /// The five-digit codes in them: `ITMS-90186` and `(90186)` both give
  /// `90186`.
  final List<String> codes;

  /// Whether altool said the upload went through.
  final bool confirmed;

  /// The delivery UUID altool printed, which `altool --build-status` takes.
  final String? deliveryId;

  /// Whether the output reports an error, whatever the exit code was.
  bool get rejected => errors.isNotEmpty;

  /// What to do about the error, for the codes and messages that have a known
  /// cure; `null` otherwise.
  String? get hint {
    if (codes.contains('90186') || codes.contains('90062')) {
      return 'The version train is closed, or the version is not higher than '
          'the one on the App Store. Bump the version.';
    }
    if (codes.contains('90189')) {
      return 'A build with this number was uploaded already. Allocate a new '
          'build number.';
    }
    final text = errors.join(' ').toLowerCase();
    if (text.contains('authenticat') || text.contains('authkey')) {
      return 'App Store Connect refused the credentials. Check the ASC key, '
          'or the Apple ID and its app-specific password.';
    }
    return null;
  }

  /// The error lines as one sentence for the owner, at most [limit] of them.
  String describe({int limit = 3}) {
    final shown = errors.take(limit).join(' | ');
    final more = errors.length > limit
        ? ' (+${errors.length - limit} more)'
        : '';
    return '$shown$more';
  }

  @override
  List<Object?> get props => [errors, codes, confirmed, deliveryId];
}
