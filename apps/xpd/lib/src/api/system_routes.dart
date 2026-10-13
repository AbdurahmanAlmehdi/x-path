import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xpd/src/api/responses.dart';

/// `GET /health`: the engine answers, so it is healthy.
Response health(Request request) =>
    jsonResponse(const HealthResponse().toJson());

/// `GET /version` for an engine of [version].
Handler version(String version) =>
    (request) => jsonResponse(
      VersionResponse(version: version, apiVersion: apiVersion).toJson(),
    );
