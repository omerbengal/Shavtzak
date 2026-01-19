import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'json_tree_view.dart';
import '../../../../core/constants/role_types.dart';
import 'assignment_preview.dart';

/// An expandable card that displays a Firestore document.
/// Shows document ID and primary field when collapsed, full JSON when expanded.
class DocumentCard extends StatelessWidget {
  final String documentId;
  final Map<String, dynamic> data;
  final bool isExpanded;
  final VoidCallback onToggle;
  final String? collectionName; // Added for collection-specific hints
  final Map<String, Map<String, Map<String, dynamic>>>? collectionsData; // For looking up related data

  const DocumentCard({
    super.key,
    required this.documentId,
    required this.data,
    required this.isExpanded,
    required this.onToggle,
    this.collectionName,
    this.collectionsData,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.green.shade50,
      elevation: isExpanded ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade400, width: 1),
      ),
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
    final isAssignment = collectionName != null && collectionName!.contains('assignment');

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
                  if (isAssignment) ...[
                    const SizedBox(height: 4),
                    AssignmentPreview(
                      data: data,
                      collectionsData: collectionsData,
                    ),
                  ] else if (primaryField != null) ...[
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
          top: BorderSide(color: Colors.grey.shade400, width: 1),
        ),
        color: Colors.red.shade50,
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
    // Collection-specific hints
    if (collectionName != null) {
      // Assignments: Show role in Hebrew (no status - it's just pending/confirmed/declined)
      if (collectionName!.contains('assignment')) {
        final roleType = data['roleType'] as String?;
        if (roleType != null) {
          try {
            final role = RoleTypeExtension.fromString(roleType);
            return role.hebrewName;
          } catch (_) {
            // If roleType is invalid, fall through to default
          }
        }
      }

      // Roles collection: Show just the Hebrew name
      if (collectionName == 'roles') {
        return data['hebrewName'] as String?;
      }

      // Team members: Show name + capability count
      if (collectionName!.contains('teamMember')) {
        final name = data['name'] as String?;
        final roleCapabilities = data['roleCapabilities'] as Map<String, dynamic>?;
        if (name != null && roleCapabilities != null) {
          final enabledCount = roleCapabilities.values.where((v) => v == true).length;
          return '$name ($enabledCount תפקידים)';
        }
        if (name != null) {
          return name;
        }
      }

      // Checklist items: Show "EventName | ItemName"
      if (collectionName!.contains('checklist_item')) {
        final name = data['name'] as String?;
        final eventId = data['eventId'] as String?;

        if (name != null && eventId != null && collectionsData != null) {
          // Try to get event name from collectionsData
          final eventData = collectionsData!['events'];
          if (eventData != null) {
            final event = eventData[eventId];
            if (event != null && event['name'] != null) {
              final eventName = event['name'] as String;
              return '$eventName | $name';
            }
          }
        }
        if (name != null) return name;
      }

      // Utilities, Keys, and others: Show field names
      if (collectionName!.contains('utilit') || collectionName!.contains('key')) {
        final fieldNames = data.keys.where((k) => k != 'id').toList();
        if (fieldNames.isNotEmpty) {
          return fieldNames.join(', ');
        }
      }
    }

    // Default: Try common primary field names
    final primaryKeys = ['name', 'title', 'firstName', 'displayName', 'label', 'hebrewName'];
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
