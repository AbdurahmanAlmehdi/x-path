import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/responses.dart';
import 'package:xpd/src/api/tokens/tokens_routes.dart';

/// `GET /health`: the engine answers, so it is healthy.
Response health(Request request) =>
    jsonResponse(const HealthResponse().toJson());

/// `GET /version` for an engine of [version].
Handler version(String version) =>
    (request) => jsonResponse(
      VersionResponse(version: version, apiVersion: apiVersion).toJson(),
    );

/// `GET /doctor`: what the engine finds about the machine it runs on (U5b).
Handler doctor(EngineDoctor doctor) =>
    (request) async => jsonResponse((await doctor.examine()).toJson());

/// `GET /status`: the token that asks and whether the engine could reach its
/// secrets at its last try ([secrets]), for `xp status` (U5b).
Handler status(SecretStore secrets) =>
    (request) => jsonResponse(
      StatusResponse(
        token: TokensRoutes.infoOf(deviceTokenOf(request)),
        secretsLocked: secrets.status == SecretsStatus.locked,
      ).toJson(),
    );
