import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'backend_api_service.dart';

/// Represents a file in Google Drive
class DriveFile {
  final String id;
  final String name;
  final String mimeType;
  final int size;
  final DateTime modifiedDate;
  final String webViewLink;
  final String iconLink;

  const DriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.modifiedDate,
    required this.webViewLink,
    required this.iconLink,
  });

  factory DriveFile.fromJson(Map<String, dynamic> json) {
    return DriveFile(
      id: json['id'] as String,
      name: json['name'] as String,
      mimeType: json['mimeType'] as String,
      size: json['size'] as int,
      modifiedDate: DateTime.parse(json['modifiedDate'] as String),
      webViewLink: json['webViewLink'] as String,
      iconLink: json['iconLink'] as String,
    );
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class CreateFolderResult {
  final bool success;
  final String? folderId;
  final String? folderLink;
  final String? error;

  /// True when the failure was a network/connectivity issue (no server
  /// response) rather than a genuine backend error. Retryable.
  final bool isNetworkError;

  const CreateFolderResult({
    required this.success,
    this.folderId,
    this.folderLink,
    this.error,
    this.isNetworkError = false,
  });
}

class ListFilesResult {
  final bool success;
  final List<DriveFile> files;
  final bool folderNotFound;
  final String? error;

  const ListFilesResult({
    required this.success,
    this.files = const [],
    this.folderNotFound = false,
    this.error,
  });
}

/// Service for interacting with Google Drive via Cloud Functions.
class DriveService {
  static DriveService? _instance;

  static DriveService get instance {
    _instance ??= DriveService._();
    return _instance!;
  }

  DriveService._({BackendApiService? backendApiService})
      : _backendApiService = backendApiService ?? BackendApiService();

  /// Test-only constructor that injects a backend so error handling can be
  /// exercised without a live Firebase app.
  @visibleForTesting
  factory DriveService.forTesting({
    required BackendApiService backendApiService,
  }) =>
      DriveService._(backendApiService: backendApiService);

  final BackendApiService _backendApiService;
  bool _isInitialized = false;

  /// Initialize the backend-backed Drive service.
  void initialize() {
    _isInitialized = true;
    developer.log('DriveService initialized', name: 'DriveService');
  }

  bool get isInitialized => _isInitialized;

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    if (!_isInitialized) {
      throw Exception('DriveService not initialized. Call initialize() first.');
    }

    try {
      return await _backendApiService.post(
        'drive/action',
        body: body,
        requireAuth: true,
      );
    } on BackendApiException catch (e) {
      developer.log(
        'DriveService._post error: ${e.message}',
        name: 'DriveService',
        error: e.cause ?? e,
      );
      return {
        'success': false,
        'error': e.message,
        'isNetworkError': e.isNetworkError,
      };
    } catch (e) {
      developer.log(
        'DriveService._post error: $e',
        name: 'DriveService',
        error: e,
      );
      return {
        'success': false,
        'error': e.toString(),
        'isNetworkError': BackendApiService.isTransientError(e),
      };
    }
  }

  Future<CreateFolderResult> createFolder({
    required String eventName,
    required DateTime date,
    DateTime? endDate,
  }) async {
    final result = await _post({
      'action': 'createFolder',
      'name': eventName,
      'date': date.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
    });

    if (result['success'] == true) {
      return CreateFolderResult(
        success: true,
        folderId: result['folderId'] as String?,
        folderLink: result['folderLink'] as String?,
      );
    }

    return CreateFolderResult(
      success: false,
      error: result['error'] as String?,
      isNetworkError: result['isNetworkError'] == true,
    );
  }

  Future<bool> renameFolder({
    required String folderId,
    required String newName,
    required DateTime newDate,
    DateTime? newEndDate,
  }) async {
    final result = await _post({
      'action': 'renameFolder',
      'folderId': folderId,
      'name': newName,
      'date': newDate.toIso8601String(),
      'endDate': newEndDate?.toIso8601String(),
    });

    return result['success'] == true;
  }

  Future<bool> deleteFolder({required String folderId}) async {
    final result = await _post({
      'action': 'deleteFolder',
      'folderId': folderId,
    });

    return result['success'] == true;
  }

  Future<ListFilesResult> listFiles({required String folderId}) async {
    final result = await _post({
      'action': 'listFiles',
      'folderId': folderId,
    });

    if (result['success'] == true) {
      final filesJson = result['files'] as List<dynamic>? ?? [];
      final files = filesJson
          .map((file) => DriveFile.fromJson(file as Map<String, dynamic>))
          .toList();

      return ListFilesResult(
        success: true,
        files: files,
        folderNotFound: result['folderNotFound'] == true,
      );
    }

    return ListFilesResult(
      success: false,
      error: result['error'] as String?,
    );
  }

}
