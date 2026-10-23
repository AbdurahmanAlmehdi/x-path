import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/jobs/jobs_routes.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';

/// The runner endpoints (D-08): pairing, listing, revoking, the artifact
/// upload and the bundle a runner updates itself with (D-24). The WebSocket a
/// runner dials out on is `RunnerConnectRoute`.
///
/// - `POST /runners/pairing-tokens` and `POST /runners/{id}/revoke` are for
///   `app` and `cli` tokens (`403` for the others): a paired runner receives
///   signing material.
/// - `POST /runners/pair` needs no bearer token; the pairing token in its body
///   is the proof, and an unknown, expired or used one answers `401`.
/// - `PUT /runners/jobs/{id}/artifacts/{name}` is for a `runner` token that
///   holds the lease of the job.
/// - `GET /runners/bundle?os=&arch=` streams the `xp` bundle of the engine's
///   own version for that machine, with its SHA-256 and size. A `runner`
///   token reaches it (ADR 0011); `404` when the engine has no bundle for the
///   machine.
/// - `GET /settings/runner-url` reads the address runners reach the engine
///   at, which pairing tokens carry; `PUT` sets or clears it, for `app` and
///   `cli` tokens only.
/// - Every kind of token can read `GET /runners`, like the other reads. (A
///   runner token can read as much as an `mcp` token can; the plan only keeps
///   it from approving and from changing gates, D-13.)
class RunnersRoutes {
  /// Creates the routes.
  const new(this._runners, this._artifacts, this._bundles);

  final RunnerService _runners;
  final RunnerArtifacts _artifacts;
  final RunnerBundles _bundles;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/runners', _list)
      ..get('/runners/bundle', _bundle)
      ..post('/runners/pairing-tokens', _createPairingToken)
      ..post('/runners/pair', _pair)
      ..post('/runners/<id>/revoke', _revoke)
      ..get('/settings/runner-url', _runnerUrl)
      ..put('/settings/runner-url', _setRunnerUrl)
      ..put('/runners/jobs/<id>/artifacts/<name>', _upload);
  }

  Future<Response> _list(Request request) => _guard(() async {
    return jsonResponse(RunnersResponse(await _runners.list()).toJson());
  });

  /// Streams the bundle. `Content-Length` is its size and `X-Content-SHA256`
  /// its digest, so the runner can verify what it saved before it switches.
  Future<Response> _bundle(Request request) => _guard(() async {
    final query = request.url.queryParameters;
    final target = RunnerBundleTarget.parse(query['os'], query['arch']);
    final bundle = await _bundles.find(target);
    return Response.ok(
      bundle.open(),
      headers: {
        'content-type': 'application/gzip',
        'content-length': '${bundle.size}',
        'x-content-sha256': bundle.sha256,
        'content-disposition':
            'attachment; filename="xp-${target.folderName}.tar.gz"',
      },
    );
  });

  Future<Response> _createPairingToken(Request request) => _guard(() async {
    final body = await readJsonBody(
      request,
      CreatePairingTokenRequest.fromJson,
    );
    final token = await _runners.createPairingToken(
      name: body.name,
      by: deviceTokenOf(request),
    );
    return jsonResponse(token.toJson(), statusCode: 201);
  });

  Future<Response> _pair(Request request) => _guard(() async {
    final body = await readJsonBody(request, PairRunnerRequest.fromJson);
    final paired = await _runners.pair(body.pairingToken);
    return jsonResponse(paired.toJson(), statusCode: 201);
  });

  Future<Response> _runnerUrl(Request request) =>
      _guard(() async => jsonResponse((await _runners.runnerUrl()).toJson()));

  Future<Response> _setRunnerUrl(Request request) => _guard(() async {
    final body = await readJsonBody(request, SetRunnerUrlRequest.fromJson);
    final set = await _runners.setRunnerUrl(
      body.url,
      by: deviceTokenOf(request),
    );
    return jsonResponse(set.toJson());
  });

  Future<Response> _revoke(Request request, String id) => _guard(() async {
    final runner = await _runners.revoke(id, by: deviceTokenOf(request));
    return jsonResponse(runner.toJson());
  });

  Future<Response> _upload(Request request, String id, String name) =>
      _guard(() async {
        final runner = await _runners.runnerFor(deviceTokenOf(request));
        final sha256 = _header(request, 'x-content-sha256');
        final leaseId = _header(request, 'x-lease-id');
        final kind = _kind(request.url.queryParameters['kind']);
        final size = request.contentLength;
        if (size == null) {
          throw const BadRequestException(
            'Content-Length is required: it is the size the upload is '
            'checked against.',
          );
        }
        final record = await _artifacts.upload(
          runnerId: runner.id,
          jobId: id,
          leaseId: leaseId,
          kind: kind,
          name: name,
          content: request.read(),
          sha256: sha256,
          size: size,
        );
        return jsonResponse(record.toArtifact().toJson(), statusCode: 201);
      });

  String _header(Request request, String name) =>
      request.headers[name] ??
      (throw BadRequestException('The $name header is required.'));

  ArtifactKind _kind(String? wire) {
    for (final kind in ArtifactKind.values) {
      if (kind.wire == wire) return kind;
    }
    final kinds = ArtifactKind.values.map((kind) => kind.wire).join(', ');
    throw BadRequestException('kind must be one of: $kinds.');
  }
}

/// Runs [action] and turns the failures a client can cause into error
/// responses: `guardJobs` answers a bad body and the job failures. Anything
/// else is left to the error middleware (`500`).
Future<Response> _guard(Future<Response> Function() action) =>
    guardJobs(() => _guardRunners(action));

Future<Response> _guardRunners(Future<Response> Function() action) async {
  try {
    return await action();
  } on RunnerBundleMissingException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on RunnerNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on RunnerForbiddenException catch (error) {
    return errorResponse(ApiErrorCode.forbidden, error.message);
  } on PairingRejectedException catch (error) {
    return errorResponse(
      ApiErrorCode.unauthorized,
      error.message,
      headers: const {'www-authenticate': 'Bearer'},
    );
  } on RunnerNameTakenException catch (error) {
    return errorResponse(ApiErrorCode.conflict, error.message);
  } on RunnerLeaseException catch (error) {
    return errorResponse(ApiErrorCode.conflict, error.message);
  } on RunnerInvalidException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on ArtifactChecksumException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  }
}
