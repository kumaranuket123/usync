import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'network_errors.dart';

/// A message a person can act on, instead of the exception's own text
/// ("AuthApiException(message: …, statusCode: 400, …)").
String friendlyAuthMessage(Object error) {
  if (isNetworkError(error)) {
    return 'No connection. Check your internet and try again.';
  }
  if (error is AuthException) {
    if (error.message.toLowerCase().contains('rate limit') || error.statusCode == '429') {
      return 'Too many attempts. Wait a moment and try again.';
    }
    // Other messages from the server are written for people, so show them as they are.
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}
