import 'package:xp_api/xp_api.dart';

/// A workflow operation cannot be done.
class WorkflowException implements Exception {
  /// Creates the exception with a [message] for the owner.
  const new(this.message);

  /// What is wrong, and what to do.
  final String message;

  @override
  String toString() => 'WorkflowException: $message';
}

/// There is no such workflow, or it is not one of this project.
class WorkflowNotFoundException extends WorkflowException {
  /// Creates the exception. [version] is the version that was asked for.
  const new(this.id, {this.version})
    : super(
        version == null
            ? 'There is no workflow $id in this project.'
            : 'Workflow $id has no version $version.',
      );

  /// The id that was asked for.
  final String id;

  /// The version that was asked for, if the workflow exists and the version
  /// does not.
  final int? version;

  @override
  String toString() => 'WorkflowNotFoundException: $message';
}

/// The project has a workflow of that name already.
class WorkflowExistsException extends WorkflowException {
  /// Creates the exception.
  const new(this.name)
    : super('The project has a workflow called "$name" already.');

  /// The name.
  final String name;

  @override
  String toString() => 'WorkflowExistsException: $message';
}

/// A built-in workflow cannot be changed.
class WorkflowBuiltinException extends WorkflowException {
  /// Creates the exception.
  const new(this.name)
    : super(
        '"$name" is a built-in workflow, so it cannot be edited or deleted. '
        'Create a workflow of your own with its YAML.',
      );

  /// The name of the built-in.
  final String name;

  @override
  String toString() => 'WorkflowBuiltinException: $message';
}

/// The workflow is archived, so it does not run until it is unarchived.
class WorkflowArchivedException extends WorkflowException {
  /// Creates the exception for the workflow called [name].
  const new(String name)
    : super('The workflow "$name" is archived. Unarchive it to run it.');

  @override
  String toString() => 'WorkflowArchivedException: $message';
}

/// Jobs ran the workflow, so it cannot be deleted.
class WorkflowInUseException extends WorkflowException {
  /// Creates the exception.
  const new(this.id)
    : super(
        'Workflow $id has been run, and the jobs keep the version they ran, '
        'so it cannot be deleted.',
      );

  /// The workflow.
  final String id;

  @override
  String toString() => 'WorkflowInUseException: $message';
}

/// The workflow name is not allowed.
class WorkflowNameException extends WorkflowException {
  /// Creates the exception.
  const new(this.name)
    : super(
        '"$name" is not a workflow name: 1 to 64 letters, digits, ".", "_" or '
        '"-", starting with a letter or digit.',
      );

  /// The name.
  final String name;

  @override
  String toString() => 'WorkflowNameException: $message';
}

/// A change of a workflow does not apply to it, for example catching up
/// with a built-in that it is not a copy of.
class WorkflowEditException extends WorkflowException {
  /// Creates the exception.
  const new(super.message);

  @override
  String toString() => 'WorkflowEditException: $message';
}

/// The workflow document has issues.
class WorkflowInvalidException extends WorkflowException {
  /// Creates the exception from the [issues] found.
  new(this.issues)
    : super(
        'The workflow has ${issues.length} issue'
        '${issues.length == 1 ? '' : 's'}: '
        '${issues.map((issue) => 'line ${issue.line}, column ${issue.column}: '
            '${[issue.message, ?issue.hint].join(' ')}').join(' ')}',
      );

  /// The issues, in the order of the document.
  final List<WorkflowIssue> issues;

  @override
  String toString() => 'WorkflowInvalidException: $message';
}

/// A dispatch asks for something the project cannot do.
class DispatchException extends WorkflowException {
  /// Creates the exception, with what to do about it ([hint]) and the
  /// [details] a client can act on.
  const new(super.message, {this.hint, this.details});

  /// What to do about it, for the owner; it names no command.
  final String? hint;

  /// Facts a client can act on, such as the `kind` of a missing credential.
  final Map<String, Object?>? details;

  @override
  String toString() => 'DispatchException: $message';
}
