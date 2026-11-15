import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xpd/src/api/allowed_origins.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/responses.dart';

/// The header a browser request that changes something carries (D14). A
/// page on another site cannot add it without a CORS preflight, which fails:
/// the engine sends no CORS headers.
const csrfHeader = 'x-xpath-csrf';

const _safe = {'GET', 'HEAD', 'OPTIONS'};

/// Refuses, with `403 csrf`, a request authenticated by the session cookie
/// whose method changes something, unless it carries `X-XPath-CSRF: 1` and
/// an `Origin` of [origins] (ADR 0018, D14). An absent `Origin` is refused.
///
/// A bearer request is not affected: its cookie is never read. Add it after
/// [authMiddleware]: it reads how that one authenticated the request.
Middleware csrfMiddleware(AllowedOrigins origins) =>
    (inner) => (request) async {
      if (_safe.contains(methodOf(request)) ||
          !authenticatedByCookie(request)) {
        return await inner(request);
      }
      if (request.headers[csrfHeader] != '1') {
        return errorResponse(
          ApiErrorCode.csrf,
          'A browser request that changes something needs the header '
          'X-XPath-CSRF: 1.',
        );
      }
      if (await origins.of(request) == null) {
        return errorResponse(
          ApiErrorCode.csrf,
          'A browser request that changes something must come from a page '
          'of the engine: its Origin is missing or not one the engine '
          'serves.',
        );
      }
      return await inner(request);
    };
