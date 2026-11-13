import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// A route of the API: its method and its path as it was registered, for
/// example `POST /runs/<id>/cancel`.
typedef ApiRoute = ({String method, String path});

/// The router of the API: a `shelf_router` [Router] that remembers the
/// routes registered on it, in order, so that the permission middleware
/// knows which route a request reaches and a test can walk them.
class ApiRouter {
  /// Creates the router; [notFoundHandler] answers a path no route has.
  new({Handler? notFoundHandler})
    : _router = notFoundHandler == null
          ? Router()
          : Router(notFoundHandler: notFoundHandler);

  final Router _router;
  final _routes = <ApiRoute>[];

  /// Every route registered, in order.
  List<ApiRoute> get routes => List.unmodifiable(_routes);

  /// Handles [request] with the first route that matches it.
  Future<Response> call(Request request) => _router.call(request);

  /// Routes `GET` (and `HEAD`) [route] to [handler].
  void get(String route, Function handler) => _add('GET', route, handler);

  /// Routes `POST` [route] to [handler].
  void post(String route, Function handler) => _add('POST', route, handler);

  /// Routes `PUT` [route] to [handler].
  void put(String route, Function handler) => _add('PUT', route, handler);

  /// Routes `PATCH` [route] to [handler].
  void patch(String route, Function handler) => _add('PATCH', route, handler);

  /// Routes `DELETE` [route] to [handler].
  void delete(String route, Function handler) => _add('DELETE', route, handler);

  void _add(String method, String route, Function handler) {
    _routes.add((method: method, path: route));
    _router.add(method, route, handler);
  }
}
