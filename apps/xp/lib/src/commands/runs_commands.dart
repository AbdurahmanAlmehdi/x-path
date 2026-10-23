import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp/src/run_approvals.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:yaml/yaml.dart';

/// `xp dispatch <project> <workflow>`: runs a workflow.
class DispatchCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser
      ..addOption('ref', help: 'Branch, tag or commit (default: base branch).')
      ..addOption('app', help: 'The app, by path (`.` for the root).')
      ..addMultiOption('flavor', help: 'A flavor to run for. Repeatable.')
      ..addMultiOption(
        'platform',
        help: 'A platform to build for. Repeatable.',
        allowed: ['android', 'ios'],
      )
      ..addOption(
        'bump',
        help: 'How to bump the version.',
        allowed: VersionBump.values.map((bump) => bump.wire),
      )
      ..addOption('version', help: 'The version x.y.z to release.')
      ..addOption(
        'release-version',
        help: 'The release x.y.z+build a patch applies to.',
      )
      ..addMultiOption(
        'input',
        help:
            'An input of the workflow, key=value, read as its declared type '
            '(text, true or false, JSON, ...); an input without a type is '
            'JSON if it parses as JSON, else text. Repeatable.',
        valueHelp: 'key=value',
        splitCommas: false,
      )
      ..addOption(
        'input-file',
        help:
            'A YAML or JSON file of inputs, name: value. --input wins over '
            'it.',
        valueHelp: 'file',
      );
  }

  @override
  String get name => 'dispatch';

  @override
  String get description => 'Run a workflow of a project.';

  @override
  String get invocation => 'xp dispatch <project> <workflow> [options]';

  @override
  Future<int> execute(XpClient client) async {
    final [projectReference, workflowReference] = positionals([
      'project',
      'workflow',
    ]);
    final results = argResults!;
    final given = <String, String>{};
    for (final input in results.multiOption('input')) {
      final split = input.indexOf('=');
      if (split < 1) usageException('--input must be key=value, not "$input".');
      given[input.substring(0, split)] = input.substring(split + 1);
    }
    final file = results.option('input-file');
    final fromFile = file == null
        ? const <String, Object?>{}
        : _readInputs(file);
    final projectId = await resolveProject(client, projectReference);
    final workflowId = await resolveWorkflow(
      client,
      projectId,
      workflowReference,
    );
    final declared = {
      for (final input in (await client.getWorkflow(
        projectId,
        workflowId,
      )).inputs)
        input.name: input,
    };
    final inputs = <String, dynamic>{
      ...fromFile,
      for (final MapEntry(key: name, value: text) in given.entries)
        name: _coerce(name, declared[name], text),
    };
    final prompt = context.secretPrompt;
    for (final input in declared.values) {
      if (input.required &&
          !inputs.containsKey(input.name) &&
          prompt.interactive) {
        final answer = prompt.ask(
          [input.name, ?input.description].join(' — '),
          secret: false,
        );
        inputs[input.name] = _coerce(input.name, input, answer);
      }
    }
    final bump = results.option('bump');
    final flavors = results.multiOption('flavor');
    final platforms = results.multiOption('platform');
    final request = DispatchRequest(
      ref: results.option('ref'),
      app: results.option('app'),
      flavors: flavors.isEmpty ? null : flavors,
      platforms: platforms.isEmpty ? null : platforms,
      bump: bump == null
          ? null
          : VersionBump.values.firstWhere((value) => value.wire == bump),
      version: results.option('version'),
      releaseVersion: results.option('release-version'),
      inputs: inputs,
    );
    final run = await client.dispatchWorkflow(projectId, workflowId, request);
    emit(run.toJson(), () => 'Dispatched ${run.id}.\n\n${describeRun(run)}');
    return XpExit.ok;
  }

  /// The value [text] gives the input [name], read as its declared [input]
  /// type (UX-04): text stays text, a boolean is true or false, JSON is
  /// decoded. An input without a type, or one the workflow does not declare
  /// (the engine refuses it), is JSON if it parses as JSON, else text.
  Object? _coerce(String name, WorkflowInput? input, String text) {
    switch (input?.type) {
      case InputType.string || InputType.choice || InputType.release:
        return text;
      case InputType.boolean:
        return switch (text.toLowerCase()) {
          'true' => true,
          'false' => false,
          _ => usageException(
            'The input "$name" is true or false, not "$text".',
          ),
        };
      case InputType.json:
        try {
          return jsonDecode(text);
        } on FormatException {
          usageException('The input "$name" must be JSON: $text');
        }
      case null:
        try {
          return jsonDecode(text);
        } on FormatException {
          return text;
        }
    }
  }

  /// The inputs of an `--input-file`: a YAML (or JSON, which is YAML) mapping
  /// from a name to its value.
  Map<String, Object?> _readInputs(String path) {
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on FileSystemException catch (error) {
      throw ReferenceException(
        'Cannot read "$path": ${error.osError?.message ?? error.message}.',
        notFound: true,
      );
    }
    final Object? document;
    try {
      document = loadYaml(text);
    } on YamlException catch (error) {
      usageException('$path is not YAML or JSON: ${error.message}');
    }
    if (document is! Map) {
      usageException('$path must be a mapping of input names to values.');
    }
    return {
      for (final MapEntry(:key, :value) in document.entries)
        '$key': _plain(value),
    };
  }
}

