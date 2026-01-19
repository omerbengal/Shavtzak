import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'json_tree_view.dart';

/// An expandable card that displays a Firestore document.
/// Shows document ID and primary field when collapsed, full JSON when expanded.
class DocumentCard extends StatelessWidget {
  final String documentId;
  final Map<String, dynamic> data;
  final bool isExpanded;
  final VoidCallback onToggle;

  const DocumentCard({
    super.key,
    required this.documentId,
    required this.data,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: isExpanded ? 3 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header (always visible)
          _buildHeader(context),
          // Expanded content
          if (isExpanded) _buildExpandedContent(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final primaryField = _getPrimaryFieldValue();

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Document ID (tappable for copy)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => _copyId(context),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            documentId,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.blue.shade700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.copy,
                          size: 14,
                          color: Colors.blue.shade700,
                        ),
                      ],
                    ),
                  ),
                  if (primaryField != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      primaryField,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Expand/collapse icon
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.grey.shade600,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
        color: Colors.grey.shade50,
      ),
      padding: const EdgeInsets.all(12),
      child: Directionality(
        textDirection: TextDirection.ltr, // JSON is LTR
        child: JsonTreeView(
          data: {'id': documentId, ...data},
          initiallyExpanded: true,
        ),
      ),
    );
  }

  String? _getPrimaryFieldValue() {
    // Try common primary field names
    final primaryKeys = ['name', 'title', 'firstName', 'displayName', 'label'];
    for (final key in primaryKeys) {
      if (data.containsKey(key) && data[key] != null) {
        return data[key].toString();
      }
    }
    // Fall back to first string field
    for (final entry in data.entries) {
      if (entry.value is String && entry.value.toString().isNotEmpty) {
        return '${entry.key}: ${entry.value}';
      }
    }
    return null;
  }

  void _copyId(BuildContext context) {
    Clipboard.setData(ClipboardData(text: documentId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('הועתק: $documentId'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
