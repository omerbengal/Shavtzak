import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../../core/debug/logger.dart';
import '../../../../core/services/environment_service.dart';
import '../../../../core/constants/role_types.dart';
import 'document_card.dart';

/// A widget that displays a real-time stream of documents from a Firestore collection.
/// Supports searching, filtering, and expanding documents.
/// Displays all documents in a Column (no internal scrolling) for unified page scroll.
class CollectionViewer extends StatefulWidget {
  final String collectionName;
  final bool useEnvironmentPrefix;
  final String searchQuery;
  final Map<String, Map<String, Map<String, dynamic>>>?
      collectionsData; // Data from other collections for lookups
  final ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>?
      documentsNotifier; // Receive sorted documents from parent
  final bool
      isLoaded; // Whether the collection has received its first data snapshot
  final Set<String> expandedDocIds; // Expanded document IDs (managed by parent)
  final Function(String documentId)
      onToggleDocument; // Callback to toggle document expansion

  const CollectionViewer({
    super.key,
    required this.collectionName,
    this.useEnvironmentPrefix = true,
    this.searchQuery = '',
    this.collectionsData,
    this.documentsNotifier,
    this.isLoaded = false,
    required this.expandedDocIds,
    required this.onToggleDocument,
  });

  @override
  State<CollectionViewer> createState() => _CollectionViewerState();
}

class _CollectionViewerState extends State<CollectionViewer> {
  static const int _lazyPageSize = 10;
  late int _visibleDocumentsCount;

  bool get _isLazyCollection =>
      widget.collectionName == 'assignments' ||
      widget.collectionName == 'logs' ||
      widget.collectionName == 'events';

  bool get _isLogCollection => widget.collectionName == 'logs';

  int get _initialVisibleCount => _isLazyCollection ? _lazyPageSize : 999999;

  @override
  void initState() {
    super.initState();
    _visibleDocumentsCount = _initialVisibleCount;
  }

