import 'dart:developer' as developer;

import 'backend_api_service.dart';

class ExportResult {
  final bool success;
  final String? spreadsheetUrl;
  final String? error;

  const ExportResult({
    required this.success,
    this.spreadsheetUrl,
    this.error,
  });
}

/// Exports production data through backend Cloud Functions so the browser never
/// reads or forwards the Google Drive API key.
class ExportService {
  ExportService({BackendApiService? backendApiService})
      : _backendApiService = backendApiService ?? BackendApiService();

  final BackendApiService _backendApiService;

  Future<ExportResult> exportToSheets() async {
    return _runExport('full');
  }

  Future<ExportResult> exportAssignmentsOnly() async {
    return _runExport('assignments');
  }

  Future<ExportResult> _runExport(String type) async {
    try {
      final response = await _backendApiService.post(
        'drive/export',
        body: {'type': type},
        requireAuth: true,
      );

      if (response['success'] == true) {
        return ExportResult(
          success: true,
          spreadsheetUrl: response['spreadsheetUrl'] as String?,
        );
      }

      return ExportResult(
        success: false,
        error: response['error'] as String? ?? 'Unknown export error',
      );
    } on BackendApiException catch (e) {
      developer.log(
        'ExportService: Export failed: ${e.message}',
        name: 'Export',
        error: e,
      );
      return ExportResult(success: false, error: e.message);
    } catch (e) {
      developer.log('ExportService: Export failed: $e', name: 'Export', error: e);
      return ExportResult(success: false, error: e.toString());
    }
  }
}
