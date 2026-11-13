import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/api_router.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/responses.dart';
import 'package:xpd/src/api/route_permissions.dart';

/// The methods that read: they need no permission beyond a token.
const _reading = {'GET', 'HEAD', 'OPTIONS'};

/// Refuses a request to a mutating route of [routes] with `403 forbidden`
/// unless its token has the permission [table] names for the route
/// (ADR 0017). A route missing from [table] needs [unlistedRouteAccess].
///
/// The first route that matches decides, in the order the router tries
/// them. A request no route matches goes on to the router's `404`, and one
/// without a token (a public path) goes on as it is.
///
/// Add it after [authMiddleware]: it reads the token that middleware found.
Middleware permissionMiddleware(
  List<ApiRoute> routes, {
  Map<String, RouteAccess> table = routePermissions,
}) {
  final mutating = [
    for (final route in routes)
      if (!_reading.contains(route.method))
        (
          method: route.method,
          pattern: _patternOf(route.path),
          access: table['${route.method} ${route.path}'] ?? unlistedRouteAccess,
        ),
  ];
  return (inner) => (request) async {
    final token = deviceTokenIfAny(request);
    if (token == null || _reading.contains(request.method)) {
      return await inner(request);
    }
    final path = '/${request.url.path}';
    final route = mutating
        .where((r) => r.method == request.method && r.pattern.hasMatch(path))
        .firstOrNull;
    final permission = route?.access.permission;
    if (route == null || permission == null) return await inner(request);
    final refusal = AccessPolicy.refusal(token, permission, route.access.what);
    if (refusal == null) return await inner(request);
    return errorResponse(ApiErrorCode.forbidden, refusal);
  };
}

/// The paths a route pattern such as `/runs/<id>/cancel` matches: each
/// `<name>` is one path segment, as in `shelf_router`.
RegExp _patternOf(String route) =>
    RegExp('^${route.split(_parameter).map(RegExp.escape).join('[^/]+')}\$');

final _parameter = RegExp('<[^>]+>');