  @override
  void didUpdateWidget(covariant CollectionViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collectionName != widget.collectionName ||
        oldWidget.searchQuery != widget.searchQuery) {
      _visibleDocumentsCount = _initialVisibleCount;
    }
  }

  String get _fullCollectionName {
    if (widget.useEnvironmentPrefix) {
      final prefix = EnvironmentService.instance.collectionPrefix;
      return '$prefix${widget.collectionName}';
    }
    return widget.collectionName;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getCollectionStream() {
    return FirebaseFirestore.instance
        .collection(_fullCollectionName)
        .snapshots();
  }

  /// Get the primary field value for a document (insightful preview text)
  /// This is the same logic used in DocumentCard._getPrimaryFieldValue()
  String? _getPrimaryFieldValue(Map<String, dynamic> data) {
    if (widget.collectionName == 'events') {
      return _formatEventPreview(data);
    }

    // Collection-specific hints
    // Checklist items: Show "EventName | ItemName | ResponsibleName"
    if (widget.collectionName == 'checklist_items') {
      final name = data['name'] as String?;
      final eventId = data['eventId'] as String?;
      final responsibleId = data['responsibleId'] as String?;

      String? eventName;
      String? responsibleName;

      if (eventId != null && widget.collectionsData != null) {
        final eventData = widget.collectionsData!['events'];
        if (eventData != null) {
          final event = eventData[eventId];
          if (event != null && event['name'] != null) {
            eventName = event['name'] as String;
          }
        }
      }

      if (responsibleId != null && widget.collectionsData != null) {
        final membersData = widget.collectionsData!['teamMembers'];
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

    // Assignments: Show "TeamMemberName | RoleName | EventName"
    if (widget.collectionName == 'assignments') {
      final teamMemberId = data['teamMemberId'] as String?;
      final eventId = data['eventId'] as String?;
      final roleType = data['roleType'] as String?;

      String? memberName;
      String? eventName;
      String roleName = 'לא ידוע';

      // Get team member name from collectionsData
      if (teamMemberId != null && widget.collectionsData != null) {
        final membersData = widget.collectionsData!['teamMembers'];
        if (membersData != null) {
          final member = membersData[teamMemberId];
          if (member != null && member['name'] != null) {
            memberName = member['name'] as String;
          }
        }
      }

      // Get event name from collectionsData
      if (eventId != null && widget.collectionsData != null) {
        final eventsData = widget.collectionsData!['events'];
        if (eventsData != null) {
          final event = eventsData[eventId];
          if (event != null && event['name'] != null) {
            eventName = event['name'] as String;
          }
        }
      }

      // Get role name in Hebrew
      if (roleType != null) {
        try {
          roleName = RoleTypeExtension.fromString(roleType).hebrewName;
        } catch (_) {
          roleName = roleType;
        }
      }

      final member = memberName ?? 'חבר צוות לא ידוע';
      final event = eventName ?? 'אירוע לא ידוע';

      return '$member | $roleName | $event';
    }

    // Logs: "<performerName> <actionType> <entityType> | <timestampLocalIsrael>"
    if (widget.collectionName == 'logs') {
      final actionTypeRaw = data['actionType'] as String?;
      final entityTypeRaw = data['entityType'] as String?;
      final entityName = _getLogEntityName(data);
      final entityNameSuffix = entityName != null ? ' "$entityName"' : '';

      final actor = _getLogActor(data);
      final actionType = _getActionTypeHebrew(actionTypeRaw);
      final entityType = _getEntityTypeHebrew(entityTypeRaw);
      final timestampText = _formatLogTimestamp(data);

      return '$actor $actionType $entityType$entityNameSuffix | $timestampText';
    }

    // Team members: Show name + capability count
    if (widget.collectionName == 'teamMembers') {
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

    // Utilities, Keys, and others: Show field names
    if (widget.collectionName.contains('utilit') ||
        widget.collectionName.contains('key')) {
      final fieldNames = data.keys.where((k) => k != 'id').toList();
      if (fieldNames.isNotEmpty) {
        return fieldNames.join(', ');
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

  String? _formatEventPreview(Map<String, dynamic> data) {
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
    final normalized = parts.isNotEmpty ? parts.last : raw;
    switch (normalized) {
      case 'deletebyevent':
      case 'deletebyperson':
      case 'deletebatch':
        return 'delete';
      case 'insertbatch':
        return 'create';
      default:
        return normalized;
    }
  }

  String? _readTrimmedString(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _getLogActor(Map<String, dynamic> data) {
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

  String? _getLogEntityName(Map<String, dynamic> data) {
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
      case 'assignmentlabel':
        return 'לייבל';
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
      case 'assignmentlabelbatch':
        return 'לייבלים (פעולה קיבוצית)';
      case 'checklistitembatch':
        return 'פריטי צ\'קליסט (פעולה קיבוצית)';
      case 'rolebatch':
        return 'תפקידים (פעולה קיבוצית)';
      default:
        return entityType ?? 'ישות לא ידועה';
    }
  }

  String _formatLogTimestamp(Map<String, dynamic> data) {
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

  @override
  Widget build(BuildContext context) {
    // If a documentsNotifier is provided (from parent with sorting), use it
    // Otherwise, fall back to our own Firestore query
    if (widget.documentsNotifier != null) {
      return ValueListenableBuilder<
          List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        valueListenable: widget.documentsNotifier!,
        builder: (context, docs, _) {
          if (_isLogCollection) {
            final logGroups = _buildLogGroups(docs);

            if (logGroups.isEmpty) {
              if (docs.isEmpty && !widget.isLoaded) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'אין מסמכים',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }

            return _buildLogGroupsList(logGroups, docs.length);
          }

          // Filter documents based on search query
          final filteredDocs = _filterDocuments(docs);

          if (filteredDocs.isEmpty) {
            if (docs.isEmpty && !widget.isLoaded) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'אין מסמכים',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }

          return _buildDocumentsList(filteredDocs);
        },
      );
    }

    // Fall back to Firestore query (for collections without custom sorting)
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _getCollectionStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'שגיאה: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ],
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (snapshot.connectionState == ConnectionState.waiting &&
            docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (_isLogCollection) {
          final logGroups = _buildLogGroups(docs);
          if (logGroups.isEmpty) {
            return const SizedBox.shrink();
          }

          return _buildLogGroupsList(logGroups, docs.length);
        }

        // Filter documents based on search query
        final filteredDocs = _filterDocuments(docs);

        if (filteredDocs.isEmpty) {
          return const SizedBox.shrink();
        }

        return _buildDocumentsList(filteredDocs);
      },
    );
  }

  Widget _buildDocumentsList(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredDocs) {
    final totalDocuments = filteredDocs.length;
    final visibleCount = _isLazyCollection
        ? math.min(_visibleDocumentsCount, totalDocuments)
        : totalDocuments;
    final visibleDocuments = filteredDocs.take(visibleCount).toList();

    // Build all documents as a Column - no internal scrolling
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Collection stats header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              Text(
                _fullCollectionName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                _isLazyCollection
                    ? '$visibleCount מתוך $totalDocuments מסמכים'
                    : '$totalDocuments מסמכים',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        // All documents as a Column
        ...visibleDocuments.map((doc) {
          final data = doc.data();
          final isExpanded = widget.expandedDocIds.contains(doc.id);

          return DocumentCard(
            key: ValueKey('${widget.collectionName}_${doc.id}'),
            documentId: doc.id,
            data: data,
            isExpanded: isExpanded,
            collectionName: widget.collectionName,
            collectionsData: widget.collectionsData
                ?.cast<String, Map<String, Map<String, dynamic>>>(),
            onToggle: () {
              Logger.action('tap:toggleDocument', {'documentId': doc.id, 'collection': widget.collectionName});
              widget.onToggleDocument(doc.id);
            },
          );
        }),
        if (_isLazyCollection && visibleCount < totalDocuments)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Align(
              alignment: Alignment.center,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: () {
                  Logger.action('tap:loadMore', {'collection': widget.collectionName});
                  setState(() {
                    _visibleDocumentsCount += _lazyPageSize;
                  });
                },
                icon: const Icon(Icons.expand_more),
                label: const Text('טען עוד'),
              ),
            ),
          ),
      ],
    );
  }

  List<_LogDocumentGroup> _buildLogGroups(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final matchesSearch = <String, bool>{
      for (final doc in docs) doc.id: _documentMatchesSearch(doc),
    };
    final docsByOperationId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in docs) {
      final operationId = _readTrimmedString(doc.data()['operationId']);
      if (operationId != null) {
        docsByOperationId[operationId] = doc;
      }
    }

    final childrenByParentOperationId =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    final topLevelDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (final doc in docs) {
      final parentOperationId =
          _readTrimmedString(doc.data()['parentOperationId']);
      if (parentOperationId != null &&
          docsByOperationId.containsKey(parentOperationId)) {
        childrenByParentOperationId
            .putIfAbsent(parentOperationId, () => [])
            .add(doc);
        continue;
      }
      topLevelDocs.add(doc);
    }

    final groups = <_LogDocumentGroup>[];
    final isSearching = widget.searchQuery.isNotEmpty;

    for (final parentDoc in topLevelDocs) {
      final operationId = _readTrimmedString(parentDoc.data()['operationId']);
      final allChildren = operationId == null
          ? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]
          : (childrenByParentOperationId[operationId] ?? const []);
      final parentMatches = matchesSearch[parentDoc.id] ?? false;
      final matchingChildren = isSearching
          ? allChildren.where((child) => matchesSearch[child.id] ?? false).toList()
          : allChildren;

      if (!isSearching || parentMatches || matchingChildren.isNotEmpty) {
        groups.add(
          _LogDocumentGroup(
            parent: parentDoc,
            visibleChildren:
                isSearching && !parentMatches ? matchingChildren : allChildren,
            matchingChildrenCount: matchingChildren.length,
            parentMatchesSearch: parentMatches,
          ),
        );
      }
    }

    return groups;
  }

  Widget _buildLogGroupsList(
    List<_LogDocumentGroup> groups,
    int totalLogDocuments,
  ) {
    final totalGroups = groups.length;
    final visibleCount = _isLazyCollection
        ? math.min(_visibleDocumentsCount, totalGroups)
        : totalGroups;
    final visibleGroups = groups.take(visibleCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              Text(
                _fullCollectionName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                _isLazyCollection
                    ? '$visibleCount מתוך $totalGroups פעולות ($totalLogDocuments לוגים)'
                    : '$totalGroups פעולות ($totalLogDocuments לוגים)',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        ...visibleGroups.map(_buildLogGroupItem),
        if (_isLazyCollection && visibleCount < totalGroups)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Align(
              alignment: Alignment.center,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: () {
                  Logger.action('tap:loadMore', {'collection': widget.collectionName});
                  setState(() {
                    _visibleDocumentsCount += _lazyPageSize;
                  });
                },
                icon: const Icon(Icons.expand_more),
                label: const Text('טען עוד'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLogGroupItem(_LogDocumentGroup group) {
    final parentDoc = group.parent;
    final parentData = parentDoc.data();
    final isParentExpanded = widget.expandedDocIds.contains(parentDoc.id);
    final shouldShowChildren =
        isParentExpanded ||
        (widget.searchQuery.isNotEmpty && group.visibleChildren.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DocumentCard(
          key: ValueKey('${widget.collectionName}_${parentDoc.id}'),
          documentId: parentDoc.id,
          data: parentData,
          isExpanded: isParentExpanded,
          collectionName: widget.collectionName,
          collectionsData:
              widget.collectionsData?.cast<String, Map<String, Map<String, dynamic>>>(),
          onToggle: () {
            Logger.action('tap:toggleDocument', {'documentId': parentDoc.id, 'collection': widget.collectionName});
            widget.onToggleDocument(parentDoc.id);
          },
        ),
        if (shouldShowChildren && group.visibleChildren.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 24,
              end: 8,
              bottom: 10,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _buildChildLogsLabel(group),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...group.visibleChildren.map((childDoc) {
                    final childData = childDoc.data();
                    final isChildExpanded =
                        widget.expandedDocIds.contains(childDoc.id);

                    return DocumentCard(
                      key: ValueKey(
                          '${widget.collectionName}_${parentDoc.id}_${childDoc.id}'),
                      documentId: childDoc.id,
                      data: childData,
                      isExpanded: isChildExpanded,
                      collectionName: widget.collectionName,
                      collectionsData: widget.collectionsData
                          ?.cast<String, Map<String, Map<String, dynamic>>>(),
                      onToggle: () {
                        Logger.action('tap:toggleDocument', {'documentId': childDoc.id, 'collection': widget.collectionName});
                        widget.onToggleDocument(childDoc.id);
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _buildChildLogsLabel(_LogDocumentGroup group) {
    if (widget.searchQuery.isNotEmpty &&
        !group.parentMatchesSearch &&
        group.matchingChildrenCount > 0) {
      return 'לוגים קשורים (${group.matchingChildrenCount} תואמים לחיפוש)';
    }

    return 'לוגים קשורים (${group.visibleChildren.length})';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocuments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (widget.searchQuery.isEmpty) return docs;

    return docs.where(_documentMatchesSearch).toList();
  }

  bool _documentMatchesSearch(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    if (widget.searchQuery.isEmpty) return true;

    final query = widget.searchQuery.toLowerCase();
    if (doc.id.toLowerCase().contains(query)) return true;

    final data = doc.data();
    final primaryValue = _getPrimaryFieldValue(data);
    if (primaryValue != null && primaryValue.toLowerCase().contains(query)) {
      return true;
    }

    return _searchInMap(data, query);
  }

  bool _searchInMap(Map<String, dynamic> map, String query) {
    for (final entry in map.entries) {
      final value = entry.value;
      if (value == null) continue;

      if (value is String && value.toLowerCase().contains(query)) {
        return true;
      } else if (value is Map<String, dynamic> && _searchInMap(value, query)) {
        return true;
      } else if (value is List) {
        for (final item in value) {
          if (item is String && item.toLowerCase().contains(query)) {
            return true;
          } else if (item is Map<String, dynamic> &&
              _searchInMap(item, query)) {
            return true;
          }
        }
      } else if (value.toString().toLowerCase().contains(query)) {
        return true;
      }
    }
    return false;
  }
}

class _LogDocumentGroup {
  final QueryDocumentSnapshot<Map<String, dynamic>> parent;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> visibleChildren;
  final int matchingChildrenCount;
  final bool parentMatchesSearch;

  const _LogDocumentGroup({
    required this.parent,
    required this.visibleChildren,
    required this.matchingChildrenCount,
    required this.parentMatchesSearch,
  });
}
