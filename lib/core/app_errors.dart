import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

class FriendlyError {
  final String title;
  final String message;

  const FriendlyError(this.title, this.message);
}

FriendlyError friendlyErrorOf(Object error) {
  if (error is SocketException) {
    return const FriendlyError(
      'No connection',
      'Your device could not reach the proxy sources. Check your internet and pull down to retry.',
    );
  }
  if (error is TimeoutException) {
    return const FriendlyError(
      'Taking too long',
      'The proxy sources are responding very slowly. Try again in a bit.',
    );
  }
  if (error is HandshakeException) {
    return const FriendlyError(
      'Secure connection failed',
      'Something on this network is interfering with secure connections. A proxy may be exactly what you need — retry once you have one.',
    );
  }
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.transformTimeout:
        return const FriendlyError(
          'Sources are slow',
          'The proxy lists took too long to respond. Pull down to retry.',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return const FriendlyError(
          'Sources unreachable',
          'TelePulse could not reach any proxy list. If Telegram is blocked here, the lists may be blocked too — try again later.',
        );
      case DioExceptionType.badResponse:
        return const FriendlyError(
          'Source returned an error',
          'One of the proxy lists answered with an error. TelePulse will keep using the others.',
        );
      case DioExceptionType.cancel:
        return const FriendlyError(
          'Request cancelled',
          'The request was cancelled. Pull down to retry.',
        );
      case DioExceptionType.badCertificate:
        return const FriendlyError(
          'Certificate problem',
          'A source presented an unexpected certificate. TelePulse refused the connection to keep you safe.',
        );
    }
  }
  if (error is HttpException) {
    return const FriendlyError(
      'Network problem',
      'A network error interrupted the scan. Pull down to retry.',
    );
  }
  return const FriendlyError(
    'Something went wrong',
    'TelePulse could not complete the last action. Pull down to retry.',
  );
}

String snackbarFor(Object error) => friendlyErrorOf(error).message;
