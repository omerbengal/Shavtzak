import 'dart:developer' as developer;

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

  const CreateFolderResult({
    required this.success,
    this.folderId,
    this.folderLink,
    this.error,
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

class ArchiveCheckResult {
  final bool success;
  final List<String> archivedFolderIds;
  final String? error;

  const ArchiveCheckResult({
    required this.success,
    this.archivedFolderIds = const [],
    this.error,
  });
}

class ArchiveEventData {
  final String folderId;
  final DateTime endDate;
  final bool isArchived;

  const ArchiveEventData({
    required this.folderId,
    required this.endDate,
    required this.isArchived,
  });

  Map<String, dynamic> toJson() => {
        'folderId': folderId,
        'endDate': endDate.toIso8601String(),
        'isArchived': isArchived,
      };
}

/// Service for interacting with Google Drive via Cloud Functions.
class DriveService {
  static DriveService? _instance;

  static DriveService get instance {
    _instance ??= DriveService._();
    return _instance!;
  }

  DriveService._();

  final BackendApiService _backendApiService = BackendApiService();
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
        error: e,
      );
      return {
        'success': false,
        'error': e.message,
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

  Future<ArchiveCheckResult> archiveCheck({
    required List<ArchiveEventData> events,
  }) async {
    final result = await _post({
      'action': 'archiveCheck',
      'events': events.map((event) => event.toJson()).toList(),
    });

    if (result['success'] == true) {
      final archivedList = result['archived'] as List<dynamic>? ?? [];
      final archivedIds = archivedList
          .map((item) => (item as Map<String, dynamic>)['folderId'] as String)
          .toList();

      return ArchiveCheckResult(
        success: true,
        archivedFolderIds: archivedIds,
      );
    }

    return ArchiveCheckResult(
      success: false,
      error: result['error'] as String?,
    );
  }
}
