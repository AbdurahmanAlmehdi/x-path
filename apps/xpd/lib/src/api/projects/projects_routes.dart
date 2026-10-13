import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/responses.dart';

/// The `/projects` endpoints: add a repository by path or remote, scan it,
/// edit its profile, list and remove.
class ProjectsRoutes {
  /// Creates the routes over [_projects].
  const new(this._projects);

  final ProjectService _projects;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..post('/projects', _add)
      ..get('/projects', _list)
      ..get('/projects/<id>', _get)
      ..post('/projects/<id>/scan', _scan)
      ..patch('/projects/<id>', _update)
      ..delete('/projects/<id>', _remove);
  }

  Future<Response> _add(Request request) => _guard(() async {
    final body = await _body(request, AddProjectRequest.fromJson);
    final project = await _projects.add(body);
    return jsonResponse(
      project.toJson(),
      statusCode: 201,
      headers: {'location': '/projects/${project.id}'},
    );
  });

  Future<Response> _list(Request request) => _guard(() async {
    return jsonResponse(ProjectsResponse(await _projects.list()).toJson());
  });

  Future<Response> _get(Request request, String id) => _guard(() async {
    return jsonResponse((await _projects.get(id)).toJson());
  });

  Future<Response> _scan(Request request, String id) => _guard(() async {
    return jsonResponse((await _projects.scan(id)).toJson());
  });

  Future<Response> _update(Request request, String id) => _guard(() async {
    final edits = await _body(request, ProfileEdits.fromJson);
    return jsonResponse((await _projects.update(id, edits)).toJson());
  });

  Future<Response> _remove(Request request, String id) => _guard(() async {
    await _projects.remove(id);
    return Response(204);
  });
}

/// The JSON object in the body of [request], read with [fromJson].
///
/// Throws a [_BadRequest] if the body is not a JSON object of the right shape.
Future<T> _body<T>(
  Request request,
  T Function(Map<String, dynamic> json) fromJson,
) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(await request.readAsString());
  } on FormatException {
    throw const _BadRequest('The body is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const _BadRequest('The body must be a JSON object.');
  }
  try {
    return fromJson(decoded);
  } on CheckedFromJsonException catch (error) {
    throw _BadRequest(
      'The body has a field that is missing or of the wrong type'
      '${error.key == null ? '' : ': ${error.key}'}.',
    );
  }
}

class _BadRequest implements Exception {
  const new(this.message);

  final String message;
}

/// Runs [action] and turns the failures a client can cause or fix into error
/// responses. Anything else is left to the error middleware (`500`).
Future<Response> _guard(Future<Response> Function() action) async {
  try {
    return await action();
  } on _BadRequest catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on ProjectNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on ProjectExistsException catch (error) {
    return errorResponse(ApiErrorCode.conflict, error.message);
  } on ProjectInUseException catch (error) {
    return errorResponse(ApiErrorCode.conflict, error.message);
  } on ProjectInvalidException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on GitHubNotFoundException {
    return errorResponse(
      ApiErrorCode.notFound,
      'GitHub cannot find that repository, or the token cannot see it.',
    );
  } on GitHubException catch (error) {
    return errorResponse(
      ApiErrorCode.upstreamError,
      'GitHub refused the request: ${error.message}',
    );
  } on GitException catch (error) {
    return errorResponse(ApiErrorCode.upstreamError, error.message);
  } on SecretsLockedException {
    return errorResponse(
      ApiErrorCode.secretsLocked,
      'The engine cannot read its secrets right now. Unlock them and retry.',
    );
  }
}