/// [value] of a YAML document as plain lists, maps and scalars.
Object? _plain(Object? value) => switch (value) {
  final Map<Object?, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries) '$key': _plain(value),
  },
  final List<Object?> list => [for (final item in list) _plain(item)],
  _ => value,
};

/// The lines `xp runs show` prints.
String describeRun(Run run, {List<Approval> approvals = const []}) {
  final version = run.version;
  final build = run.build;
  final head =
      '${run.id}  ${run.state.wire}'
      '${version == null ? '' : '  $version'}'
      '${build == null ? '' : '+$build'}';
  final lines = [
    head,
    'sha: ${run.sha}  dispatched: ${formatTime(run.createdAt)}',
    '',
    renderTable(
      ['JOB', 'NAME', 'STAGE', 'STATE'],
      [
        for (final job in run.jobs)
          [job.id, job.name, '${job.stage}', job.state.wire],
      ],
    ),
    for (final approval in approvals) _waitingFor(approval),
  ];
  return lines.join('\n');
}

String _waitingFor(Approval approval) =>
    '\nWaiting for approval ${approval.id} (${approval.action}). Approve '
    'with: xp approvals approve ${approval.id}';

/// `xp runs`: the runs a dispatch made.
XpGroup runsCommand(XpContext context) => XpGroup(
  context,
  'runs',
  'Show and cancel runs.',
  [RunsShowCommand(context), RunsCancelCommand(context)],
);

/// `xp runs show <run>`.
class RunsShowCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'show';

  @override
  String get description =>
      'Show a run, its jobs and the approval it waits for.';

  @override
  String get invocation => 'xp runs show <run>';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['run']);
    final run = await client.getRun(id);
    final approvals = await pendingApprovalsOf(client, run);
    emit({
      ...run.toJson(),
      if (approvals.isNotEmpty)
        'pendingApprovals': [for (final a in approvals) a.toJson()],
    }, () => describeRun(run, approvals: approvals));
    return XpExit.ok;
  }
}

/// `xp runs cancel <run>`.
class RunsCancelCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'cancel';

  @override
  String get description => 'Cancel every job of a run that has not ended.';

  @override
  String get invocation => 'xp runs cancel <run>';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['run']);
    final run = await client.cancelRun(id);
    emit(run.toJson(), () => describeRun(run));
    return XpExit.ok;
  }
}

/// `xp jobs`: the jobs of a run.
XpGroup jobsCommand(XpContext context) =>
    XpGroup(context, 'jobs', 'Show, cancel and resume jobs.', [
      JobsShowCommand(context),
      JobsCancelCommand(context),
      JobsResumeCommand(context),
    ]);

/// The lines `xp jobs show` prints: the job, its steps, why each failed step
/// failed, and what each guard check says to fix.
String describeJob(Job job) {
  final name = job.name;
  final times =
      'started: ${formatTime(job.startedAt)}  '
      'finished: ${formatTime(job.finishedAt)}';
  final lines = [
    '${job.id}  ${job.state.wire}${name == null ? '' : '  $name'}',
    if (job.message != null) 'message: ${job.message}',
    times,
    '',
    renderTable(
      ['STEP', 'KIND', 'STATE', 'TRIES'],
      [
        for (final step in job.steps)
          [
            '${step.ordinal}',
            step.kind,
            snakeCase(step.state.name),
            '${step.attempts}',
          ],
      ],
    ),
    for (final step in job.steps)
      if (step.state == StepState.failed && step.message != null)
        _failure(step),
    for (final step in job.steps) ..._guardFixes(step),
  ];
  return lines.join('\n');
}

