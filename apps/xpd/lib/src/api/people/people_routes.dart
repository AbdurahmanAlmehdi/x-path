import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/api_router.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';

/// The `/people` endpoints (ADR 0017): anyone lists and reads people; an
/// admin adds, renames, changes the role of and removes them. The route
/// table (`route_permissions.dart`) holds who may change them.
class PeopleRoutes {
  /// Creates the routes over [_people].
  const new(this._people);

  final PersonService _people;

  /// Registers the routes on [router].
  void addTo(ApiRouter router) {
    router
      ..get('/people', _list)
      ..post('/people', _create)
      ..get('/people/<id>', _get)
      ..patch('/people/<id>', _update)
      ..delete('/people/<id>', _remove);
  }

  Future<Response> _list(Request request) async =>
      jsonResponse(PeopleResponse(await _people.list()).toJson());

  Future<Response> _create(Request request) => _guard(() async {
    final body = await readJsonBody(request, CreatePersonRequest.fromJson);
    final person = await _people.create(name: body.name, role: body.role);
    return jsonResponse(
      person.toJson(),
      statusCode: 201,
      headers: {'location': '/people/${person.id}'},
    );
  });

  Future<Response> _get(Request request, String id) => _guard(() async {
    return jsonResponse((await _people.get(id)).toJson());
  });

  Future<Response> _update(Request request, String id) => _guard(() async {
    final body = await readJsonBody(request, UpdatePersonRequest.fromJson);
    final name = body.name;
    final role = body.role;
    if (name == null && role == null) {
      throw const BadRequestException('Give a "name", a "role" or both.');
    }
    if (name != null) await _people.rename(id, name);
    if (role != null) await _people.setRole(id, role);
    return jsonResponse((await _people.get(id)).toJson());
  });

  Future<Response> _remove(Request request, String id) => _guard(() async {
    await _people.remove(id);
    return Response(204);
  });

  static Future<Response> _guard(Future<Response> Function() action) async {
    try {
      return await action();
    } on BadRequestException catch (error) {
      return errorResponse(ApiErrorCode.invalidRequest, error.message);
    } on PersonNotFoundException catch (error) {
      return errorResponse(ApiErrorCode.notFound, error.message);
    } on PersonConflictException catch (error) {
      return errorResponse(ApiErrorCode.conflict, error.message);
    } on PersonRequestException catch (error) {
      return errorResponse(ApiErrorCode.invalidRequest, error.message);
    }
  }
}
