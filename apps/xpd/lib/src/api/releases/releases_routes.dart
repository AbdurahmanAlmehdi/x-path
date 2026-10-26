import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';
import 'package:xpd/src/api/workflows/workflows_routes.dart';

/// The release endpoints (D-17): list and read the releases, read the notes
/// of one for Slack and WhatsApp (D-22), ask the stores
/// about one now, say what a store did by hand, build the same version again
/// after a rejection, request the merge of the pull request, request a change
/// of the rollout in a store (U7a) and give a release up.
///
/// Anyone with a token may read, refresh, start a new build and request the
/// merge or a rollout change: these are gated actions, which wait for the owner
/// to approve them (D-13). Setting a store status and abandoning are for `app`
/// and `cli` tokens only, because a status moves a release toward the merge
/// of its pull request; the rules are the [ReleaseService]'s, and a token that
/// may not answers `403 forbidden`.
class ReleasesRoutes {
  /// Creates the routes over [_releases].
  const new(this._releases, this._notes);

  final ReleaseService _releases;
  final ReleaseNotesService _notes;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/releases', _list)
      ..get('/releases/<id>', _get)
      ..get('/releases/<id>/notes', _getNotes)
      ..post('/releases/<id>/refresh', _refresh)
      ..post('/releases/<id>/stores/<store>/status', _setStatus)
      ..post('/releases/<id>/builds', _newBuild)
      ..post('/releases/<id>/merge', _merge)
      ..post('/releases/<id>/rollout', _rollout)
      ..post('/releases/<id>/abandon', _abandon);
  }

  Future<Response> _list(Request request) => _guard(() async {
    final query = request.requestedUri.queryParameters;
    final wanted = query['state'];
    final state = wanted == null
        ? null
        : ReleaseState.values.where((s) => s.wire == wanted).firstOrNull ??
              (throw BadRequestException(
                '"$wanted" is not a release state. The states are: '
                '${ReleaseState.values.map((s) => s.wire).join(', ')}.',
              ));
    final releases = await _releases.list(
      projectId: query['project'],
      appPath: query['app'],
      state: state,
    );
    return jsonResponse(ReleasesResponse(releases).toJson());
  });

  Future<Response> _get(Request request, String id) => _guard(() async {
    return jsonResponse((await _releases.get(id)).toJson());
  });

  Future<Response> _getNotes(Request request, String id) => _guard(() async {
    return jsonResponse((await _notes.forRelease(id)).toJson());
  });

  Future<Response> _refresh(Request request, String id) => _guard(() async {
    return jsonResponse((await _releases.refresh(id)).toJson());
  });

  Future<Response> _setStatus(Request request, String id, String store) =>
      _guard(() async {
        final named = ReleaseStore.values
            .where((candidate) => candidate.wire == store)
            .firstOrNull;
        if (named == null) {
          throw BadRequestException(
            '"$store" is not a store. The stores are: '
            '${ReleaseStore.values.map((s) => s.wire).join(', ')}.',
          );
        }
        final body = await readJsonBody(request, StoreStatusRequest.fromJson);
        final release = await _releases.setStoreStatus(
          id,
          named,
          body.state,
          by: deviceTokenOf(request),
        );
        return jsonResponse(release.toJson());
      });

  Future<Response> _newBuild(Request request, String id) => _guard(() async {
    return _accepted(await _releases.newBuild(id));
  });

  Future<Response> _merge(Request request, String id) => _guard(() async {
    return _accepted(await _releases.requestMerge(id));
  });

  Future<Response> _rollout(Request request, String id) => _guard(() async {
    final body = await readJsonBody(request, RolloutRequest.fromJson);
    return _accepted(await _releases.requestRollout(id, body));
  });

  Future<Response> _abandon(Request request, String id) => _guard(() async {
    final body = await readOptionalJsonBody(
      request,
      AbandonRequest.fromJson,
      whenEmpty: const AbandonRequest(),
    );
    final release = await _releases.abandon(
      id,
      by: deviceTokenOf(request),
      reason: body.reason,
    );
    return jsonResponse(release.toJson());
  });

  Response _accepted(Run run) => jsonResponse(
    run.toJson(),
    statusCode: 202,
    headers: {'location': '/runs/${run.id}'},
  );
}

/// Runs [action] and turns the failures a client can cause or fix into error
/// responses: the release ones here, the dispatch ones as the workflow
/// endpoints do. Anything else is left to the error middleware (`500`).
Future<Response> _guard(Future<Response> Function() action) =>
    guardWorkflows(() async {
      try {
        return await action();
      } on ReleaseNotFoundException catch (error) {
        return errorResponse(ApiErrorCode.notFound, error.message);
      } on ReleaseForbiddenException catch (error) {
        return errorResponse(ApiErrorCode.forbidden, error.message);
      } on ReleaseStateException catch (error) {
        return errorResponse(ApiErrorCode.conflict, error.message);
      } on ReleaseRequestException catch (error) {
        return errorResponse(ApiErrorCode.invalidRequest, error.message);
      }
    });
