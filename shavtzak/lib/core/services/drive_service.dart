import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;

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

  /// Get a human-readable file size
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Result of a Drive folder creation
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

/// Result of listing files in a folder
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

/// Result of archive check operation
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

/// Event data for archive check
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

/// Service for interacting with Google Drive via Apps Script
class DriveService {
  static DriveService? _instance;

  /// Singleton instance
  static DriveService get instance {
    _instance ??= DriveService._();
    return _instance!;
  }

  DriveService._();

  // Configuration - set via initialize()
  String? _scriptUrl;
  String? _apiKey;
  bool _isInitialized = false;

  /// Initialize the service with Apps Script URL and API key
  void initialize({
    required String scriptUrl,
    required String apiKey,
  }) {
    _scriptUrl = scriptUrl;
    _apiKey = apiKey;
    _isInitialized = true;
    developer.log('DriveService initialized', name: 'DriveService');
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Make a POST request to the Apps Script
  /// Uses text/plain content type to avoid CORS preflight requests
  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    if (!_isInitialized) {
      throw Exception('DriveService not initialized. Call initialize() first.');
    }

    body['apiKey'] = _apiKey;

    try {
      // Use text/plain to avoid CORS preflight (OPTIONS request)
      // Apps Script will still receive the JSON in postData.contents
      final response = await http.post(
        Uri.parse(_scriptUrl!),
        headers: {'Content-Type': 'text/plain;charset=UTF-8'},
        body: jsonEncode(body),
      );

      developer.log(
        'DriveService._post: action=${body['action']}, status=${response.statusCode}',
        name: 'DriveService',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        // Try to parse error from response body
        try {
          final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
          return {
            'success': false,
            'error': errorBody['error'] ?? 'HTTP ${response.statusCode}',
          };
        } catch (_) {
          return {
            'success': false,
            'error': 'HTTP ${response.statusCode}: ${response.body}',
          };
        }
      }
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

  /// Create a folder for an event
  /// Returns the folder ID and link on success
  Future<CreateFolderResult> createFolder({
    required String eventName,
    required DateTime date,
    DateTime? endDate, // Optional end date for multi-day events
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
        folderId: result['folderId'] as String,
        folderLink: result['folderLink'] as String,
      );
    } else {
      return CreateFolderResult(
        success: false,
        error: result['error'] as String?,
      );
    }
  }

  /// Rename an event folder
  Future<bool> renameFolder({
    required String folderId,
    required String newName,
    required DateTime newDate,
    DateTime? newEndDate, // Optional end date for multi-day events
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

  /// Delete (trash) an event folder
  Future<bool> deleteFolder({required String folderId}) async {
    final result = await _post({
      'action': 'deleteFolder',
      'folderId': folderId,
    });

    return result['success'] == true;
  }

  /// List files in an event folder
  Future<ListFilesResult> listFiles({required String folderId}) async {
    final result = await _post({
      'action': 'listFiles',
      'folderId': folderId,
    });

    if (result['success'] == true) {
      final filesJson = result['files'] as List<dynamic>? ?? [];
      final files = filesJson
          .map((f) => DriveFile.fromJson(f as Map<String, dynamic>))
          .toList();

      return ListFilesResult(
        success: true,
        files: files,
        folderNotFound: result['folderNotFound'] == true,
      );
    } else {
      return ListFilesResult(
        success: false,
        error: result['error'] as String?,
      );
    }
  }

  /// Run archive check - move old event folders to archive
  /// Pass list of events with their folder IDs, end dates, and archive status
  /// Returns list of folder IDs that were archived
  Future<ArchiveCheckResult> archiveCheck({
    required List<ArchiveEventData> events,
  }) async {
    final result = await _post({
      'action': 'archiveCheck',
      'events': events.map((e) => e.toJson()).toList(),
    });

    if (result['success'] == true) {
      final archivedList = result['archived'] as List<dynamic>? ?? [];
      final archivedIds = archivedList
          .map((a) => (a as Map<String, dynamic>)['folderId'] as String)
          .toList();

      return ArchiveCheckResult(
        success: true,
        archivedFolderIds: archivedIds,
      );
    } else {
      return ArchiveCheckResult(
        success: false,
        error: result['error'] as String?,
      );
    }
  }
}
