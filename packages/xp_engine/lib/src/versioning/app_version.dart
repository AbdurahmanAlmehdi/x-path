import 'package:equatable/equatable.dart';

final _name = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');
final _build = RegExp(r'^\d+$');

/// The marketing version of an app: `x.y.z`.
class VersionName extends Equatable implements Comparable<VersionName> {
  /// Creates the version [major].[minor].[patch].
  const new(this.major, this.minor, this.patch);

  /// Reads `x.y.z`.
  ///
  /// Throws a [FormatException] for anything else, including a pre-release
  /// suffix: the stores order versions by their numbers only.
  factory parse(String text) {
    final match = _name.firstMatch(text);
    if (match == null) {
      throw FormatException('"$text" is not a version like 5.4.1.', text);
    }
    return VersionName(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  /// The first number.
  final int major;

  /// The second number.
  final int minor;

  /// The third number.
  final int patch;

  /// Whether this version is higher than [other].
  bool operator >(VersionName other) => compareTo(other) > 0;

  @override
  int compareTo(VersionName other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';

  @override
  List<Object?> get props => [major, minor, patch];
}

/// The version of an app as the pubspec writes it: `x.y.z+build`.
class AppVersion extends Equatable {
  /// Creates a version. The [build] is absent in `version: 1.0.0`.
  const new(this.name, [this.build]);

  /// Reads `x.y.z` or `x.y.z+build`.
  ///
  /// Throws a [FormatException] for anything else.
  factory parse(String text) {
    final plus = text.indexOf('+');
    if (plus < 0) return AppVersion(VersionName.parse(text));
    final build = text.substring(plus + 1);
    if (!_build.hasMatch(build)) {
      throw FormatException(
        '"$text" is not a version like 5.4.1+3283: the build number must be '
        'a number.',
        text,
      );
    }
    return AppVersion(
      VersionName.parse(text.substring(0, plus)),
      int.parse(build),
    );
  }

  /// The marketing version.
  final VersionName name;

  /// The build number, if there is one.
  final int? build;

  @override
  String toString() => build == null ? '$name' : '$name+$build';

  @override
  List<Object?> get props => [name, build];
}
