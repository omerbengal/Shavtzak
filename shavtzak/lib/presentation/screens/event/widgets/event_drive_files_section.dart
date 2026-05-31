import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/debug/logger.dart';
import '../../../../core/services/drive_service.dart';
import '../../../../core/utils/web_url_launcher.dart';
import '../../../../data/repositories/event_repository.dart';

/// Widget to display Drive files for an event
class EventDriveFilesSection extends StatefulWidget {
  final String eventId;
  final String? driveFolderId;
  final String? driveFolderLink;
  final String eventName;
  final bool showHeader;
  final bool scrollableFilesOnly;
  final double filesListHeight;

  const EventDriveFilesSection({
    super.key,
    required this.eventId,
    this.driveFolderId,
    this.driveFolderLink,
    required this.eventName,
    this.showHeader = true,
    this.scrollableFilesOnly = false,
    this.filesListHeight = 320,
  });

  @override
  State<EventDriveFilesSection> createState() => _EventDriveFilesSectionState();
}

class _EventDriveFilesSectionState extends State<EventDriveFilesSection> {
  List<DriveFile> _files = [];
  bool _isLoading = false;
  bool _isWaitingForFolder = false;
  bool _isRecreatingFolder = false;
  String? _error;
  Timer? _pollTimer;

  // Current folder info (may be updated via polling)
  String? _currentFolderId;
  String? _currentFolderLink;

  @override
  void initState() {
    super.initState();
    _currentFolderId = widget.driveFolderId;
    _currentFolderLink = widget.driveFolderLink;

    if (_currentFolderId != null && _currentFolderId!.isNotEmpty) {
      _loadFiles();
    } else {
      // No folder yet - start polling for folder creation
      _startPollingForFolder();
    }
  }

  @override
  void didUpdateWidget(EventDriveFilesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update if folder ID changed from widget
    if (oldWidget.driveFolderId != widget.driveFolderId) {
      _currentFolderId = widget.driveFolderId;
      _currentFolderLink = widget.driveFolderLink;

      if (_currentFolderId != null && _currentFolderId!.isNotEmpty) {
        _stopPolling();
        _loadFiles();
      }
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Start polling to check if the Drive folder has been created
  void _startPollingForFolder() {
    setState(() {
      _isWaitingForFolder = true;
    });

    // Poll every 2 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _checkForFolder();
    });
  }

  /// Check if the event now has a Drive folder
  Future<void> _checkForFolder() async {
    if (!mounted) return;

    try {
      final eventRepository = context.read<EventRepository>();
      final event = await eventRepository.getEventById(widget.eventId);

      if (event != null && event.hasDriveFolder) {
        // Folder was created!
        _stopPolling();
        if (mounted) {
          setState(() {
            _isWaitingForFolder = false;
            _currentFolderId = event.driveFolderId;
            _currentFolderLink = event.driveFolderLink;
          });
          _loadFiles();
        }
      }
    } catch (e) {
      // Silently ignore polling errors - we'll try again
    }
  }

