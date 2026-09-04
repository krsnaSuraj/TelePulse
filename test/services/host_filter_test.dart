import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/services/host_filter.dart';

void main() {
  group('IPv4 classification boundaries', () {
    final cases = <String, bool>{
      '0.0.0.0': true,
      '0.1.2.3': true,
      '9.255.255.255': false,
      '10.0.0.0': true,
      '10.1.2.3': true,
      '11.0.0.1': false,
      '100.63.255.255': false,
      '100.64.0.0': true,
      '100.127.255.255': true,
      '100.128.0.0': false,
      '126.1.1.1': false,
      '127.0.0.1': true,
      '127.255.255.254': true,
      '128.0.0.1': false,
      '169.253.1.1': false,
      '169.254.0.1': true,
      '172.15.255.255': false,
      '172.16.0.0': true,
      '172.31.255.255': true,
      '172.32.0.0': false,
      '192.167.1.1': false,
      '192.168.0.0': true,
      '192.168.99.99': true,
      '192.169.0.1': false,
      '192.0.2.1': true,
      '192.0.0.1': true,
      '192.0.3.1': true,
      '198.17.255.255': false,
      '198.18.0.0': true,
      '198.19.255.255': true,
      '198.20.0.0': false,
      '198.51.99.255': false,
      '198.51.100.0': true,
      '198.51.100.200': true,
      '198.51.101.0': false,
      '223.255.255.255': false,
      '203.0.112.255': false,
      '203.0.113.0': true,
      '203.0.113.77': true,
      '203.0.114.0': false,
      '224.0.0.1': true,
      '239.1.1.1': true,
      '240.0.0.1': true,
      '255.255.255.255': true,
      '8.8.8.8': false,
      '93.184.216.34': false,
    };

    cases.forEach((ip, expectedPrivate) {
      test('$ip -> ${expectedPrivate ? "blocked" : "allowed"}', () {
        final addr = InternetAddress(ip);
        expect(HostFilter.isPrivateOrReservedAddress(addr), expectedPrivate,
            reason: ip);
      });
    });
  });

  group('IPv6 classification', () {
    final cases = <String, bool>{
      '::': true,
      '::1': true,
      'fe80::1': true,
      'febf::ffff': true,
      'fec0::1': true,
      'fd12:3456:789a::1': true,
      'fe00::1': true,
      'ff02::1': true,
      '2001:db8::1': true,
      '2002:0a00:0001::1': true,
      '2001::1': true,
      '64:ff9b::0808:0808': true,
      '100::1': true,
      '2606:4700::1111': false,
      '::ffff:127.0.0.1': true,
      '::ffff:8.8.8.8': false,
      '::ffff:192.168.1.1': true,
    };

    cases.forEach((ip, expectedPrivate) {
      test('$ip -> ${expectedPrivate ? "blocked" : "allowed"}', () {
        final addr = InternetAddress(ip);
        expect(HostFilter.isPrivateOrReservedAddress(addr), expectedPrivate,
            reason: ip);
      });
    });
  });

  group('literal parsing', () {
    test('parses bracketed IPv6 literals', () {
      final parsed = HostFilter.tryParseLiteral('[::1]');
      expect(parsed, isNotNull);
      expect(HostFilter.isDisallowedLiteral('[::1]'), isTrue);
    });

    test('returns null for plain hostnames', () {
      expect(HostFilter.tryParseLiteral('example.com'), isNull);
      expect(HostFilter.isDisallowedLiteral('example.com'), isFalse);
    });

    test('blocks loopback and private literals directly', () {
      expect(HostFilter.isDisallowedLiteral('127.0.0.1'), isTrue);
      expect(HostFilter.isDisallowedLiteral('10.0.0.5'), isTrue);
      expect(HostFilter.isDisallowedLiteral('192.168.1.20'), isTrue);
      expect(HostFilter.isDisallowedLiteral('8.8.8.8'), isFalse);
    });
  });
}