String _failure(JobStep step) =>
    '\nstep ${step.ordinal} (${step.kind}) failed:\n${_indent(step.message!)}';

String _indent(String text) =>
    text.split('\n').map((line) => '  $line').join('\n');

/// What the checks of a guard step that ran say to fix (a failed one says
/// it in its message).
Iterable<String> _guardFixes(JobStep step) sync* {
  if (step.kind != 'guard') return;
  final results = step.result?['results'];
  if (results is! List) return;
  for (final result in results) {
    if (result case {'name': final String check, 'fix': final String fix}) {
      yield '\nfix (${step.kind} $check): $fix';
    }
  }
}

/// `xp jobs show <job>`.
class JobsShowCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'show';

  @override
  String get description => 'Show a job and its steps.';

  @override
  String get invocation => 'xp jobs show <job>';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['job']);
    final job = await client.getJob(id);
    emit(job.toJson(), () => describeJob(job));
    return XpExit.ok;
  }
}

/// `xp jobs cancel <job>`.
class JobsCancelCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'cancel';

  @override
  String get description => 'Cancel a job.';

  @override
  String get invocation => 'xp jobs cancel <job>';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['job']);
    final job = await client.cancelJob(id);
    emit(job.toJson(), () => describeJob(job));
    return XpExit.ok;
  }
}

/// `xp jobs resume <job> [--from-step n]`.
class JobsResumeCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addOption(
      'from-step',
      help: 'Go on from this step (the first unfinished one by default).',
      valueHelp: 'ordinal',
    );
  }

  @override
  String get name => 'resume';

  @override
  String get description => 'Resume a job at its first unfinished step.';

  @override
  String get invocation => 'xp jobs resume <job> [--from-step <n>]';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['job']);
    final text = argResults!.option('from-step');
    final fromStep = text == null ? null : int.tryParse(text);
    if (text != null && fromStep == null) {
      usageException('--from-step must be a number.');
    }
    final job = await client.resumeJob(id, fromStep: fromStep);
    emit(job.toJson(), () => describeJob(job));
    return XpExit.ok;
  }
}

/// `xp logs <job> [-f]`: the log of a job.
class LogsCommand extends XpCommand {
  /// Creates the command. Without `-f` the log of a job that ended is
  /// printed to its end; that of a job that runs, until the engine has been
  /// quiet for `XpContext.logIdle`.
  new(super.context) {
    argParser
      ..addFlag(
        'follow',
        abbr: 'f',
        negatable: false,
        help: 'Keep following the job until it ends, reconnecting if needed.',
      )
      ..addOption(
        'after',
        help: 'Start after this line number.',
        valueHelp: 'seq',
        defaultsTo: '0',
      );
  }

  @override
  String get name => 'logs';

  @override
  String get description => 'Print the log of a job; with -f, follow it.';

  @override
  String get invocation => 'xp logs <job> [-f] [--after <seq>]';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['job']);
    final after = int.tryParse(argResults!.option('after')!);
    if (after == null || after < 0) {
      usageException('--after must be a non-negative number.');
    }
    final follow = argResults!.flag('follow');
    // A job that ended has its whole log: read it to its end, however long
    // the engine takes. One that runs prints what it has so far.
    final whole = follow || (await client.getJob(id)).state.isFinished;
    final lines = StreamIterator(client.followJobLogs(id, after: after));
    LogEndFrame? end;
    try {
      while (true) {
        final more = whole
            ? await lines.moveNext()
            : await lines.moveNext().timeout(
                context.logIdle,
                onTimeout: () => false,
              );
        if (!more) break;
        final frame = lines.current;
        if (frame is LogEndFrame) end = frame;
        if (asJson) {
          logger.info(jsonEncode(frame.toJson()));
        } else if (frame is LogLineFrame) {
          logger.info(frame.text);
        }
      }
    } finally {
      await lines.cancel();
    }
    if (!asJson && end != null) {
      logger.info('-- job ${end.state.wire}');
    }
    return switch (end?.state) {
      JobState.failed ||
      JobState.cancelled ||
      JobState.interrupted when follow => XpExit.failed,
      _ => XpExit.ok,
    };
  }
}
