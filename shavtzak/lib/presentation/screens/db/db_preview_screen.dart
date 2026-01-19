import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/constants/role_types.dart';
import 'widgets/collection_viewer.dart';

/// A hidden diagnostic screen for viewing Firestore data in real-time.
/// Accessible at /db (production) or /test/db (test environment).
/// No authentication required - URL obscurity is sufficient protection.
class DbPreviewScreen extends StatefulWidget {
  const DbPreviewScreen({super.key});

  @override
  State<DbPreviewScreen> createState() => _DbPreviewScreenState();
}

class _DbPreviewScreenState extends State<DbPreviewScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedCollections = {};
  final ScrollController _scrollController = ScrollController();

  // Track expanded document IDs per collection (moved from CollectionViewer to prevent state loss on scroll)
  final Map<String, Set<String>> _expandedDocIdsByCollection = {};

  // Track document counts per collection using ValueNotifier
  final Map<String, ValueNotifier<int>> _docCountNotifiers = {};

  // Track filtered document counts per collection (for hiding empty collections during search)
  final Map<String, ValueNotifier<int>> _filteredCountNotifiers = {};

  // Track stream subscriptions
  final Map<String, StreamSubscription<QuerySnapshot>> _streamSubscriptions = {};

  // Track document data for filtering (cache for search)
  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _collectionDataCache = {};

  // ValueNotifiers for collections that need custom sorting (events, roles, assignments, checklist_items)
  final Map<String, ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>> _sortedCollectionNotifiers = {};

  // All collections to display
  static const List<_CollectionConfig> _collections = [
    _CollectionConfig('teamMembers', 'חברי צוות', Icons.people, true),
    _CollectionConfig('events', 'אירועים', Icons.event, true),
    _CollectionConfig('assignments', 'שיבוצים', Icons.assignment_ind, true),
    _CollectionConfig('checklist_items', 'פריטי צ\'קליסט', Icons.checklist, true),
    _CollectionConfig('checklist_presets', 'תבניות צ\'קליסט', Icons.list_alt, true),
    _CollectionConfig('roles', 'תפקידים', Icons.work, true),
    _CollectionConfig('utilities', 'כלים (גלובלי)', Icons.build, false),
    _CollectionConfig('keys', 'מפתחות (גלובלי)', Icons.key, false),
  ];

  @override
  void initState() {
    super.initState();
    // Initialize notifiers for all collections
    for (final config in _collections) {
      _docCountNotifiers.putIfAbsent(config.name, () => ValueNotifier<int>(0));
      _filteredCountNotifiers.putIfAbsent(config.name, () => ValueNotifier<int>(0));
    }
    // Start listening to all collections for real-time count updates
    _startListeningToAllCollections();
  }

  /// Get the sorted notifier for a collection
  ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _getSortedNotifier(String collectionName) {
    return _sortedCollectionNotifiers[collectionName];
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    // Cancel all stream subscriptions
    for (final sub in _streamSubscriptions.values) {
      sub.cancel();
    }
    // Dispose all sorted collection notifiers
    for (final notifier in _sortedCollectionNotifiers.values) {
      notifier.dispose();
    }
    // Dispose all notifiers
    for (final notifier in _docCountNotifiers.values) {
      notifier.dispose();
    }
    for (final notifier in _filteredCountNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  /// Start streaming all collections to keep counts updated in real-time
  void _startListeningToAllCollections() {
    final prefix = EnvironmentService.instance.collectionPrefix;

    for (final config in _collections) {
      final collectionName = config.useEnvironmentPrefix ? '$prefix${config.name}' : config.name;

      // Create ValueNotifier for all collections that need sorting (events, roles, assignments, checklist_items)
      // Initialize with empty list to prevent loading issues
      if (config.name == 'events' || config.name == 'roles' || config.name == 'assignments' || config.name == 'checklist_items') {
        _sortedCollectionNotifiers.putIfAbsent(
          config.name,
          () => ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>([]),
        );
      }

      // Create query with appropriate orderBy
      Query query = FirebaseFirestore.instance.collection(collectionName).limit(100);

      // Add orderBy based on collection type
      if (config.name == 'events') {
        query = query.orderBy('startDate', descending: false);
      } else if (config.name == 'roles') {
        query = query.orderBy('sortOrder', descending: false);
      }

      final subscription = query.snapshots().listen((snapshot) {
        var docs = snapshot.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>();

        // Client-side sorting for complex cases
        if (config.name == 'assignments') {
          // Sort assignments by event.startDate then role.sortOrder
          // This requires joining with events and roles data
          docs = _sortAssignments(docs);
        } else if (config.name == 'checklist_items') {
          // Sort checklist items by event.startDate
          docs = _sortChecklistItems(docs);
        }

        // Cache the document data for filtering
        _collectionDataCache[config.name] = docs;

        // Update sorted collection notifier if it exists
        final sortedNotifier = _sortedCollectionNotifiers[config.name];
        if (sortedNotifier != null) {
          sortedNotifier.value = docs;
        }

        final count = docs.length;

        // Update total count
        final countNotifier = _docCountNotifiers[config.name];
        if (countNotifier != null && countNotifier.value != count) {
          countNotifier.value = count;
        }

        // If search is empty, filtered count = total count
        // If search is active, filter the cached data
        if (_searchQuery.isEmpty) {
          final filteredNotifier = _filteredCountNotifiers[config.name];
          if (filteredNotifier != null && filteredNotifier.value != count) {
            filteredNotifier.value = count;
          }
        } else {
          // Search is active - filter this collection's data
          _filterAndUpdateCount(config.name, docs);
        }
      });

      _streamSubscriptions[config.name] = subscription;
    }
  }

  /// Sort assignments by event.startDate then role.sortOrder
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortAssignments(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // We need to sort by event data and role data
    // Build maps for quick lookup
    final Map<String, DateTime> eventStartDates = {};
    final Map<String, int> roleSortOrders = {};

    // Get events data
    final eventsDocs = _collectionDataCache['events'];
    if (eventsDocs != null) {
      for (final doc in eventsDocs) {
        final data = doc.data() as Map<String, dynamic>;
        final startDate = data['startDate'];
        if (startDate is Timestamp) {
          eventStartDates[doc.id] = startDate.toDate();
        }
      }
    }

    // Get roles data
    final rolesDocs = _collectionDataCache['roles'];
    if (rolesDocs != null) {
      for (final doc in rolesDocs) {
        final data = doc.data() as Map<String, dynamic>;
        final sortOrder = data['sortOrder'];
        if (sortOrder is int) {
          roleSortOrders[data['key']] = sortOrder;
        }
      }
    }

    // Sort assignments
    final sortedDocs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sortedDocs.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;

      final aEventId = aData['eventId'] as String?;
      final bEventId = bData['eventId'] as String?;
      final aRoleType = aData['roleType'] as String?;
      final bRoleType = bData['roleType'] as String?;

      // First compare by event start date
      final aEventDate = aEventId != null ? (eventStartDates[aEventId] ?? DateTime(2099, 12, 31)) : DateTime(2099, 12, 31);
      final bEventDate = bEventId != null ? (eventStartDates[bEventId] ?? DateTime(2099, 12, 31)) : DateTime(2099, 12, 31);
      final dateCompare = aEventDate.compareTo(bEventDate);
      if (dateCompare != 0) return dateCompare;

      // Then compare by role sort order
      final aRoleSort = aRoleType != null ? (roleSortOrders[aRoleType] ?? 999) : 999;
      final bRoleSort = bRoleType != null ? (roleSortOrders[bRoleType] ?? 999) : 999;
      return aRoleSort.compareTo(bRoleSort);
    });

    return sortedDocs;
  }

  /// Sort checklist items by event.startDate
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortChecklistItems(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // Build map of event start dates
    final Map<String, DateTime> eventStartDates = {};
    final eventsDocs = _collectionDataCache['events'];
    if (eventsDocs != null) {
      for (final doc in eventsDocs) {
        final data = doc.data() as Map<String, dynamic>;
        final startDate = data['startDate'];
        if (startDate is Timestamp) {
          eventStartDates[doc.id] = startDate.toDate();
        }
      }
    }

    // Sort checklist items
    final sortedDocs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sortedDocs.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;

      final aEventId = aData['eventId'] as String?;
      final bEventId = bData['eventId'] as String?;

      final aEventDate = aEventId != null ? (eventStartDates[aEventId] ?? DateTime(2099, 12, 31)) : DateTime(2099, 12, 31);
      final bEventDate = bEventId != null ? (eventStartDates[bEventId] ?? DateTime(2099, 12, 31)) : DateTime(2099, 12, 31);

      return aEventDate.compareTo(bEventDate);
    });

    return sortedDocs;
  }

  /// Filter a collection's documents and update the filtered count
  void _filterAndUpdateCount(String collectionName, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (_searchQuery.isEmpty) {
      // No search - all docs match
      _filteredCountNotifiers[collectionName]!.value = docs.length;
      return;
    }

    final query = _searchQuery.toLowerCase();
    int matchCount = 0;

    for (final doc in docs) {
      // Search in document ID
      if (doc.id.toLowerCase().contains(query)) {
        matchCount++;
        continue;
      }

      // Search in primary field value (insightful preview text)
      final data = doc.data() as Map<String, dynamic>;
      final primaryValue = _getPrimaryFieldValue(collectionName, data);
      if (primaryValue != null && primaryValue.toLowerCase().contains(query)) {
        matchCount++;
        continue;
      }

      // Search in document data
      if (_searchInDocData(data, query)) {
        matchCount++;
      }
    }

    _filteredCountNotifiers[collectionName]!.value = matchCount;
  }

  /// Search helper - check if query matches document data
  bool _searchInDocData(Map<String, dynamic> data, String query) {
    // Search in all string values
    for (final entry in data.entries) {
      final value = entry.value;
      if (value == null) continue;

      if (value is String && value.toLowerCase().contains(query)) {
        return true;
      } else if (value is Map<String, dynamic> && _searchInDocData(value, query)) {
        return true;
      } else if (value is List) {
        for (final item in value) {
          if (item is String && item.toLowerCase().contains(query)) {
            return true;
          } else if (item is Map<String, dynamic> && _searchInDocData(item, query)) {
            return true;
          }
        }
      } else if (value.toString().toLowerCase().contains(query)) {
        return true;
      }
    }
    return false;
  }

  /// Get the primary field value for filtering (same logic as CollectionViewer and DocumentCard)
  String? _getPrimaryFieldValue(String collectionName, Map<String, dynamic> data) {
    // Checklist items: Show "EventName | ItemName"
    if (collectionName.contains('checklist_item')) {
      final name = data['name'] as String?;
      final eventId = data['eventId'] as String?;

      if (name != null && eventId != null) {
        // Try to get event name from cache
        final eventsDocs = _collectionDataCache['events'];
        if (eventsDocs != null) {
          for (final eventDoc in eventsDocs) {
            if (eventDoc.id == eventId) {
              final eventData = eventDoc.data() as Map<String, dynamic>;
              final eventName = eventData['name'] as String?;
              if (eventName != null) {
                return '$eventName | $name';
              }
            }
          }
        }
      }
      if (name != null) return name;
    }

    // Assignments: Show "TeamMemberName | RoleName | EventName"
    if (collectionName.contains('assignment')) {
      final teamMemberId = data['teamMemberId'] as String?;
      final eventId = data['eventId'] as String?;
      final roleType = data['roleType'] as String?;

      String? memberName;
      String? eventName;
      String roleName = 'לא ידוע';

      // Get team member name from cache
      if (teamMemberId != null) {
        final membersDocs = _collectionDataCache['teamMembers'];
        if (membersDocs != null) {
          for (final memberDoc in membersDocs) {
            if (memberDoc.id == teamMemberId) {
              final memberData = memberDoc.data() as Map<String, dynamic>;
              memberName = memberData['name'] as String?;
              break;
            }
          }
        }
      }

      // Get event name from cache
      if (eventId != null) {
        final eventsDocs = _collectionDataCache['events'];
        if (eventsDocs != null) {
          for (final eventDoc in eventsDocs) {
            if (eventDoc.id == eventId) {
              final eventData = eventDoc.data() as Map<String, dynamic>;
              eventName = eventData['name'] as String?;
              break;
            }
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

    // Roles collection: Show just the Hebrew name
    if (collectionName == 'roles') {
      return data['hebrewName'] as String?;
    }

    // Team members: Show name + capability count
    if (collectionName.contains('teamMember')) {
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

    // Utilities, Keys, and others: Show field names
    if (collectionName.contains('utilit') || collectionName.contains('key')) {
      final fieldNames = data.keys.where((k) => k != 'id').toList();
      if (fieldNames.isNotEmpty) {
        return fieldNames.join(', ');
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

  /// Update filtered counts for all collections when search query changes
  void _updateAllFilteredCounts() {
    for (final config in _collections) {
      final docs = _collectionDataCache[config.name];
      if (docs != null) {
        _filterAndUpdateCount(config.name, docs);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EnvironmentService.instance,
      builder: (context, _) {
        final isTestMode = EnvironmentService.instance.isTestMode;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildEnvironmentBadge(isTestMode),
                  const SizedBox(width: 8),
                  const Text('DB Preview'),
                ],
              ),
            ),
            body: Column(
              children: [
                // Search bar
                _buildSearchBar(),
                // Collections list
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    cacheExtent: 2000, // Keep more widgets cached to prevent scroll jumping
                    itemCount: _collections.length,
                    itemBuilder: (context, index) {
                      final config = _collections[index];
                      final isExpanded = _expandedCollections.contains(config.name);
                      final filteredCountNotifier = _filteredCountNotifiers[config.name]!;

                      // Hide collection if searching and has no matching documents (but never hide expanded collections)
                      return ValueListenableBuilder<int>(
                        valueListenable: filteredCountNotifier,
                        builder: (context, filteredCount, _) {
                          // Hide when searching, no matches (count = 0), AND not expanded
                          if (_searchQuery.isNotEmpty && filteredCount == 0 && !isExpanded) {
                            return const SizedBox.shrink();
                          }
                                          return _buildCollectionCard(
                            key: ValueKey(config.name),
                            config: config,
                            isExpanded: isExpanded,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEnvironmentBadge(bool isTestMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isTestMode ? Colors.red.shade600 : Colors.green.shade600,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isTestMode ? 'TEST' : 'PROD',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey.shade100,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'חיפוש לפי ID או תוכן...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Collapse all button (always visible on the left in RTL)
              IconButton(
                icon: const Icon(Icons.unfold_less),
                onPressed: () {
                  setState(() {
                    // Collapse all collections
                    _expandedCollections.clear();
                    // Collapse all documents within all collections
                    _expandedDocIdsByCollection.clear();
                  });
                },
                tooltip: 'כווץ הכל',
              ),
              // Clear button (only show when there's search text)
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                    // Update filtered counts when clearing search
                    _updateAllFilteredCounts();
                  },
                ),
            ],
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
          // Update filtered counts when search changes
          _updateAllFilteredCounts();
        },
      ),
    );
  }

  /// Get expanded document IDs for a specific collection
  Set<String> _getExpandedDocIds(String collectionName) {
    return _expandedDocIdsByCollection.putIfAbsent(collectionName, () => {});
  }

  /// Toggle document expansion for a specific collection
  void _toggleDocumentExpansion(String collectionName, String documentId) {
    setState(() {
      final expandedIds = _getExpandedDocIds(collectionName);
      if (expandedIds.contains(documentId)) {
        expandedIds.remove(documentId);
      } else {
        expandedIds.add(documentId);
      }
    });
  }

  Widget _buildCollectionCard({
    Key? key,
    required _CollectionConfig config,
    required bool isExpanded,
  }) {
    final fullName = config.useEnvironmentPrefix
        ? '${EnvironmentService.instance.collectionPrefix}${config.name}'
        : config.name;
    final countNotifier = _docCountNotifiers[config.name]!;
    final filteredCountNotifier = _filteredCountNotifiers[config.name]!;

    // Build collections data map for CollectionViewer (used for checklist items to show event names)
    final Map<String, Map<String, Map<String, dynamic>>> collectionsData = {};
    for (final entry in _collectionDataCache.entries) {
      final collectionName = entry.key;
      final docs = entry.value;
      final Map<String, Map<String, dynamic>> dataMap = {};
      for (final doc in docs) {
        dataMap[doc.id] = doc.data() as Map<String, dynamic>;
      }
      collectionsData[collectionName] = dataMap;
    }

    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade400, width: 1),
      ),
      child: Column(
        children: [
          // Collection header
          ListTile(
            leading: Icon(config.icon, color: Theme.of(context).primaryColor),
            title: ListenableBuilder(
              listenable: Listenable.merge([countNotifier, filteredCountNotifier]),
              builder: (context, _) {
                // Show filtered count when searching, total count otherwise
                final displayCount = _searchQuery.isNotEmpty
                    ? filteredCountNotifier.value
                    : countNotifier.value;
                return Text(
                  '${config.hebrewName} ($displayCount)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                );
              },
            ),
            subtitle: Text(
              fullName,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Colors.grey.shade600,
              ),
            ),
            trailing: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCollections.remove(config.name);
                } else {
                  _expandedCollections.add(config.name);
                }
              });
            },
          ),
          // Expanded content - no height constraint, let it be part of main scroll
          if (isExpanded)
            RepaintBoundary(
              child: CollectionViewer(
                key: ValueKey('${config.name}_$_searchQuery'),
                collectionName: config.name,
                useEnvironmentPrefix: config.useEnvironmentPrefix,
                searchQuery: _searchQuery,
                collectionsData: collectionsData,
                documentsNotifier: _getSortedNotifier(config.name),
                expandedDocIds: _getExpandedDocIds(config.name),
                onToggleDocument: (docId) => _toggleDocumentExpansion(config.name, docId),
              ),
            ),
        ],
      ),
    );
  }
}

/// Configuration for a single collection
class _CollectionConfig {
  final String name;
  final String hebrewName;
  final IconData icon;
  final bool useEnvironmentPrefix;

  const _CollectionConfig(this.name, this.hebrewName, this.icon, this.useEnvironmentPrefix);
}
