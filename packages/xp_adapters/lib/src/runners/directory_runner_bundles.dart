import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

/// The name of a runner bundle in the folder of its target.
const runnerBundleFileName = 'xp.tar.gz';

/// The runner bundles of the engine as folders: `<root>/<os>-<arch>/xp.tar.gz`
/// in the first of the [roots] that has one for the target.
///
/// The file is the `xp` bundle that `dart build cli` makes (`bin/xp` and
/// `lib/libsqlite3.*`) as a `.tar.gz` whose top level is `bin` and `lib`
/// themselves. The packaging of a release (Phase 18a) puts it there; the
/// engine never builds one.
///
/// The SHA-256 is worked out once per file and kept until the file changes.
class DirectoryRunnerBundles implements RunnerBundles {
  /// Creates the bundles over [roots], tried in order.
  new(this.roots);

  /// The folders that hold a `<os>-<arch>` folder, in the order they are
  /// tried.
  final List<String> roots;

  final _digests = <String, ({DateTime modified, int size, String sha256})>{};

  @override
  Future<RunnerBundle> find(RunnerBundleTarget target) async {
    for (final root in roots) {
      final file = File(p.join(root, target.folderName, runnerBundleFileName));
      if (!file.existsSync()) continue;
      final stat = file.statSync();
      final digest = await _digest(file, stat);
      return RunnerBundle(sha256: digest, size: stat.size, open: file.openRead);
    }
    final where = [
      for (final root in roots)
        p.join(root, target.folderName, runnerBundleFileName),
    ];
    throw RunnerBundleMissingException(
      'This engine has no runner bundle for ${target.folderName}. Put the '
      '$runnerBundleFileName of this version in ${where.join(' or ')}.',
    );
  }

  Future<String> _digest(File file, FileStat stat) async {
    final known = _digests[file.path];
    if (known != null &&
        known.modified == stat.modified &&
        known.size == stat.size) {
      return known.sha256;
    }
    final sha256 = (await _sha256Of(file)).toString();
    _digests[file.path] = (
      modified: stat.modified,
      size: stat.size,
      sha256: sha256,
    );
    return sha256;
  }
}

/// The SHA-256 of [file], read as a stream.
Future<Digest> _sha256Of(File file) => sha256.bind(file.openRead()).first;
