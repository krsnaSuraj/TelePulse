import 'package:flutter_test/flutter_test.dart';
import 'package:telepulse/models/proxy_model.dart';
import 'package:telepulse/services/proxy_parser.dart';

const _hex32 = 'A1b2C3d4E5f6A7b8C9d0E1f2A3b4C5d6';

ProxyModel? one(String text, {String format = 'auto'}) {
  final list = many(text, format: format);
  return list.isEmpty ? null : list.first;
}

List<ProxyModel> many(String text, {String format = 'auto'}) =>
    ProxyParser.parse(text, sourceName: 'T', format: format);

void main() {
  group('tg:// link parsing', () {
    test('parses a well-formed tg://proxy link', () {
      final m = one(
          'tg://proxy?server=1.2.3.4&port=443&secret=ee$_hex32');
      expect(m, isNotNull);
      expect(m!.server, '1.2.3.4');
      expect(m.port, 443);
      expect(m.secret, 'ee$_hex32');
      expect(m.protocolType, ProxyProtocolType.fakeTls);
      expect(m.source, 'T');
    });

    test('is case-insensitive on scheme and params', () {
      final m = one(
          'TG://PROXY?SERVER=example.com&PORT=8080&SECRET=$_hex32');
      expect(m!.port, 8080);
    });

    test('decodes percent-encoded hostnames', () {
      final m = one(
          'tg://proxy?server=my%2Eproxy%2Eexample&port=443&secret=$_hex32');
      expect(m!.server, 'my.proxy.example');
    });

    test('rejects hosts that decode to invalid characters', () {
      expect(
          one('tg://proxy?server=my%20proxy.example&port=443&secret=$_hex32'),
          isNull);
    });

    test('rejects out-of-range ports', () {
      expect(
          one('tg://proxy?server=a.com&port=0&secret=$_hex32'), isNull);
      expect(
          one('tg://proxy?server=a.com&port=65536&secret=$_hex32'), isNull);
      expect(one('tg://proxy?server=a.com&port=&secret=$_hex32'), isNull);
    });

    test('rejects empty server or secret', () {
      expect(one('tg://proxy?server=&port=443&secret=$_hex32'), isNull);
      expect(one('tg://proxy?server=a.com&port=443&secret='), isNull);
    });

    test('rejects localhost and private-IP targets', () {
      expect(one('tg://proxy?server=localhost&port=443&secret=$_hex32'),
          isNull);
      expect(one('tg://proxy?server=192.168.1.1&port=443&secret=$_hex32'),
          isNull);
      expect(one('tg://proxy?server=10.0.0.2&port=443&secret=$_hex32'),
          isNull);
      expect(one('tg://proxy?server=127.0.0.1&port=443&secret=$_hex32'),
          isNull);
    });
  });

  group('t.me link parsing', () {
    test('parses https t.me links', () {
      final m = one(
          'https://t.me/proxy?server=5.6.7.8&port=8888&secret=$_hex32');
      expect(m!.port, 8888);
    });

    test('parses http variant too', () {
      final m = one(
          'http://t.me/proxy?server=5.6.7.8&port=8888&secret=$_hex32');
      expect(m, isNotNull);
    });
  });

  group('plain format parsing', () {
    test('accepts common separators', () {
      for (final sep in [' ', ',', ':', ';', '|']) {
        final m = one('1.2.3.4${sep}443$_hex32'.replaceFirst('443', '443$sep'));
        expect(m, isNotNull, reason: 'separator "$sep"');
        expect(m!.port, 443);
      }
    });

    test('requires hex-only secrets in plain format', () {
      expect(one('a.com 443 zz$_hex32'), isNull);
      expect(one('a.com 443 $_hex32'), isNotNull);
    });

    test('enforces secret length bounds', () {
      final short15 = 'a' * 15;
      final exact16 = 'a' * 16;
      final ok128 = 'b' * 128;
      final long129 = 'c' * 129;
      expect(one('a.com 443 $short15'), isNull);
      expect(one('a.com 443 $exact16'), isNotNull);
      expect(one('a.com 443 $ok128'), isNotNull);
      expect(one('a.com 443 $long129'), isNull);
    });

    test('rejects invalid IPv4 octet values', () {
      expect(one('300.1.1.1 443 $_hex32'), isNull);
      expect(one('1.2.3 443 $_hex32'), isNull);
    });

    test('rejects lines with fewer than three parts', () {
      expect(one('justhost 443'), isNull);
      expect(one('# a comment line'), isNull);
      expect(one(''), isNull);
    });
  });

  group('robustness', () {
    test('strips BOM before parsing', () {
      final list = many('\uFEFFtg://proxy?server=1.1.1.1&port=80&secret=$_hex32');
      expect(list, hasLength(1));
    });

    test('handles CRLF line endings', () {
      final list = many(
        'tg://proxy?server=1.1.1.1&port=80&secret=$_hex32\r\ntg://proxy?server=2.2.2.2&port=81&secret=dd$_hex32\r\n',
      );
      expect(list, hasLength(2));
    });

    test('one malformed percent-escape does not kill the rest of the file',
        () {
      final list = many([
        'tg://proxy?server=%ZZbroken&port=443&secret=$_hex32',
        'tg://proxy?server=9.9.9.9&port=443&secret=$_hex32',
      ].join('\n'));
      expect(list, hasLength(1));
      expect(list.first.server, '9.9.9.9');
    });

    test('skips comment and blank lines', () {
      final list = many([
        '# header',
        '',
        '   ',
        'tg://proxy?server=1.1.1.1&port=80&secret=$_hex32',
      ].join('\n'));
      expect(list, hasLength(1));
    });

    test('deduplicates identical entries within a file (O(n))', () {
      final line = 'tg://proxy?server=1.1.1.1&port=80&secret=$_hex32';
      final list = many([line, line, line].join('\n'));
      expect(list, hasLength(1));
    });
  });

  group('html fallback parsing', () {
    test('extracts links from HTML with entities', () {
      final html = '''
        <html><body>
          <a href="https://t.me/proxy?server=3.3.3.3&amp;port=443&amp;secret=$_hex32">p</a>
          <a href="tg://proxy?server=4.4.4.4&port=8080&secret=dd$_hex32">q</a>
        </body></html>
      ''';
      final list = many(html);
      expect(list.map((e) => e.server), containsAll(['3.3.3.3', '4.4.4.4']));
    });

    test('auto format falls back to HTML when no plain matches', () {
      final html = '<div>server=7.7.7.7&port=443&secret=$_hex32</div>';
      expect(many(html), hasLength(1));
      expect(many(html, format: 'html'), hasLength(1));
    });
  });

  group('custom URL validation', () {
    test('accepts https URLs on public hosts', () {
      expect(
        ProxyParser.isValidCustomSourceUrl(
            'https://example.com/list.txt'),
        isTrue,
      );
      expect(
        ProxyParser.isValidCustomSourceUrl(
            'https://raw.githubusercontent.com/u/r/main/p.txt'),
        isTrue,
      );
    });

    test('rejects insecure or invalid URLs', () {
      expect(
          ProxyParser.isValidCustomSourceUrl('http://example.com/l.txt'),
          isFalse);
      expect(ProxyParser.isValidCustomSourceUrl('ftp://x.com'), isFalse);
      expect(ProxyParser.isValidCustomSourceUrl('not a url'), isFalse);
      expect(ProxyParser.isValidCustomSourceUrl(''), isFalse);
    });

    test('rejects localhost and private hosts', () {
      expect(ProxyParser.isValidCustomSourceUrl('https://localhost/a'),
          isFalse);
      expect(ProxyParser.isValidCustomSourceUrl('https://127.0.0.1/a'),
          isFalse);
      expect(ProxyParser.isValidCustomSourceUrl('https://192.168.0.10/a'),
          isFalse);
      expect(ProxyParser.isValidCustomSourceUrl('https://10.9.8.7/a'),
          isFalse);
    });
  });
}
