import 'package:equatable/equatable.dart';

/// How far a program on this machine can be used.
enum ToolStatus {
  /// It runs and its version was read.
  available,

  /// It is not installed, or not on the `PATH` of the engine.
  missing,

  /// It is there but did not answer as expected.
  failed,

  /// It does not exist on this operating system.
  unsupported,
}

/// What the engine found out about one program (D-20, D-19).
class ToolReport extends Equatable {
  /// Creates a report for [tool].
  const new(this.tool, this.status, {this.version, this.detail, this.message});

  /// The program: `shorebird`, `gh` or `xcode`.
  final String tool;

  /// Whether it can be used.
  final ToolStatus status;

  /// Its version, such as `2.96.0`; only when [status] is
  /// [ToolStatus.available].
  final String? version;

  /// More that is known about it, such as the Xcode build and location.
  final String? detail;

  /// Why it cannot be used and how to fix that; unless it is available.
  final String? message;

  /// Whether the tool can be used.
  bool get isAvailable => status == ToolStatus.available;

  @override
  List<Object?> get props => [tool, status, version, detail, message];
}
