import 'package:flutter_test/flutter_test.dart';
import 'package:web_scripts/models/proxy.dart';

void main() {
  group('WebProxy', () {
    test('reads what the backend sends, without the password', () {
      final proxy = WebProxy.fromJson({
        'id': 'prx_1',
        'scheme': 'http',
        'host': '203.0.113.24',
        'port': 6014,
        'username': 'user',
        'has_password': true,
        'status': 'alive',
        'latency_ms': 320,
        'exit_ip': '203.0.113.24',
        'country': 'Germany',
        'city': 'Frankfurt',
        'used_by': 2,
      });

      expect(proxy.address, '203.0.113.24:6014');
      expect(proxy.needsAuth, isTrue);
      expect(proxy.alive, isTrue);
      expect(proxy.place, 'Germany · Frankfurt');
      expect(proxy.usedBy, 2);
    });

    test('a proxy nobody checked is neither alive nor dead', () {
      final proxy =
          WebProxy.fromJson({'id': 'p', 'host': '1.2.3.4', 'port': 80});

      expect(proxy.status, 'unknown');
      expect(proxy.alive, isFalse);
      expect(proxy.dead, isFalse);
      expect(proxy.place, '');
    });

    test('the title falls back to the address', () {
      final bare =
          WebProxy.fromJson({'id': 'p', 'host': '1.2.3.4', 'port': 80});
      final named = WebProxy.fromJson(
          {'id': 'p', 'host': '1.2.3.4', 'port': 80, 'label': 'Webshare 1'});

      expect(bare.title, '1.2.3.4:80');
      expect(named.title, 'Webshare 1');
    });
  });

  group('ProxyBook', () {
    ProxyBook book() => ProxyBook.fromJson({
          'proxies': [
            {'id': 'a', 'host': '1.1.1.1', 'port': 1, 'status': 'alive'},
            {'id': 'b', 'host': '2.2.2.2', 'port': 2, 'status': 'dead'},
            {'id': 'c', 'host': '3.3.3.3', 'port': 3, 'enabled': false},
            {'id': 'd', 'host': '4.4.4.4', 'port': 4},
          ],
          'overview': {'total': 4, 'alive': 1, 'dead': 1, 'free': 3},
        });

    test('a run may use the ones that are enabled and not known dead', () {
      expect(book().usable.map((p) => p.id), ['a', 'd']);
    });

    test('finds a proxy by id, and copes with none', () {
      expect(book().byId('b')!.host, '2.2.2.2');
      expect(book().byId('nope'), isNull);
      expect(book().byId(''), isNull);
      expect(book().byId(null), isNull);
    });

    test('carries the overview the page shows', () {
      expect(book().total, 4);
      expect(book().alive, 1);
      expect(book().free, 3);
    });
  });
}
