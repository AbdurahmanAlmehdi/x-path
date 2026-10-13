import 'package:xp_engine/src/versioning/app_version.dart';

/// Reads the release a patch targets from what the owner wrote.
///
/// Returns the release, which always has a build number, or why [raw] cannot
/// name one.
({AppVersion? release, String? problem}) readPatchRelease(String? raw) {
  if (raw == null) {
    return (release: null, problem: 'A patch needs the release it patches.');
  }
  if (raw == 'latest') {
    return (
      release: null,
      problem:
          "'latest' is whichever release was cut last, and more than one can "
          'be live.',
    );
  }
  final AppVersion release;
  try {
    release = AppVersion.parse(raw);
  } on FormatException catch (error) {
    return (release: null, problem: error.message);
  }
  if (release.build == null) {
    return (
      release: null,
      problem: '$release has no build number, so it names no single release.',
    );
  }
  return (release: release, problem: null);
}
