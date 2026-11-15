import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An HTTP client that answers only the probe for `/api/v1`, as an engine
/// that serves the API there does: for a client whose requests are all
/// WebSockets.
http.Client apiProbeOnly() => MockClient(
  (request) async => http.Response(
    '{"version": "9.9.9", "apiVersion": "1"}',
    request.url.path == '/api/v1/version' ? 200 : 404,
  ),
);
