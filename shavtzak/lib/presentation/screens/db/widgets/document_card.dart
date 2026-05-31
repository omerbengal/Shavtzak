import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'json_tree_view.dart';
import 'log_document_card_view.dart';
import '../../../../core/constants/role_types.dart';
import '../../../../core/debug/logger.dart';
import 'assignment_preview.dart';

/// An expandable card that displays a Firestore document.
/// Shows document ID and primary field when collapsed, full JSON when expanded.
class DocumentCard extends StatelessWidget {
  final String documentId;
  final Map<String, dynamic> data;
  final bool isExpanded;
  final VoidCallback onToggle;
  final String? collectionName; // Added for collection-specific hints
  final Map<String, Map<String, Map<String, dynamic>>>?
      collectionsData; // For looking up related data

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
    final isLog = collectionName == 'logs';
    if (isLog) {
      return LogDocumentCardView(
        key: key,
        documentId: documentId,
        data: data,
        isExpanded: isExpanded,
        onToggle: onToggle,
        collectionsData: collectionsData,
      );
    }

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
    final isAssignment = collectionName == 'assignments';

    return InkWell(
      onTap: () {
        Logger.action('tap:toggleDocumentCard', {'documentId': documentId, 'collectionName': collectionName, 'expanding': !isExpanded});
        onToggle();
      },
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
                    onTap: () {
                      Logger.action('tap:copyDocumentId', {'documentId': documentId, 'collectionName': collectionName});
                      _copyId(context);
                    },
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
    final jsonData = _getExpandedJsonData();
    final isLog = collectionName == 'logs';
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
          data: jsonData,
          initiallyExpanded: !isLog,
        ),
      ),
    );
  }

  Map<String, dynamic> _getExpandedJsonData() {
    final isLog = collectionName == 'logs';
    if (!isLog) {
      return {'id': documentId, ...data};
    }

    final ordered = <String, dynamic>{
      'id': documentId,
      'timestampLocalIsrael': data['timestampLocalIsrael'],
      'timestampUtc': data['timestampUtc'],
      'performerName': data['performerName'],
      'performerId': data['performerId'],
      'performerUniqueKey': data['performerUniqueKey'],
      'actionType': data['actionType'],
      'operation': data['operation'],
      'entityId': data['entityId'],
      'entityType': data['entityType'],
      'entityName': data['entityName'],
      'status': data['status'],
      'source': data['source'],
      'changes': data['changes'],
      'oldValue': data['oldValue'],
      'newValue': data['newValue'],
      'details': data['details'],
      'operationId': data['operationId'],
      'parentOperationId': data['parentOperationId'],
    };

    // Keep only the fields relevant for DB log view and preserve the exact order.
    return ordered;
  }

  String? _getPrimaryFieldValue() {
    // Collection-specific hints
    if (collectionName != null) {
      if (collectionName == 'events') {
        return _formatEventPreview();
      }

      // Assignments: Show role in Hebrew (no status - it's just pending/confirmed/declined)
      if (collectionName == 'assignments') {
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

      // Team members: Show name + capability count
      if (collectionName == 'teamMembers') {
        final name = data['name'] as String?;
        final roleCapabilities =
            data['roleCapabilities'] as Map<String, dynamic>?;
        if (name != null && roleCapabilities != null) {
          final enabledCount =
              roleCapabilities.values.where((v) => v == true).length;
          return '$name ($enabledCount תפקידים)';
        }
        if (name != null) {
          return name;
        }
      }

      // Checklist items: Show "EventName | ItemName | ResponsibleName"
      if (collectionName == 'checklist_items') {
        final name = data['name'] as String?;
        final eventId = data['eventId'] as String?;
        final responsibleId = data['responsibleId'] as String?;

        String? eventName;
        String? responsibleName;

        if (eventId != null && collectionsData != null) {
          final eventData = collectionsData!['events'];
          if (eventData != null) {
            final event = eventData[eventId];
            if (event != null && event['name'] != null) {
              eventName = event['name'] as String;
            }
          }
        }

        if (responsibleId != null && collectionsData != null) {
          final membersData = collectionsData!['teamMembers'];
          if (membersData != null) {
            final member = membersData[responsibleId];
            if (member != null && member['name'] != null) {
              responsibleName = member['name'] as String;
            }
          }
        }

        final parts = <String>[];
        if (eventName != null) parts.add(eventName);
        if (name != null) parts.add(name);
        if (responsibleName != null) parts.add(responsibleName);
        if (parts.isNotEmpty) return parts.join(' | ');
        if (name != null) return name;
      }

      // Logs: "<performerName> <actionType> <entityType> | <timestampLocalIsrael>"
      if (collectionName == 'logs') {
        final actionTypeRaw = data['actionType'] as String?;
        final entityTypeRaw = data['entityType'] as String?;
        final entityName = _getLogEntityName();
        final entityNameSuffix = entityName != null ? ' "$entityName"' : '';

        final actor = _getLogActor();
        final actionType = _getActionTypeHebrew(actionTypeRaw);
        final entityType = _getEntityTypeHebrew(entityTypeRaw);
        final timestampText = _formatLogTimestamp();

        return '$actor $actionType $entityType$entityNameSuffix | $timestampText';
      }

      // Utilities, Keys, and others: Show field names
      if (collectionName!.contains('utilit') ||
          collectionName!.contains('key')) {
        final fieldNames = data.keys.where((k) => k != 'id').toList();
        if (fieldNames.isNotEmpty) {
          return fieldNames.join(', ');
        }
      }
    }

    // Default: Try common primary field names
    final primaryKeys = [
      'name',
      'title',
      'firstName',
      'displayName',
      'label',
      'hebrewName'
    ];
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

  String? _formatEventPreview() {
    final name = data['name'] as String?;
    final start = _asDateTime(data['startDate']);
    final end = _asDateTime(data['endDate']);

    if (name == null || name.trim().isEmpty) {
      return null;
    }

    if (start == null) {
      return name;
    }

    final startText = DateFormat('dd/MM/yyyy').format(start);
    if (end == null || _isSameDate(start, end)) {
      return '$name | $startText';
    }

    final endText = DateFormat('dd/MM/yyyy').format(end);
    return '$name | $startText --> $endText';
  }

  DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _normalizeActionType(String? actionType) {
    final raw = (actionType ?? '').trim().toLowerCase();
    if (raw.isEmpty) return '';
    final parts = raw.split('.');
    return parts.isNotEmpty ? parts.last : raw;
  }

  String _getLogActor() {
    for (final candidate in [
      data['performerName'],
      data['performerUniqueKey'],
      data['performerId'],
    ]) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return 'לא ידוע';
  }

  String? _getLogEntityName() {
    final topLevelName = data['entityName'];
    if (topLevelName is String && topLevelName.trim().isNotEmpty) {
      return topLevelName.trim();
    }

    final details = data['details'];
    if (details is Map) {
      for (final key in ['name', 'entityName']) {
        final value = details[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }

    return null;
  }

  String _getActionTypeHebrew(String? actionType) {
    switch (_normalizeActionType(actionType)) {
      case 'create':
      case 'insert':
        return 'יצר';
      case 'edit':
      case 'update':
        return 'עדכן';
      case 'delete':
        return 'מחק';
      case 'add':
        return 'הוסיף';
      case 'remove':
        return 'הסיר';
      case 'archive':
        return 'העביר לארכיון';
      case 'restore':
        return 'שחזר';
      case 'reorder':
        return 'סידר מחדש';
      case 'loadintoevent':
        return 'טען לאירוע';
      case 'clearalldata':
        return 'ניקה נתונים';
      case 'updatepasscode':
        return 'עדכן קוד גישה';
      case 'clearpasscode':
        return 'איפס קוד גישה';
      case 'updatearchivestatus':
        return 'עדכן ארכיון';
      case 'seed':
        return 'אתחל';
      default:
        return actionType ?? 'לא ידוע';
    }
  }

  String _getEntityTypeHebrew(String? entityType) {
    switch ((entityType ?? '').toLowerCase()) {
      case 'event':
        return 'אירוע';
      case 'teammember':
        return 'חבר צוות';
      case 'checklistitem':
        return 'פריט צ\'קליסט';
      case 'constraint':
        return 'מגבלה';
      case 'availability':
        return 'זמינות';
      case 'assignment':
        return 'שיבוץ';
      case 'checklistnote':
        return 'הערת צ\'קליסט';
      case 'preset':
        return 'תבנית צ\'קליסט';
      case 'role':
        return 'תפקיד';
      case 'category':
        return 'קטגוריה';
      case 'teammemberbatch':
        return 'חברי צוות (פעולה קיבוצית)';
      case 'eventbatch':
        return 'אירועים (פעולה קיבוצית)';
      case 'assignmentbatch':
        return 'שיבוצים (פעולה קיבוצית)';
      case 'checklistitembatch':
        return 'פריטי צ\'קליסט (פעולה קיבוצית)';
      case 'rolebatch':
        return 'תפקידים (פעולה קיבוצית)';
      default:
        return entityType ?? 'ישות לא ידועה';
    }
  }

  String _formatLogTimestamp() {
    final timestampLocalIsrael = data['timestampLocalIsrael'];
    if (timestampLocalIsrael is String) {
      final parsed = DateTime.tryParse(timestampLocalIsrael);
      if (parsed != null) {
        return DateFormat('dd/MM/yyyy, HH:mm:ss.SSS').format(parsed);
      }
    }

    final timestampUtc = data['timestampUtc'];
    if (timestampUtc is Timestamp) {
      return DateFormat('dd/MM/yyyy, HH:mm:ss.SSS')
          .format(timestampUtc.toDate());
    }
    if (timestampUtc is DateTime) {
      return DateFormat('dd/MM/yyyy, HH:mm:ss.SSS').format(timestampUtc);
    }
    if (timestampUtc is String) {
      final parsed = DateTime.tryParse(timestampUtc);
      if (parsed != null) {
        return DateFormat('dd/MM/yyyy, HH:mm:ss.SSS').format(parsed);
      }
    }

    return 'תאריך לא זמין';
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
