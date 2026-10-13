import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';

/// The most tests a page can hold.
const maxTestsPageSize = 1000;

/// How many tests a page holds unless the request says.
const defaultTestsPageSize = 200;

/// The test endpoints: the run of a job with what changed against the
/// baseline, and the baselines of a project.
class TestsRoutes {
  /// Creates the routes over [_tests].
  const new(this._tests);

  final TestRunService _tests;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/jobs/<id>/tests', _forJob)
      ..get('/projects/<id>/tests/baseline', _baselines);
  }

  Future<Response> _forJob(Request request, String id) => guardTests(() async {
    final query = request.url.queryParameters;
    final page = await _tests.forJob(
      id,
      statuses: _statuses(query['status']),
      limit: _number(
        query['limit'],
        'limit',
        min: 1,
        max: maxTestsPageSize,
        fallback: defaultTestsPageSize,
      ),
      offset: _number(query['offset'], 'offset', min: 0, fallback: 0),
    );
    return jsonResponse(
      TestRunResponse(
        run: page.run.toTestRun(),
        total: page.total,
        offset: page.offset,
        tests: page.tests,
      ).toJson(),
    );
  });

  Future<Response> _baselines(Request request, String id) =>
      guardTests(() async {
        final runs = await _tests.baselines(id);
        return jsonResponse(
          TestBaselinesResponse([for (final run in runs) run.toTestBaseline()])
              .toJson(),
        );
      });

  Set<TestStatus> _statuses(String? param) {
    if (param == null) return TestRunService.defaultStatuses;
    final statuses = <TestStatus>{};
    for (final name in param.split(',')) {
      final status = TestStatus.values
          .where((status) => status.wire == name)
          .firstOrNull;
      if (status == null) {
        throw BadRequestException(
          '"status" must list passed, failed, errored or skipped, separated '
          'by commas, not "$name".',
        );
      }
      statuses.add(status);
    }
    return statuses;
  }

  int _number(
    String? param,
    String name, {
    required int min,
    required int fallback,
    int? max,
  }) {
    if (param == null) return fallback;
    final value = int.tryParse(param);
    if (value == null || value < min || (max != null && value > max)) {
      throw BadRequestException(
        '"$name" must be a number from $min'
        '${max == null ? ' up' : ' to $max'}.',
      );
    }
    return value;
  }
}

/// Runs [action] and turns the failures a client can cause into error
/// responses. Anything else is left to the error middleware (`500`).
Future<Response> guardTests(Future<Response> Function() action) async {
  try {
    return await action();
  } on BadRequestException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on JobNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on TestRunNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on ProjectNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  }
}
