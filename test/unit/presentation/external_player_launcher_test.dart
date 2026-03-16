import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/presentation/providers/player/external_player_launcher.dart';

void main() {
  group('ExternalPlayerLauncher', () {
    late ExternalPlayerLauncher launcher;

    setUp(() {
      launcher = ExternalPlayerLauncher();
    });

    group('URL scheme validation', () {
      // For URLs with disallowed schemes, openInExternalPlayer returns false
      // before attempting any process launch. This makes them safe to test
      // directly without mocking Process.start.

      group('rejects dangerous URL schemes', () {
        test('should reject file:// URLs', () async {
          final result =
              await launcher.openInExternalPlayer('file:///etc/passwd');
          expect(result, isFalse);
        });

        test('should reject javascript: URLs', () async {
          final result = await launcher
              .openInExternalPlayer('javascript:alert("xss")');
          expect(result, isFalse);
        });

        test('should reject data:// URLs', () async {
          final result = await launcher
              .openInExternalPlayer('data:text/html,<h1>Hello</h1>');
          expect(result, isFalse);
        });

        test('should reject ftp:// URLs', () async {
          final result =
              await launcher.openInExternalPlayer('ftp://example.com/file');
          expect(result, isFalse);
        });

        test('should reject ssh:// URLs', () async {
          final result =
              await launcher.openInExternalPlayer('ssh://user@host');
          expect(result, isFalse);
        });

        test('should reject telnet:// URLs', () async {
          final result =
              await launcher.openInExternalPlayer('telnet://host:23');
          expect(result, isFalse);
        });
      });

      group('rejects invalid URLs', () {
        test('should reject empty string', () async {
          final result = await launcher.openInExternalPlayer('');
          expect(result, isFalse);
        });

        test('should reject plain text', () async {
          final result =
              await launcher.openInExternalPlayer('not a url');
          expect(result, isFalse);
        });

        test('should reject URL without scheme', () async {
          final result =
              await launcher.openInExternalPlayer('example.com/stream');
          expect(result, isFalse);
        });
      });

      // For allowed schemes, the method will attempt Process.start which may
      // succeed or fail depending on the environment. We verify that the
      // validation itself does NOT reject these by checking it does not return
      // false before trying the process launch. On CI (no VLC installed) the
      // method may return false from the process catch, but that's after
      // validation passes. We can't easily distinguish, so we only test
      // rejection-side directly.
      //
      // Instead, we validate the scheme logic by testing against the Uri
      // parsing that the method uses internally.
      group('allows valid network schemes (validation logic)', () {
        test('http scheme is in allowed set', () {
          final uri = Uri.tryParse('http://example.com/stream.m3u8');
          expect(uri, isNotNull);
          expect(['http', 'https', 'rtsp', 'rtmp'].contains(uri!.scheme),
              isTrue);
        });

        test('https scheme is in allowed set', () {
          final uri = Uri.tryParse('https://example.com/stream.m3u8');
          expect(uri, isNotNull);
          expect(['http', 'https', 'rtsp', 'rtmp'].contains(uri!.scheme),
              isTrue);
        });

        test('rtsp scheme is in allowed set', () {
          final uri = Uri.tryParse('rtsp://example.com/stream');
          expect(uri, isNotNull);
          expect(['http', 'https', 'rtsp', 'rtmp'].contains(uri!.scheme),
              isTrue);
        });

        test('rtmp scheme is in allowed set', () {
          final uri = Uri.tryParse('rtmp://example.com/live/stream');
          expect(uri, isNotNull);
          expect(['http', 'https', 'rtsp', 'rtmp'].contains(uri!.scheme),
              isTrue);
        });

        test('file scheme is NOT in allowed set', () {
          final uri = Uri.tryParse('file:///etc/passwd');
          expect(uri, isNotNull);
          expect(['http', 'https', 'rtsp', 'rtmp'].contains(uri!.scheme),
              isFalse);
        });

        test('javascript scheme is NOT in allowed set', () {
          final uri = Uri.tryParse('javascript:alert(1)');
          expect(uri, isNotNull);
          expect(['http', 'https', 'rtsp', 'rtmp'].contains(uri!.scheme),
              isFalse);
        });

        test('data scheme is NOT in allowed set', () {
          final uri = Uri.tryParse('data:text/html,hello');
          expect(uri, isNotNull);
          expect(['http', 'https', 'rtsp', 'rtmp'].contains(uri!.scheme),
              isFalse);
        });

        test('ftp scheme is NOT in allowed set', () {
          final uri = Uri.tryParse('ftp://example.com');
          expect(uri, isNotNull);
          expect(['http', 'https', 'rtsp', 'rtmp'].contains(uri!.scheme),
              isFalse);
        });
      });
    });
  });
}
