import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shavtzak/core/services/backend_api_service.dart';

void main() {
  group('BackendApiService.isTransientError', () {
    test('network ClientException is transient', () {
      expect(
        BackendApiService.isTransientError(
          http.ClientException('Load failed', Uri.parse('https://example.com')),
        ),
        isTrue,
      );
    });

    test('TimeoutException is transient', () {
      expect(
        BackendApiService.isTransientError(TimeoutException('slow')),
        isTrue,
      );
    });

    test('a non-network error is NOT transient', () {
      expect(BackendApiService.isTransientError(StateError('boom')), isFalse);
    });
  });

  group('BackendApiService.retryTransient', () {
    test('returns the value on first success without retrying', () async {
      var calls = 0;
      final result = await BackendApiService.retryTransient(
        () async {
          calls++;
          return 'ok';
        },
        maxAttempts: 3,
        initialBackoff: Duration.zero,
      );

      expect(result, 'ok');
      expect(calls, 1);
    });

    test('retries a transient failure then succeeds', () async {
      var calls = 0;
      final result = await BackendApiService.retryTransient(
        () async {
          calls++;
          if (calls < 3) {
            throw http.ClientException('Load failed');
          }
          return 'recovered';
        },
        maxAttempts: 3,
        initialBackoff: Duration.zero,
      );

      expect(result, 'recovered');
      expect(calls, 3);
    });

    test('rethrows after exhausting attempts on persistent transient failure',
        () async {
      var calls = 0;
      await expectLater(
        BackendApiService.retryTransient<String>(
          () async {
            calls++;
            throw http.ClientException('Load failed');
          },
          maxAttempts: 3,
          initialBackoff: Duration.zero,
        ),
        throwsA(isA<http.ClientException>()),
      );
      expect(calls, 3);
    });

    test('does NOT retry a non-transient error', () async {
      var calls = 0;
      await expectLater(
        BackendApiService.retryTransient<String>(
          () async {
            calls++;
            throw StateError('boom');
          },
          maxAttempts: 3,
          initialBackoff: Duration.zero,
        ),
        throwsA(isA<StateError>()),
      );
      expect(calls, 1);
    });

    test('backoff grows exponentially between attempts', () async {
      final delays = <Duration>[];
      await expectLater(
        BackendApiService.retryTransient<String>(
          () async {
            throw http.ClientException('Load failed');
          },
          maxAttempts: 3,
          initialBackoff: const Duration(milliseconds: 100),
          sleep: (d) async => delays.add(d),
        ),
        throwsA(isA<http.ClientException>()),
      );

      // 3 attempts => 2 backoff waits, doubling each time.
      expect(delays, [
        const Duration(milliseconds: 100),
        const Duration(milliseconds: 200),
      ]);
    });
  });

  group('BackendApiService.post network handling', () {
    setUp(() {
      // Force a defined platform so DefaultFirebaseOptions.currentPlatform
      // resolves on any test host (Linux CI would otherwise throw).
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('retries transient failures then returns the decoded body', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls < 2) {
          throw http.ClientException('Load failed', request.url);
        }
        return http.Response('{"success": true}', 200);
      });
      final service = BackendApiService(
        client: client,
        maxAttempts: 3,
        initialBackoff: Duration.zero,
      );

      final result = await service.post('drive/action');

      expect(result['success'], true);
      expect(calls, 2);
    });

    test(
        'persistent network failure throws BackendApiException flagged as network',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        throw http.ClientException('Load failed', request.url);
      });
      final service = BackendApiService(
        client: client,
        maxAttempts: 2,
        initialBackoff: Duration.zero,
      );

      await expectLater(
        service.post('drive/action'),
        throwsA(
          isA<BackendApiException>()
              .having((e) => e.isNetworkError, 'isNetworkError', true),
        ),
      );
      expect(calls, 2);
    });
  });
}
