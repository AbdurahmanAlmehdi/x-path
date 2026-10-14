import 'package:xp_engine/src/workflows/workflow_definition.dart';
import 'package:xp_engine/src/workflows/workflow_exceptions.dart';

/// The cells a job is repeated over: one map from axis (`platform`, `flavor`)
/// to its value for each combination, in the order of the axes and values.
/// A job without a matrix has one empty cell.
///
/// [scope] holds what an axis may read (`platforms`, `flavors`).
///
/// Throws a [DispatchException] for an axis that does not give a list of
/// strings.
List<Map<String, String>> expandMatrix(
  JobDefinition job,
  Map<String, Object?> scope,
) {
  var cells = <Map<String, String>>[{}];
  for (final axis in job.matrix) {
    final values = axis.values ?? _read(axis, scope);
    cells = [
      for (final cell in cells)
        for (final value in values) {...cell, axis.name: value},
    ];
  }
  return cells;
}

List<String> _read(MatrixAxis axis, Map<String, Object?> scope) {
  final value = axis.reference!.evaluate(scope);
  if (value is List && value.every((item) => item is String)) {
    return value.cast<String>();
  }
  throw DispatchException(
    'Line ${axis.position.line}: the matrix axis "${axis.name}" must give a '
    'list of strings.',
  );
}
