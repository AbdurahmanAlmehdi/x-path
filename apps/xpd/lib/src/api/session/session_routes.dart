import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/allowed_origins.dart';
import 'package:xpd/src/api/api_router.dart';
import 'package:xpd/src/api/legacy_alias.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';
import 'package:xpd/src/api/session/session_cookie.dart';
import 'package:xpd/src/api/tokens/tokens_routes.dart';

/// Browser sessions of the web dashboard (ADR 0018):
///
/// - `POST /session` exchanges a one-time sign-in code for a `web` token in
///   the session cookie (D3a, D10, D11). It needs no token, and works only
///   from an origin the engine serves (D15): this machine, or the HTTPS
///   public URL (D3).
/// - `DELETE /session` signs the browser out: its token is revoked and the
///   cookie cleared.
/// - `POST /people/{id}/sign-in-codes` issues a code (D9): an admin's for
///   anyone, a person's own `app` or `cli` token for them.
///
/// Every answer is `Cache-Control: no-store`.
class SessionRoutes {
  /// Creates the routes.
  const new({
    required this._signIn,
    required this._tokens,
    required this._origins,
  });

  /// The routes that need no token.
  static const publicRoutes = {'POST /session'};

  final SignInCodeService _signIn;
  final TokenService _tokens;
  final AllowedOrigins _origins;

  /// Registers the routes on [router].
  void addTo(ApiRouter router) {
    router
      ..post('/session', _signInWith)
      ..delete('/session', _signOut)
      ..post('/people/<id>/sign-in-codes', _issue);
  }

  Future<Response> _signInWith(Request request) async {
    if (!isUnderApiMount(request)) {
      return errorResponse(
        ApiErrorCode.notFound,
        'A browser signs in under $apiMount.',
        headers: noStore,
      );
    }
    final kind = await _origins.of(request);
    if (request.headers['origin'] == null) {
      return errorResponse(
        ApiErrorCode.csrf,
        'Sign in from a page of the engine: the request has no Origin.',
        headers: noStore,
      );
    }
    if (kind == null ||
        (kind == OriginKind.loopback &&
            !AllowedOrigins.fromLoopback(request))) {
      return errorResponse(
        ApiErrorCode.forbidden,
        'A browser signs in only on the engine machine, or through the '
        "engine's HTTPS public URL: the engine has no TLS, so a sign-in over "
        'plain HTTP from another machine is refused.',
        hint:
            'Put an HTTPS proxy in front of the engine and set its address '
            "as the engine's public URL, or sign in on the engine machine.",
        headers: noStore,
      );
    }
    final SignInRequest body;
    try {
      body = await readJsonBody(request, SignInRequest.fromJson);
    } on BadRequestException catch (error) {
      return errorResponse(
        ApiErrorCode.invalidRequest,
        error.message,
        headers: noStore,
      );
    }
    final IssuedToken issued;
    try {
      issued = await _signIn.signIn(
        body.code,
        address: AllowedOrigins.remoteAddressOf(request) ?? 'unknown',
      );
    } on SignInRejectedException catch (error) {
      return errorResponse(
        ApiErrorCode.unauthorized,
        error.message,
        headers: noStore,
      );
    } on SignInRateLimitedException catch (error) {
      final seconds = (error.retryAfter.inMilliseconds / 1000).ceil();
      return errorResponse(
        ApiErrorCode.rateLimited,
        error.message,
        headers: {...noStore, 'retry-after': '$seconds'},
      );
    }
    final token = issued.token;
    return jsonResponse(
      Me(
        person: token.person!,
        token: TokensRoutes.infoOf(token),
        permissions: AccessPolicy.permissionsOf(token),
      ).toJson(),
      headers: {
        ...noStore,
        'set-cookie': SessionCookie.set(
          request,
          kind,
          issued.secret,
          TokenService.webSessionLifetime,
        ),
      },
    );
  }

  Future<Response> _signOut(Request request) async {
    final token = deviceTokenOf(request);
    if (!AccessPolicy.maySignOut(token)) {
      return errorResponse(
        ApiErrorCode.forbidden,
        'Only a browser session signs out; revoke a ${token.kind.name} token '
        'with DELETE /tokens/{id}.',
        headers: noStore,
      );
    }
    await _tokens.revoke(token.id);
    final cleared = SessionCookie.clear(request);
    return Response(
      204,
      headers: {...noStore, if (cleared.isNotEmpty) 'set-cookie': cleared},
    );
  }

  Future<Response> _issue(Request request, String id) async {
    try {
      final code = await _signIn.issueFor(deviceTokenOf(request), id);
      return jsonResponse(code.toJson(), statusCode: 201, headers: noStore);
    } on SignInForbiddenException catch (error) {
      return errorResponse(
        ApiErrorCode.forbidden,
        error.message,
        headers: noStore,
      );
    } on PersonNotFoundException catch (error) {
      return errorResponse(
        ApiErrorCode.notFound,
        error.message,
        headers: noStore,
      );
    }
  }
}
