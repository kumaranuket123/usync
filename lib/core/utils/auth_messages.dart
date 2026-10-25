import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'network_errors.dart';

/// A message a person can act on, instead of the exception's own text
/// ("AuthApiException(message: Invalid login credentials, statusCode: 400, …)").
String friendlyAuthMessage(Object error) {
  if (isNetworkError(error)) {
    return 'No connection. Check your internet and try again.';
  }
  if (error is AuthException) {
    final text = error.message.toLowerCase();
    if (text.contains('invalid login credentials')) return 'Wrong email or password.';
    if (text.contains('email not confirmed'))       return 'Confirm your email first, then sign in.';
    if (text.contains('already registered') || text.contains('already been registered')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (text.contains('rate limit') || error.statusCode == '429') {
      return 'Too many attempts. Wait a moment and try again.';
    }
    // Other messages from the server are written for people ("Password should be
    // at least 6 characters"), so show them as they are.
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}
