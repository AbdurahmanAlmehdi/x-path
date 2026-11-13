import 'dart:io' show HttpDate;

import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xpd/src/api/responses.dart';

/// Where the API is served (ADR 0018).
const apiMount = '/api/v1';

/// When the root paths stop being aliases of the API: the `Sunset` header
/// of every answer to one (ADR 0018).
final legacySunset = DateTime.utc(2027, 11, 14);

/// Sends a request to [api] when it is under [apiMount], or when it is to a
/// root path and carries `Authorization` or is one of [publicPaths]: the
/// root paths stay bearer-only aliases of the API, for the clients made
/// before it moved (ADR 0018). Every other request is not the API: it gets
/// a JSON `404`.
///
/// [api] serves the paths relative to [apiMount]: under it, the request
/// reaches [api] with [apiMount] as its handler path, and a `Location` the
/// API answers with is put under [apiMount] too. An answer to an alias says
/// it is deprecated (`Deprecation`, `Sunset`, and a `Link` to the same path
/// under [apiMount]). Every answer to a root path varies by `Authorization`,
/// since that header alone decides whether it is the API.
Handler legacyAlias(Handler api, {required Set<String> publicPaths}) {
  final mount = apiMount.substring(1);
  final sunset = HttpDate.format(legacySunset);
  return (request) async {
    final path = request.url.path;
    if (path == mount || path.startsWith('$mount/')) {
      return _mounted(await api(request.change(path: mount)));
    }
    final alias =
        request.headers.containsKey('authorization') ||
        publicPaths.contains('/$path');
    if (!alias) return _notTheApi(request).change(headers: _vary);
    return (await api(request)).change(
      headers: {
        ..._vary,
        'deprecation': 'true',
        'sunset': sunset,
        'link': '<$apiMount/$path>; rel="successor-version"',
      },
    );
  };
}

/// Whether [request] came to the API under [apiMount], not to a root alias.
/// Only there does the session cookie authenticate (ADR 0018).
bool isUnderApiMount(Request request) => request.handlerPath == '$apiMount/';

const _vary = {'vary': 'Authorization'};

/// Puts a root-relative `Location` of [response] under [apiMount].
Response _mounted(Response response) {
  final location = response.headers['location'];
  if (location == null || !location.startsWith('/')) return response;
  return response.change(headers: {'location': '$apiMount$location'});
}

Response _notTheApi(Request request) => errorResponse(
  ApiErrorCode.notFound,
  'Nothing is served at /${request.url.path}. The API is under $apiMount.',
);
