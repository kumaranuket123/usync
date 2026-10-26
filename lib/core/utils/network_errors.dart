import 'dart:async';
import 'dart:io';

/// True when [error] means the request never got a proper answer from the
/// server (no connection, timeout, a gateway error), so retrying later can
/// succeed. Anything else (a rejected row, a permissions error) will fail
/// the same way again and must not be retried forever.
bool isNetworkError(Object error) {
  if (error is SocketException || error is TimeoutException || error is HandshakeException) {
    return true;
  }
  // The http package's ClientException and Supabase's retryable auth error are
  // matched by name so this file needs no extra dependency.
  final type = error.runtimeType.toString();
  if (type == 'ClientException' || type == 'AuthRetryableFetchException' || type == 'WebSocketException') {
    return true;
  }
  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('Network is unreachable') ||
      text.contains('Connection closed') ||
      text.contains('Connection refused') ||
      text.contains('Connection reset') ||
      text.contains('Software caused connection abort')) {
    return true;
  }
  // A PostgrestException carries the HTTP status as its code: 5xx is the
  // server or a gateway being down, which is worth retrying.
  final code = _statusCode(error);
  return code != null && code >= 500 && code < 600;
}

int? _statusCode(Object error) {
  try {
    final code = (error as dynamic).code;
    return code is String ? int.tryParse(code) : (code is int ? code : null);
  } catch (_) {
    return null;
  }
}
