import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as p;

/// Where `xp` stands on the `PATH` of the user.
enum CliLinkState {
  /// A link to the bundled `xp` is in place.
  linked,

  /// Nothing links to the bundled `xp`.
  notLinked,

  /// This build has no bundled `xp` to link to (a development build before
  /// Phase 18b).
  missingBinary,

  /// Another `xp` (not a link into an XPath app) is in the way. XPath does
  /// not replace it.
  conflict,

  /// The link could not be made anywhere.
  failed,
}

/// The outcome of linking `xp`, and why the link is where it is.
class CliLink extends Equatable {
  /// Creates the outcome.
  const new(this.state, {this.path, this.fellBack = false, this.detail});

  /// What happened.
  final CliLinkState state;

  /// The link, or the file in the way for [CliLinkState.conflict].
  final String? path;

  /// Whether the link went to `~/.local/bin` because `/usr/local/bin` could
  /// not be written without an administrator password (XPath never asks for
  /// one).
  final bool fellBack;

  /// What the file system said, when something failed.
  final String? detail;

  @override
  List<Object?> get props => [state, path, fellBack, detail];
}

/// Links the `xp` inside the app into a folder on the user's `PATH`.
abstract interface class CliLinker {
  /// Whether a link to the bundled `xp` is in place.
  Future<CliLink> status();

  /// Makes the link: in `/usr/local/bin` if the user can write there (Intel
  /// Homebrew owns it), else in `~/.local/bin`. A link that points into an
  /// older or moved XPath app is replaced; anything else named `xp` is left
  /// alone and reported as a [CliLinkState.conflict].
  Future<CliLink> link();
}

/// The [CliLinker] of the real file system. It never asks for a password
/// and never shows a dialog: a folder it cannot write is a reason to use the
/// next one.
class FileSystemCliLinker implements CliLinker {
  /// Creates the linker of [target] (the bundled `xp`).
  const new({
    required this.target,
    required this.home,
    this.systemDirectory = '/usr/local/bin',
  });

  /// The bundled `xp`.
  final String target;

  /// The home folder of the user.
  final String home;

  /// The folder tried first.
  final String systemDirectory;

  /// The folder used when [systemDirectory] cannot be written.
  String get userDirectory => p.join(home, '.local', 'bin');

  bool _isXPathLink(String path) {
    final link = Link(path);
    final destination = link.targetSync();
    return destination == target ||
        destination.endsWith(p.join('Contents', 'Helpers', 'xp', 'bin', 'xp'));
  }

  @override
  Future<CliLink> status() async {
    for (final directory in [systemDirectory, userDirectory]) {
      final path = p.join(directory, 'xp');
      if (FileSystemEntity.isLinkSync(path) &&
          Link(path).targetSync() == target) {
        return CliLink(
          CliLinkState.linked,
          path: path,
          fellBack: directory == userDirectory,
        );
      }
    }
    return const CliLink(CliLinkState.notLinked);
  }

  @override
  Future<CliLink> link() async {
    if (!File(target).existsSync()) {
      return CliLink(CliLinkState.missingBinary, path: target);
    }
    String? lastError;
    for (final directory in [systemDirectory, userDirectory]) {
      final fellBack = directory == userDirectory;
      final path = p.join(directory, 'xp');
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.link && !_isXPathLink(path) ||
          type == FileSystemEntityType.file ||
          type == FileSystemEntityType.directory) {
        return CliLink(CliLinkState.conflict, path: path);
      }
      try {
        if (fellBack) await Directory(directory).create(recursive: true);
        final link = Link(path);
        if (type == FileSystemEntityType.link) {
          await link.update(target);
        } else {
          await link.create(target);
        }
        return CliLink(CliLinkState.linked, path: path, fellBack: fellBack);
      } on FileSystemException catch (error) {
        lastError = error.osError?.message ?? error.message;
      }
    }
    return CliLink(CliLinkState.failed, detail: lastError);
  }
}
