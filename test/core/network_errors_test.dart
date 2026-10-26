import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/utils/network_errors.dart';

class _Coded implements Exception {
  _Coded(this.code);
  final String code;
}

class ClientException implements Exception {
  @override
  String toString() => 'ClientException: x';
}

void main() {
  test('connection problems are network errors', () {
    expect(isNetworkError(const SocketException('Failed host lookup')), isTrue);
    expect(isNetworkError(TimeoutException('slow')), isTrue);
    expect(isNetworkError(ClientException()), isTrue);
    expect(isNetworkError(Exception('SocketException: Network is unreachable')), isTrue);
  });

  test('a gateway or server outage (5xx) is a network error', () {
    expect(isNetworkError(_Coded('502')), isTrue);
    expect(isNetworkError(_Coded('503')), isTrue);
  });

  test('rejections are not network errors', () {
    expect(isNetworkError(_Coded('23505')), isFalse); // duplicate key
    expect(isNetworkError(_Coded('42501')), isFalse); // permission denied
    expect(isNetworkError(_Coded('401')), isFalse);
    expect(isNetworkError(StateError('bug')), isFalse);
  });
}
