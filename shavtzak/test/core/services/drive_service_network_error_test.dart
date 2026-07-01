import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/backend_api_service.dart';
import 'package:shavtzak/core/services/drive_service.dart';

/// Fake backend that lets a test drive exactly what `post` returns/throws,
/// so DriveService's error classification can be tested without Firebase/auth.
class _FakeBackend extends BackendApiService {
  _FakeBackend(this._responder);

  final Future<Map<String, dynamic>> Function(String path) _responder;

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool requireAuth = false,
  }) =>
      _responder(path);
}

void main() {
  group('DriveService.createFolder error classification', () {
    test('flags a network BackendApiException as a network error', () async {
      final drive = DriveService.forTesting(
        backendApiService: _FakeBackend(
          (_) async => throw const BackendApiException(
            'net down',
            isNetworkError: true,
          ),
        ),
      )..initialize();

      final result = await drive.createFolder(
        eventName: 'אירוע',
        date: DateTime(2026, 1, 1),
      );

      expect(result.success, isFalse);
      expect(result.isNetworkError, isTrue);
    });

    test('a real backend failure is NOT a network error', () async {
      final drive = DriveService.forTesting(
        backendApiService: _FakeBackend(
          (_) async => throw const BackendApiException(
            'permission denied',
            statusCode: 403,
          ),
        ),
      )..initialize();

      final result = await drive.createFolder(
        eventName: 'אירוע',
        date: DateTime(2026, 1, 1),
      );

      expect(result.success, isFalse);
      expect(result.isNetworkError, isFalse);
    });

    test('a successful create is not flagged as a network error', () async {
      final drive = DriveService.forTesting(
        backendApiService: _FakeBackend(
          (_) async => {
            'success': true,
            'folderId': 'folder-1',
            'folderLink': 'https://drive/folder-1',
          },
        ),
      )..initialize();

      final result = await drive.createFolder(
        eventName: 'אירוע',
        date: DateTime(2026, 1, 1),
      );

      expect(result.success, isTrue);
      expect(result.isNetworkError, isFalse);
      expect(result.folderId, 'folder-1');
    });
  });
}
