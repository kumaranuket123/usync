import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Debug builds only: prints one line per request the app sends to the backend,
/// with a running total, so the cost of a screen or an action can be counted.
/// It logs the method, path and timing, never headers or bodies (those carry
/// the session token and personal data).
class ApiCallLogger extends http.BaseClient {
  ApiCallLogger([http.Client? inner]) : _inner = inner ?? http.Client();
  final http.Client _inner;

  static int total = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final n     = ++total;
    final timer = Stopwatch()..start();
    try {
      final response = await _inner.send(request);
      debugPrint('[api #$n] ${request.method} ${_describe(request.url)} -> ${response.statusCode} ${timer.elapsedMilliseconds}ms');
      return response;
    } catch (e) {
      debugPrint('[api #$n] ${request.method} ${_describe(request.url)} -> failed ${timer.elapsedMilliseconds}ms');
      rethrow;
    }
  }

  static String _describe(Uri url) {
    final path  = url.path.replaceFirst('/rest/v1/', 'db/').replaceFirst('/storage/v1/', 'storage/')
        .replaceFirst('/functions/v1/', 'fn/').replaceFirst('/auth/v1/', 'auth/');
    final query = url.query.length > 60 ? '${url.query.substring(0, 60)}…' : url.query;
    return query.isEmpty ? path : '$path?$query';
  }
}
