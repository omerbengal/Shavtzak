import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/services/drive_service.dart';

/// Widget to display Drive files for an event
class EventDriveFilesSection extends StatefulWidget {
  final String? driveFolderId;
  final String? driveFolderLink;
  final String eventName;

  const EventDriveFilesSection({
    super.key,
    this.driveFolderId,
    this.driveFolderLink,
    required this.eventName,
  });

  @override
  State<EventDriveFilesSection> createState() => _EventDriveFilesSectionState();
}

class _EventDriveFilesSectionState extends State<EventDriveFilesSection> {
  List<DriveFile> _files = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.driveFolderId != null && widget.driveFolderId!.isNotEmpty) {
      _loadFiles();
    }
  }

  @override
  void didUpdateWidget(EventDriveFilesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload files if the folder ID changes
    if (oldWidget.driveFolderId != widget.driveFolderId &&
        widget.driveFolderId != null &&
        widget.driveFolderId!.isNotEmpty) {
      _loadFiles();
    }
  }

  Future<void> _loadFiles() async {
    if (!DriveService.instance.isInitialized || widget.driveFolderId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await DriveService.instance.listFiles(folderId: widget.driveFolderId!);

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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
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
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything if there's no folder
    if (widget.driveFolderId == null || widget.driveFolderId!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),

        // Section title
        Row(
          children: [
            const Icon(Icons.folder_open, color: Colors.blue),
            const SizedBox(width: 8),
            const Text(
              'קבצים בגוגל דרייב',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            // Manual refresh button
            IconButton(
              onPressed: _isLoading ? null : _loadFiles,
              icon: const Icon(Icons.refresh),
              tooltip: 'רענן קבצים',
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: _isLoading ? Colors.grey : Colors.blue,
            ),
            // Link to folder
            if (widget.driveFolderLink != null)
              TextButton.icon(
                onPressed: () => _launchUrl(widget.driveFolderLink!),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('פתח תיקייה'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue,
                ),
              ),
          ],
        ),

        const SizedBox(height: 8),

        // Loading indicator
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),

        // Error message
        if (_error != null)
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
                  onPressed: _loadFiles,
                  color: Colors.red.shade600,
                ),
              ],
            ),
          ),

        // Files list
        if (!_isLoading && _error == null) ...[
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

        const SizedBox(height: 16), // Add space before comments field
      ],
    );
  }
}

/// Widget for a single file in the list
class _FileTile extends StatelessWidget {
  final DriveFile file;

  const _FileTile({required this.file});

  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
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
      onTap: () => _launchUrl(context, file.webViewLink),
    );
  }
}