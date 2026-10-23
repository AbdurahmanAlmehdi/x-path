import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xp_api/xp_api.dart';

import 'test_engine.dart';

/// The results of the probe of a Mac with Xcode.
const macProbeResults = [
  ProbeResult(
    id: 'os',
    status: ProbeStatus.exited,
    exitCode: 0,
    stdout: 'Darwin\n',
  ),
  ProbeResult(
    id: 'git',
    status: ProbeStatus.exited,
    exitCode: 0,
    stdout: 'git version 2.50.1\n',
  ),
  ProbeResult(id: 'android_sdk', status: ProbeStatus.exited, exitCode: 1),
  ProbeResult(
    id: 'java',
    status: ProbeStatus.exited,
    exitCode: 0,
    stderr: 'openjdk version "17.0.12" 2024-07-16\n',
  ),
  ProbeResult(
    id: 'xcode_select',
    status: ProbeStatus.exited,
    exitCode: 0,
    stdout: '/Applications/Xcode.app/Contents/Developer\n',
  ),
  ProbeResult(
    id: 'xcodebuild',
    status: ProbeStatus.exited,
    exitCode: 0,
    stdout: 'Xcode 26.1\nBuild version 17B55\n',
  ),
  ProbeResult(id: 'swift', status: ProbeStatus.skipped),
];

/// An engine with a token of every kind, to ask the runner endpoints as each
/// of them, and a runner that is paired.
class RunnerClient {
  new _(this.engine, this.secrets, this.runner, this.credential);

  /// Starts an engine with a paired runner called `mac-mini`.
  static Future<RunnerClient> start() async {
    final engine = await TestEngine.start();
    final secrets = <DeviceTokenKind, String>{
      DeviceTokenKind.app: engine.secret,
      for (final kind in [
        DeviceTokenKind.cli,
        DeviceTokenKind.mcp,
        DeviceTokenKind.runner,
      ])
        kind: await engine.tokenOf(kind),
    };
    final paired = await engine.pairRunner();
    return RunnerClient._(engine, secrets, paired.runner, paired.token);
  }

  final TestEngine engine;

  /// The bearer secret of a token of each kind. The `runner` one belongs to
  /// no runner.
  final Map<DeviceTokenKind, String> secrets;

  /// The runner that is paired.
  final Runner runner;

  /// The credential of [runner].
  final String credential;

  /// Sends a request as a token of [kind], or with [token].
  Future<RawResponse> send(
    String method,
    String path, {
    DeviceTokenKind kind = DeviceTokenKind.app,
    String? token,
    Object? body,
    String? rawBody,
  }) => engine.request(
    path,
    method: method,
    token: token ?? secrets[kind],
    body: rawBody ?? (body == null ? null : jsonEncode(body)),
  );

  /// Uploads [content] to the artifact [name] of [jobId].
  Future<RawResponse> upload(
    String jobId,
    String name,
    List<int> content, {
    String? token,
    String? leaseId,
    String? sha256Hex,
    String? kind = 'apk',
    bool chunked = false,
  }) async {
    final client = HttpClient();
    try {
      final query = kind == null ? '' : '?kind=$kind';
      final request = await client.putUrl(
        engine.uri.resolve('/runners/jobs/$jobId/artifacts/$name$query'),
      );
      request.headers.set('authorization', 'Bearer ${token ?? credential}');
      if (leaseId != null) request.headers.set('x-lease-id', leaseId);
      final digest = sha256Hex ?? sha256.convert(content).toString();
      if (digest.isNotEmpty) request.headers.set('x-content-sha256', digest);
      if (!chunked) request.contentLength = content.length;
      request.add(content);
      final response = await request.close();
      final received = <String, String>{};
      response.headers.forEach((name, values) => received[name] = values.first);
      return RawResponse(
        response.statusCode,
        response.headers.contentType?.toString(),
        await utf8.decodeStream(response),
        received,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Connects the runner and brings it online: hello, probe, answer.
  Future<RunnerStream> online({
    List<ProbeResult> results = macProbeResults,
    int cores = 8,
  }) async {
    final stream = await engine.connectRunner(token: credential);
    await stream.nextOf<WelcomeFrame>();
    stream.send(
      HelloFrame(version: '1.0.0', os: 'macos', arch: 'arm64', cores: cores),
    );
    final probe = await stream.nextOf<ProbeFrame>();
    stream.send(ProbeResultFrame(probeId: probe.probeId, results: results));
    await waitOnline();
    return stream;
  }

  /// Waits until the engine listed the runner as online.
  Future<void> waitOnline() async {
    for (var i = 0; i < 200; i++) {
      final listed = await engine.runnerService.get(runner.id);
      if (listed.status == RunnerStatus.online) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('The runner never came online.');
  }

  /// Leases a new job with one step to the runner on [stream] and returns the
  /// offer.
  Future<LeaseOfferFrame> lease(RunnerStream stream) async {
    final job = await engine.createJob(['dart']);
    await engine.runnerHub.offer(runner.id, job.id);
    return await stream.nextOf<LeaseOfferFrame>();
  }

  Future<void> close() => engine.close();
}
