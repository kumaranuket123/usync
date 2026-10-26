import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthApiException, AuthException;
import 'package:usync/core/utils/auth_messages.dart';

void main() {
  test('no connection is explained as such', () {
    expect(friendlyAuthMessage(const SocketException('Failed host lookup')), contains('No connection'));
  });

  test('rate limiting is recognised by message or status', () {
    expect(friendlyAuthMessage(AuthApiException('Email rate limit exceeded', statusCode: '429')), contains('Too many'));
    expect(friendlyAuthMessage(AuthApiException('slow down', statusCode: '429')), contains('Too many'));
  });

  test('other server messages that are already readable are kept', () {
    expect(
      friendlyAuthMessage(const AuthException('Google did not return an ID token.')),
      'Google did not return an ID token.',
    );
  });

  test('anything unexpected gets a generic message, never the raw exception', () {
    final text = friendlyAuthMessage(StateError('boom'));
    expect(text, 'Something went wrong. Please try again.');
    expect(text, isNot(contains('boom')));
  });
}
