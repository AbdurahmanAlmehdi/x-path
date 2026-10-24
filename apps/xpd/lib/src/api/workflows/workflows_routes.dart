import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';

/// The workflow endpoints: the schema documents follow, the templates and a
/// check of a document, and per project list, create, save a new version,
/// rename or archive, validate, delete, and dispatch.
class WorkflowsRoutes {
  /// Creates the routes over the workflows and the dispatcher.
  const new(this._workflows, this._dispatcher);

  final WorkflowService _workflows;
  final WorkflowDispatcher _dispatcher;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/workflows/schema', _schema)
      ..get('/workflows/templates', _templates)
      ..post('/workflows/validate', _validateDocument)
      ..get('/projects/<id>/workflows', _list)
      ..post('/projects/<id>/workflows', _create)
      // Before `<workflowId>`: `validate` is not a workflow id.
      ..post('/projects/<id>/workflows/validate', _validate)
      ..get('/projects/<id>/workflows/<workflowId>', _get)
      ..put('/projects/<id>/workflows/<workflowId>', _save)
      ..patch('/projects/<id>/workflows/<workflowId>', _update)
      ..delete('/projects/<id>/workflows/<workflowId>', _remove)
      ..post('/projects/<id>/workflows/<workflowId>/dispatch', _dispatch)
      ..post('/runs/<id>/run-again', _again);
  }

  Response _schema(Request request) =>
      jsonResponse(_workflows.schema().toJson());

  Response _templates(Request request) =>
      jsonResponse(WorkflowTemplatesResponse(_workflows.templates()).toJson());

  Future<Response> _list(Request request, String id) =>
      guardWorkflows(() async {
        return jsonResponse(
          WorkflowsResponse(await _workflows.list(id)).toJson(),
        );
      });

  Future<Response> _create(Request request, String id) => guardWorkflows(
    () async {
      final body = await readJsonBody(request, CreateWorkflowRequest.fromJson);
      final workflow = await _workflows.create(
        id,
        name: body.name,
        yaml: body.yaml,
        basedOn: body.basedOn,
      );
      return jsonResponse(
        workflow.toJson(),
        statusCode: 201,
        headers: {'location': '/projects/$id/workflows/${workflow.id}'},
      );
    },
  );

  Future<Response> _validate(Request request, String id) =>
      _validateDocument(request);

  Future<Response> _validateDocument(Request request) =>
      guardWorkflows(() async {
        final body = await readJsonBody(request, WorkflowYamlRequest.fromJson);
        return jsonResponse(_workflows.validate(body.yaml).toJson());
      });

  Future<Response> _get(Request request, String id, String workflowId) =>
      guardWorkflows(() async {
        final param = request.url.queryParameters['version'];
        final version = param == null ? null : int.tryParse(param);
        if (param != null && (version == null || version < 1)) {
          return errorResponse(
            ApiErrorCode.invalidRequest,
            'version must be a positive integer.',
          );
        }
        return jsonResponse(
          (await _workflows.get(id, workflowId, version: version)).toJson(),
        );
      });

  Future<Response> _save(Request request, String id, String workflowId) =>
      guardWorkflows(() async {
        final body = await readJsonBody(request, WorkflowYamlRequest.fromJson);
        return jsonResponse(
          (await _workflows.save(id, workflowId, body.yaml)).toJson(),
        );
      });

  Future<Response> _update(Request request, String id, String workflowId) =>
      guardWorkflows(() async {
        final body = await readJsonBody(
          request,
          UpdateWorkflowRequest.fromJson,
        );
        return jsonResponse(
          (await _workflows.update(id, workflowId, body)).toJson(),
        );
      });

  Future<Response> _again(Request request, String id) =>
      guardWorkflows(() async {
        final run = await _dispatcher.again(id);
        return jsonResponse(
          run.toJson(),
          statusCode: 202,
          headers: {'location': '/runs/${run.id}'},
        );
      });

  Future<Response> _remove(Request request, String id, String workflowId) =>
      guardWorkflows(() async {
        await _workflows.remove(id, workflowId);
        return Response(204);
      });

  Future<Response> _dispatch(Request request, String id, String workflowId) =>
      guardWorkflows(() async {
        final body = await request.readAsString();
        final dispatch = body.trim().isEmpty
            ? const DispatchRequest()
            : await readJsonBody(
                request.change(body: body),
                DispatchRequest.fromJson,
              );
        final dryRun = request.url.queryParameters['dryRun'];
        if (dryRun != null && dryRun != 'true' && dryRun != 'false') {
          throw const BadRequestException('dryRun must be true or false.');
        }
        if (dryRun == 'true') {
          final plan = await _dispatcher.plan(id, workflowId, dispatch);
          return jsonResponse(plan.toJson());
        }
        final run = await _dispatcher.dispatch(id, workflowId, dispatch);
        return jsonResponse(
          run.toJson(),
          statusCode: 202,
          headers: {'location': '/runs/${run.id}'},
        );
      });
}

/// Runs [action] and turns the failures a client can cause or fix into error
/// responses. Anything else is left to the error middleware (`500`).
Future<Response> guardWorkflows(Future<Response> Function() action) async {
  try {
    return await action();
  } on BadRequestException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on ProjectNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on WorkflowNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on RunNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on WorkflowExistsException catch (error) {
    return errorResponse(ApiErrorCode.conflict, error.message);
  } on WorkflowBuiltinException catch (error) {
    return errorResponse(ApiErrorCode.conflict, error.message);
  } on WorkflowInUseException catch (error) {
    return errorResponse(
      ApiErrorCode.conflict,
      error.message,
      details: const {'reason': ErrorReason.hasRuns},
    );
  } on WorkflowArchivedException catch (error) {
    return errorResponse(
      ApiErrorCode.conflict,
      error.message,
      details: const {'reason': ErrorReason.archived},
    );
  } on WorkflowNameException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on WorkflowEditException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on WorkflowInvalidException catch (error) {
    return errorResponse(
      ApiErrorCode.workflowInvalid,
      error.message,
      issues: error.issues,
      hint: 'Fix the issues at their lines, then save or dispatch again.',
    );
  } on DispatchException catch (error) {
    return errorResponse(
      ApiErrorCode.workflowInvalid,
      error.message,
      hint: error.hint,
      details: error.details,
    );
  } on GitException catch (error) {
    return errorResponse(ApiErrorCode.upstreamError, error.message);
  } on SecretsLockedException {
    return secretsLockedResponse();
  }
}
