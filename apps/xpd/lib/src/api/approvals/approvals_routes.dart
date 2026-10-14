import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';

/// The approval endpoints (D-13): list, read, approve and deny; and the gates
/// of a project.
///
/// Anyone with a token may read. Only `app` and `cli` tokens approve or deny,
/// only they change gates, and only `app` tokens loosen them; the rules are
/// the [ApprovalService]'s, and a token that may not answers `403
/// forbidden`. A decision that lost the race answers `409 already_decided`
/// with the approval that won.
class ApprovalsRoutes {
  /// Creates the routes over [_approvals].
  const new(this._approvals);

  final ApprovalService _approvals;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/approvals', _list)
      ..get('/approvals/<id>', _get)
      ..post('/approvals/<id>/approve', (Request request, String id) {
        return _decide(request, id, approve: true);
      })
      ..post('/approvals/<id>/deny', (Request request, String id) {
        return _decide(request, id, approve: false);
      })
      ..get('/projects/<id>/gates', _gates)
      ..put('/projects/<id>/gates', _setGates);
  }

  Future<Response> _list(Request request) => _guard(() async {
    final query = request.requestedUri.queryParameters;
    final wanted = query['state'];
    final state = wanted == null
        ? null
        : ApprovalState.values
                  .where((state) => state.wire == wanted)
                  .firstOrNull ??
              (throw BadRequestException(
                '"$wanted" is not an approval state. The states are: '
                '${ApprovalState.values.map((s) => s.wire).join(', ')}.',
              ));
    final approvals = await _approvals.list(
      projectId: query['project'],
      state: state,
    );
    return jsonResponse(ApprovalsResponse(approvals).toJson());
  });

  Future<Response> _get(Request request, String id) => _guard(() async {
    return jsonResponse((await _approvals.get(id)).toJson());
  });

  Future<Response> _decide(
    Request request,
    String id, {
    required bool approve,
  }) => _guard(() async {
    final body = await readOptionalJsonBody(
      request,
      DecisionRequest.fromJson,
      whenEmpty: const DecisionRequest(),
    );
    final approval = await _approvals.decide(
      id,
      approve: approve,
      by: deviceTokenOf(request),
      reason: body.reason,
    );
    return jsonResponse(approval.toJson());
  });

  Future<Response> _gates(Request request, String id) => _guard(() async {
    return jsonResponse((await _approvals.gates(id)).toJson());
  });

  Future<Response> _setGates(Request request, String id) => _guard(() async {
    final desired = await readJsonBody(request, ProjectGates.fromJson);
    final gates = await _approvals.setGates(
      id,
      desired,
      by: deviceTokenOf(request),
    );
    return jsonResponse(gates.toJson());
  });
}

/// Runs [action] and turns the failures a client can cause or fix into error
/// responses. Anything else is left to the error middleware (`500`).
Future<Response> _guard(Future<Response> Function() action) async {
  try {
    return await action();
  } on BadRequestException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on ApprovalRequestException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on ApprovalForbiddenException catch (error) {
    return errorResponse(ApiErrorCode.forbidden, error.message);
  } on ApprovalNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on ProjectNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on ApprovalAlreadyDecidedException catch (error) {
    return jsonResponse({
      ...ErrorResponse.of(ApiErrorCode.alreadyDecided, error.message).toJson(),
      'approval': error.approval.toJson(),
    }, statusCode: ApiErrorCode.alreadyDecided.statusCode);
  }
}