  Future<void> _loadFiles() async {
    if (!DriveService.instance.isInitialized || _currentFolderId == null) {
      return;
    }
    if (_isRecreatingFolder) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result =
          await DriveService.instance.listFiles(folderId: _currentFolderId!);

      if (result.success && result.folderNotFound) {
        await _recreateFolder();
        return;
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (result.success) {
            _files = result.files;
          } else {
            _error = result.error ?? 'Failed to load files';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Recreate folder when the old Drive folder was deleted manually
  Future<void> _recreateFolder() async {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _isRecreatingFolder = true;
      _error = null;
      _files = [];
    });

    try {
      final eventRepository = context.read<EventRepository>();
      final event = await eventRepository.getEventById(widget.eventId);

      if (event == null) {
        if (mounted) {
          setState(() {
            _isRecreatingFolder = false;
            _error = 'האירוע לא נמצא';
          });
        }
        return;
      }

      final createResult = await DriveService.instance.createFolder(
        eventName: event.name,
        date: event.startDate,
        endDate: event.endDate,
      );

      if (!createResult.success || createResult.folderId == null) {
        if (mounted) {
          setState(() {
            _isRecreatingFolder = false;
            _error = createResult.error ?? 'שגיאה ביצירת תיקייה מחדש';
          });
        }
        return;
      }

      final updatedEvent = event.copyWith(
        driveFolderId: createResult.folderId,
        driveFolderLink: createResult.folderLink,
      );
      await eventRepository.updateEvent(updatedEvent);

      if (mounted) {
        setState(() {
          _currentFolderId = createResult.folderId;
          _currentFolderLink = createResult.folderLink;
          _isRecreatingFolder = false;
        });
      }

      await _loadFiles();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecreatingFolder = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final success = await launchUrlWithAutoClose(url);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('לא ניתן לפתוח את הקישור'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> filesAndStatusWidgets = [
      // Waiting for folder creation state
      if (_isWaitingForFolder)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            border: Border.all(color: Colors.blue.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.blue.shade600,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'תיקיית דרייב נוצרת...',
                style: TextStyle(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.w500,
                ),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
        ),

      // Recreating folder indicator
      if (!_isWaitingForFolder && _isRecreatingFolder)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            border: Border.all(color: Colors.blue.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.blue.shade600,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'יוצר תיקייה מחדש...',
                style: TextStyle(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.w500,
                ),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
        ),

      // Loading files indicator
      if (!_isWaitingForFolder && !_isRecreatingFolder && _isLoading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        ),

      // Error message
      if (!_isWaitingForFolder && !_isRecreatingFolder && _error != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            border: Border.all(color: Colors.red.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'שגיאה בטעינת הקבצים: $_error',
                  style: TextStyle(color: Colors.red.shade800),
                  textDirection: TextDirection.rtl,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () { Logger.action('tap:refreshFiles', {'eventId': widget.eventId}); _loadFiles(); },
                color: Colors.red.shade600,
              ),
            ],
          ),
        ),

      // Files list
      if (!_isWaitingForFolder &&
          !_isRecreatingFolder &&
          !_isLoading &&
          _error == null) ...[
        if (_files.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'אין קבצים בתיקייה',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
            ),
          )
        else
          ..._files.map((file) => _FileTile(file: file)),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
        ],

        // Section title
        Row(
          children: [
            if (widget.showHeader) ...[
              const Icon(Icons.folder_open, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                'קבצים בגוגל דרייב',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
            ],
            // Only show refresh and open buttons when folder exists
            if (_currentFolderId != null && _currentFolderId!.isNotEmpty) ...[
              // Manual refresh button
              IconButton(
                onPressed: _isLoading ? null : () { Logger.action('tap:refreshFiles', {'eventId': widget.eventId}); _loadFiles(); },
                icon: const Icon(Icons.refresh),
                tooltip: 'רענן קבצים',
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: _isLoading ? Colors.grey : Colors.blue,
              ),
              // Link to folder
              if (_currentFolderLink != null)
                TextButton.icon(
                  onPressed: () { Logger.action('tap:openDriveFolder', {'eventId': widget.eventId}); _launchUrl(_currentFolderLink!); },
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('פתח תיקייה'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
            ],
          ],
        ),

        const SizedBox(height: 8),

        if (widget.scrollableFilesOnly)
          SizedBox(
            height: widget.filesListHeight,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: filesAndStatusWidgets,
              ),
            ),
          )
        else
          ...filesAndStatusWidgets,

        if (widget.showHeader)
          const SizedBox(
              height: 16), // Add space before comments field in admin modal
      ],
    );
  }
}

/// Widget for a single file in the list
class _FileTile extends StatelessWidget {
  final DriveFile file;

  const _FileTile({required this.file});

  Future<void> _launchUrl(BuildContext context, String url) async {
    final success = await launchUrlWithAutoClose(url);
    if (!context.mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('לא ניתן לפתוח את הקובץ'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getFileTypeDisplayName(String mimeType) {
    if (mimeType.startsWith('image/')) return 'תמונה';
    if (mimeType.startsWith('video/')) return 'סרטון';
    if (mimeType.startsWith('audio/')) return 'אודיו';
    if (mimeType.contains('pdf')) return 'מסמך PDF';
    if (mimeType.contains('document')) return 'מסמך';
    if (mimeType.contains('sheet')) return 'גיליון';
    if (mimeType.contains('presentation')) return 'מצגת';
    if (mimeType.contains('folder')) return 'תיקייה';
    return 'קובץ';
  }

  IconData _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.videocam;
    if (mimeType.startsWith('audio/')) return Icons.audiotrack;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('document')) return Icons.description;
    if (mimeType.contains('sheet')) return Icons.table_chart;
    if (mimeType.contains('presentation')) return Icons.slideshow;
    if (mimeType.contains('folder')) return Icons.folder;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.grey.shade200,
        child: Icon(
          _getFileIcon(file.mimeType),
          color: Colors.grey.shade700,
          size: 20,
        ),
      ),
      title: Text(
        file.name,
        textDirection: TextDirection.rtl,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${_getFileTypeDisplayName(file.mimeType)} • ${file.formattedSize}',
        textDirection: TextDirection.rtl,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 12,
        ),
      ),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: () { Logger.action('tap:openDriveFile', {'fileId': file.id, 'mimeType': file.mimeType}); _launchUrl(context, file.webViewLink); },
    );
  }
}
