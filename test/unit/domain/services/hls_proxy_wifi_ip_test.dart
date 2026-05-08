import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/domain/services/hls_proxy_service.dart';

NetworkInterfaceView _iface(String name, List<String> addrs) =>
    (name: name, ipv4Addresses: addrs);

void main() {
  group('pickWifiInterface', () {
    test('Samsung-style list picks wlan0 over rmnet/dummy', () {
      // Mirrors the failure mode in tregula501/flowtv#3: cellular and
      // virtual interfaces enumerate before the actual Wi-Fi adapter.
      final result = pickWifiInterface([
        _iface('rmnet_data0', ['10.169.0.5']),
        _iface('dummy0', []),
        _iface('ifb0', []),
        _iface('wlan0', ['192.168.1.42']),
      ]);

      expect(result.chosen, isNotNull);
      expect(result.chosen!.name, 'wlan0');
      expect(result.chosen!.ipv4Addresses.first, '192.168.1.42');
    });

    test('plain list with only wlan0 picks wlan0', () {
      final result = pickWifiInterface([
        _iface('wlan0', ['192.168.1.42']),
      ]);

      expect(result.chosen, isNotNull);
      expect(result.chosen!.name, 'wlan0');
    });

    test('ethernet-only list picks eth0', () {
      final result = pickWifiInterface([
        _iface('eth0', ['192.168.0.50']),
      ]);

      expect(result.chosen, isNotNull);
      expect(result.chosen!.name, 'eth0');
    });

    test('RFC1918 tiebreaker chooses the private-addressed interface', () {
      // Both interfaces are positive-named (en*), but only en1 has a
      // private address — RFC1918 must outrank a public one.
      final result = pickWifiInterface([
        _iface('en0', ['8.8.8.8']),
        _iface('en1', ['192.168.1.10']),
      ]);

      expect(result.chosen, isNotNull);
      expect(result.chosen!.name, 'en1');
      expect(result.chosen!.ipv4Addresses.first, '192.168.1.10');
    });

    test('empty list returns null', () {
      final result = pickWifiInterface([]);
      expect(result.chosen, isNull);
      expect(result.scored, isEmpty);
    });

    test('all-virtual list returns null (forces caller to fall back)', () {
      // Every interface is name-rejected (rmnet/dummy/tun/ifb/bond/ppp).
      // Even though they hold RFC1918 addresses, the rejection happens
      // before scoring, so nothing scores > 0.
      final result = pickWifiInterface([
        _iface('rmnet0', ['10.0.0.5']),
        _iface('dummy0', ['10.1.2.3']),
        _iface('tun0', ['10.8.0.4']),
      ]);

      expect(result.chosen, isNull);
      // Each entry should be flagged rejected for diagnostics.
      expect(result.scored.every((s) => s.rejected), isTrue);
    });

    test('rejects bond/tun/ppp/ifb name prefixes', () {
      final result = pickWifiInterface([
        _iface('bond0', ['192.168.5.1']),
        _iface('tun0', ['192.168.5.2']),
        _iface('ppp0', ['192.168.5.3']),
        _iface('ifb0', ['192.168.5.4']),
      ]);

      expect(result.chosen, isNull);
    });

    test('positive name without RFC1918 still beats a non-positive name', () {
      // wlan-prefixed gets +100 even with a public IP; the unrelated
      // interface scores 0 and is skipped.
      final result = pickWifiInterface([
        _iface('something-weird', ['203.0.113.5']),
        _iface('wlan0', ['8.8.4.4']),
      ]);

      expect(result.chosen, isNotNull);
      expect(result.chosen!.name, 'wlan0');
    });

    test('matching is case-insensitive', () {
      final result = pickWifiInterface([
        _iface('WLAN0', ['192.168.1.99']),
      ]);

      expect(result.chosen, isNotNull);
      expect(result.chosen!.name, 'WLAN0');
    });

    test('lexicographic tiebreaker after equal score and both private', () {
      // Both interfaces score 150 (positive name + RFC1918). With score
      // and RFC1918 status equal, lexicographic name order wins.
      final result = pickWifiInterface([
        _iface('wlan1', ['192.168.1.20']),
        _iface('wlan0', ['192.168.1.10']),
      ]);

      expect(result.chosen, isNotNull);
      expect(result.chosen!.name, 'wlan0');
    });

    test('172.16/12 RFC1918 boundary is respected', () {
      // 172.16.x.x is private, 172.32.x.x is public.
      final r1 = pickWifiInterface([
        _iface('zzz', ['172.16.0.1']), // not a positive name → score 50
      ]);
      expect(r1.chosen, isNotNull);
      expect(r1.chosen!.name, 'zzz');

      final r2 = pickWifiInterface([
        _iface('zzz', ['172.32.0.1']), // not private, not positive → score 0
      ]);
      expect(r2.chosen, isNull);
    });

    test('scored list is populated for every interface (diagnostics)', () {
      final result = pickWifiInterface([
        _iface('rmnet_data0', ['10.169.0.5']),
        _iface('wlan0', ['192.168.1.42']),
      ]);

      expect(result.scored, hasLength(2));
      final rmnet = result.scored.firstWhere((s) => s.iface.name == 'rmnet_data0');
      expect(rmnet.rejected, isTrue);
      final wlan = result.scored.firstWhere((s) => s.iface.name == 'wlan0');
      expect(wlan.rejected, isFalse);
      expect(wlan.score, 150); // +100 positive name, +50 RFC1918
    });
  });
}
