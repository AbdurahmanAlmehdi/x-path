import 'package:xp_engine/src/scan/ios_files.dart';

/// The one of [known] that [name] most likely meant, when it is close enough
/// to be a typo of it or the same in another case; `null` otherwise.
String? closestTo(String name, Iterable<String> known) {
  String? best;
  var bestDistance = 0;
  for (final candidate in known) {
    final distance = editDistance(name.toLowerCase(), candidate.toLowerCase());
    if (best == null || distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  final allowed = name.length < 4 ? 1 : (name.length < 9 ? 2 : 3);
  return best != null && best != name && bestDistance <= allowed ? best : null;
}

/// The hint of an issue about [name], which is none of [known]: the one it
/// most likely meant, as in `Did you mean "inputs.appIds"?` with [prefix]
/// `inputs.`, else the ones [label] lists. `null` when nothing is known.
String? suggestion(
  String name,
  Iterable<String> known, {
  String prefix = '',
  String label = 'Allowed',
}) {
  if (known.isEmpty) return null;
  if (closestTo(name, known) case final close?) {
    return 'Did you mean "$prefix$close"?';
  }
  final sorted = known.toList()..sort();
  return '$label: ${sorted.map((name) => '$prefix$name').join(', ')}.';
}
