import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/responses.dart';

/// The artifact endpoints: the files of a job, one artifact, its download and
/// its pin.
class ArtifactsRoutes {
  /// Creates the routes over [_artifacts].
  const new(this._artifacts);

  final ArtifactService _artifacts;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/jobs/<id>/artifacts', _forJob)
      ..get('/artifacts/<id>', _get)
      ..get('/artifacts/<id>/download', _download)
      ..post('/artifacts/<id>/pin', _pin)
      ..post('/artifacts/<id>/unpin', _unpin);
  }

  Future<Response> _forJob(Request request, String id) =>
      guardArtifacts(() async {
        final records = await _artifacts.forJob(id);
        return jsonResponse(
          ArtifactsResponse([for (final record in records) record.toArtifact()])
              .toJson(),
        );
      });

  Future<Response> _get(Request request, String id) => guardArtifacts(() async {
    return jsonResponse((await _artifacts.get(id)).toArtifact().toJson());
  });

  Future<Response> _pin(Request request, String id) => guardArtifacts(() async {
    return jsonResponse((await _artifacts.pin(id)).toArtifact().toJson());
  });

  Future<Response> _unpin(Request request, String id) =>
      guardArtifacts(() async {
        return jsonResponse((await _artifacts.unpin(id)).toArtifact().toJson());
      });

  /// Streams the file. `Content-Length` is the recorded size and
  /// `X-Content-SHA256` the recorded digest, so a client can verify what it
  /// saved.
  Future<Response> _download(Request request, String id) =>
      guardArtifacts(() async {
        final download = await _artifacts.download(id);
        final record = download.record;
        return Response.ok(
          download.content,
          headers: {
            'content-type': 'application/octet-stream',
            'content-length': '${record.size}',
            'x-content-sha256': record.sha256,
            'content-disposition': 'attachment; filename="${record.name}"',
          },
        );
      });
}

/// Runs [action] and turns the failures a client can cause into error
/// responses. Anything else is left to the error middleware (`500`).
Future<Response> guardArtifacts(Future<Response> Function() action) async {
  try {
    return await action();
  } on ArtifactNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on JobNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  }
}
