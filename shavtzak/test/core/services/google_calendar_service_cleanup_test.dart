import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/google_calendar_service.dart';

void main() {
  group('AppEventGuestCleanupStatus', () {
    test('parses backend progress and counts', () {
      final result = AppEventGuestCleanupStatus.fromJson(
        const {
          'jobId': 'job-1',
          'mode': 'all',
          'status': 'running',
          'totalPartCount': 8,
          'processedPartCount': '3',
          'changedPartCount': 2,
          'skippedPartCount': 1,
          'failedPartCount': 0,
        },
        fallbackMode: AppEventGuestCleanupMode.omer,
      );

      expect(result.jobId, 'job-1');
      expect(result.mode, AppEventGuestCleanupMode.all);
      expect(result.processedPartCount, 3);
      expect(result.isTerminal, isFalse);
    });

    test('uses request context when the start response is minimal', () {
      final result = AppEventGuestCleanupStatus.fromJson(
        const {'status': 'completed'},
        fallbackMode: AppEventGuestCleanupMode.omer,
        fallbackJobId: 'job-2',
      );

      expect(result.jobId, 'job-2');
      expect(result.mode, AppEventGuestCleanupMode.omer);
      expect(result.isTerminal, isTrue);
      expect(result.isFailed, isFalse);
    });

    test('exposes terminal backend failures', () {
      final result = AppEventGuestCleanupStatus.fromJson(
        const {
          'jobId': 'job-3',
          'mode': 'omer',
          'status': 'failed',
          'lastError': 'quota exceeded',
        },
        fallbackMode: AppEventGuestCleanupMode.all,
      );

      expect(result.isTerminal, isTrue);
      expect(result.isFailed, isTrue);
      expect(result.lastError, 'quota exceeded');
    });

    test('stops polling when OAuth must be reconnected', () {
      final result = AppEventGuestCleanupStatus.fromJson(
        const {
          'jobId': 'job-4',
          'mode': 'all',
          'status': 'auth-blocked',
          'lastError': 'Not authenticated',
        },
        fallbackMode: AppEventGuestCleanupMode.omer,
      );

      expect(result.isTerminal, isTrue);
      expect(result.isFailed, isTrue);
    });
  });
}
