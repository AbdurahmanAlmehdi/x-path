import 'package:xp_engine/src/workflows/expression.dart';

/// Why a job of a matrix cell is left out, in words: what its false
/// [condition] lacks in [scope], for example "no Firebase app id for dev".
///
/// The parts that only say the cell is of another platform or flavor are
/// left out when there is more to say: the `upload` of a dev build names the
/// app id it lacks, not that it is not the iOS cell.
String skipReason(
  Expression condition,
  Map<String, Object?> scope, {
  String? flavor,
}) {
  final parts = [
    for (final part in condition.falseParts(scope)) (_isAxis(part), part),
  ];
  final telling = parts.where((part) => !part.$1).toList();
  final reasons = {
    for (final (_, part) in telling.isEmpty ? parts : telling) _words(part),
  };
  final text = reasons.join(', ');
  return flavor == null ? text : '$text for $flavor';
}

/// Whether [part] only reads which platform or flavor the cell is.
bool _isAxis(Expression part) =>
    part.variables.every((name) => name == 'platform') ||
    part.source.startsWith('flavor.name');

final _credential = RegExp(r'^(!?)flavor\.credentials\.(\w+)$');
final _input = RegExp(r'^inputs\.(\w+)$');

String _words(Expression part) {
  final source = part.source;
  if (source.contains('firebaseAppId')) return 'no Firebase app id';
  if (source.contains('appleAppId')) return 'no App Store app id';
  if (_credential.firstMatch(source) case final match?) {
    return match.group(1)!.isEmpty
        ? 'no ${match.group(2)} credential'
        : 'it has a ${match.group(2)} credential';
  }
  if (_input.firstMatch(source) case final match?) {
    return 'the input ${match.group(1)} is not set';
  }
  return switch (source) {
    'flavor.shorebird' => 'not a Shorebird flavor',
    '!flavor.shorebird' => 'a Shorebird flavor',
    'flavor.prod' => 'not a production flavor',
    '!flavor.prod' => 'a production flavor',
    _ => '$source is false',
  };
}
