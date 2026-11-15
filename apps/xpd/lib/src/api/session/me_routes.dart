import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/api_router.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/responses.dart';
import 'package:xpd/src/api/tokens/tokens_routes.dart';

/// `GET /me`: the person the token that asks belongs to, and what it may do
/// (D16), so a client hides what it may not do without deciding it itself.
class MeRoutes {
  /// Creates the route.
  const new();

  /// Registers the route on [router].
  void addTo(ApiRouter router) {
    router.get('/me', _me);
  }

  Response _me(Request request) {
    final token = deviceTokenOf(request);
    // Every token that reaches here has a person: a runner token is kept to
    // the runner routes (ADR 0011).
    final person = token.person!;
    return jsonResponse(
      Me(
        person: person,
        token: TokensRoutes.infoOf(token),
        permissions: AccessPolicy.permissionsOf(token),
      ).toJson(),
      headers: const {'cache-control': 'no-store'},
    );
  }
}
