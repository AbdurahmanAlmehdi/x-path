import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';

/// Device tokens over the API (U5b): the owner's app makes a token for `xp`
/// or `xp mcp` without the `xpd` binary. The secret of a new token is in the answer of `POST /tokens` only;
/// no other response, log or error carries it.
class TokensRoutes {
  /// Creates the routes over [_tokens].
  const new(this._tokens);

  final TokenService _tokens;

  /// The kinds `POST /tokens` makes: an app or a runner token comes from
  /// `xpd token create` and pairing only.
  static const Set<DeviceTokenKind> _mintable = {
    DeviceTokenKind.cli,
    DeviceTokenKind.mcp,
  };

  /// Registers the routes on [router].
  void addTo(Router router) {
    router.post('/tokens', _create);
  }

  Future<Response> _create(Request request) async {
    if (deviceTokenOf(request).kind != DeviceTokenKind.app) {
      return errorResponse(
        ApiErrorCode.forbidden,
        'Only the app makes tokens: a token may not make others.',
      );
    }
    final CreateTokenRequest body;
    try {
      body = await readJsonBody(request, _parse);
    } on BadRequestException catch (error) {
      return errorResponse(ApiErrorCode.invalidRequest, error.message);
    }
    final issued = await _tokens.issue(name: body.name, kind: body.kind);
    return jsonResponse(
      CreatedToken(info: infoOf(issued.token), token: issued.secret).toJson(),
      statusCode: 201,
    );
  }

  /// [token] as the API shows it: never its hash.
  static TokenInfo infoOf(DeviceToken token) => TokenInfo(
    id: token.id,
    name: token.name,
    kind: token.kind,
    createdAt: token.createdAt,
  );

  static CreateTokenRequest _parse(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const BadRequestException('"name" must be a non-blank string.');
    }
    final kind = _mintable
        .where((kind) => kind.name == json['kind'])
        .firstOrNull;
    if (kind == null) {
      throw const BadRequestException('"kind" must be "cli" or "mcp".');
    }
    return CreateTokenRequest(name: name.trim(), kind: kind);
  }
}
