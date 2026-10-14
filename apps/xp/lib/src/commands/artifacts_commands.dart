import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp_client/xp_client.dart';

/// `xp artifacts`: the files jobs produced.
XpGroup artifactsCommand(XpContext context) => XpGroup(
  context,
  'artifacts',
  'List the artifacts of a job and download them.',
  [ArtifactsListCommand(context), ArtifactsDownloadCommand(context)],
);

/// `xp artifacts list <job>`.
class ArtifactsListCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'list';

  @override
  String get description => 'List the artifacts of a job.';

  @override
  String get invocation => 'xp artifacts list <job>';

  @override
  Future<int> execute(XpClient client) async {
    final [jobId] = positionals(['job']);
    final artifacts = await client.listJobArtifacts(jobId);
    emit([for (final artifact in artifacts) artifact.toJson()], () {
      if (artifacts.isEmpty) return 'No artifacts.';
      return renderTable(
        ['ID', 'KIND', 'NAME', 'SIZE', 'PINNED'],
        [
          for (final artifact in artifacts)
            [
              artifact.id,
              artifact.kind.wire,
              artifact.name,
              formatBytes(artifact.size),
              if (artifact.pinned) 'yes' else 'no',
            ],
        ],
      );
    });
    return XpExit.ok;
  }
}

/// `xp artifacts download <artifact> [--output <path>]`.
class ArtifactsDownloadCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addOption(
      'output',
      abbr: 'o',
      help:
          'Where to save it: a file, or a folder (default: the current '
          'folder).',
      valueHelp: 'path',
    );
  }

  @override
  String get name => 'download';

  @override
  String get description => 'Download an artifact and check its SHA-256.';

  @override
  String get invocation => 'xp artifacts download <artifact> [--output <path>]';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['artifact']);
    final artifact = await client.getArtifact(id);
    final download = await client.downloadArtifact(id);
    final output = argResults!.option('output') ?? '.';
    final target = Directory(output).existsSync()
        ? File(p.join(output, artifact.name))
        : File(output);
    final digest = await download.saveTo(target);
    emit(
      {'artifact': artifact.toJson(), 'path': target.path, 'sha256': digest},
      () =>
          'Saved ${target.path} (${formatBytes(artifact.size)}, SHA-256 '
          '$digest).',
    );
    return XpExit.ok;
  }
}
