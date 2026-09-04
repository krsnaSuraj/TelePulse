import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/core/app_errors.dart';

void main() {
  group('friendlyErrorOf', () {
    test('SocketException maps to a no-connection message', () {
      final e = friendlyErrorOf(
          const SocketException('Failed host lookup'));
      expect(e.title, 'No connection');
      expect(e.message, contains('internet'));
    });

    test('timeouts map to slowness copy', () {
      final e = friendlyErrorOf(TimeoutException('x', Duration.zero));
      expect(e.title, 'Taking too long');
    });

    test('Dio timeouts map to source-slowness copy', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.transformTimeout,
      ]) {
        final e = friendlyErrorOf(DioException(
          requestOptions: RequestOptions(),
          type: type,
        ));
        expect(e.title, 'Sources are slow', reason: '$type');
      }
    });

    test('Dio connection errors explain blocked lists', () {
      final e = friendlyErrorOf(DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
      ));
      expect(e.title, 'Sources unreachable');
      expect(e.message, contains('blocked'));
    });

    test('bad certificates refuse with a safety message', () {
      final e = friendlyErrorOf(DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.badCertificate,
      ));
      expect(e.message, contains('safe'));
    });

    test('unknown errors degrade to a generic retry message', () {
      final e = friendlyErrorOf(StateError('weird'));
      expect(e.title, 'Something went wrong');
      expect(snackbarFor(StateError('x')), e.message);
    });

    test('handshake failures explain interference', () {
      final e = friendlyErrorOf(
          const HandshakeException('Connection terminated'));
      expect(e.title, 'Secure connection failed');
    });

    test('bad responses blame the source', () {
      final e = friendlyErrorOf(DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.badResponse,
      ));
      expect(e.title, 'Source returned an error');
    });

    test('cancelled requests say so plainly', () {
      final e = friendlyErrorOf(DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.cancel,
      ));
      expect(e.title, 'Request cancelled');
    });

    test('unknown Dio errors map to unreachable', () {
      final e = friendlyErrorOf(DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.unknown,
      ));
      expect(e.title, 'Sources unreachable');
    });

    test('HTTP errors map to a network problem', () {
      final e = friendlyErrorOf(const HttpException('closed'));
      expect(e.title, 'Network problem');
    });
  });
}
