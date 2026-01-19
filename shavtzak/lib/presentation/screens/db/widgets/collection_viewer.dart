import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/services/environment_service.dart';
import 'document_card.dart';

/// A widget that displays a real-time stream of documents from a Firestore collection.
/// Supports searching, filtering, and expanding documents.
class CollectionViewer extends StatefulWidget {
  final String collectionName;
  final bool useEnvironmentPrefix;
  final String searchQuery;

  const CollectionViewer({
    super.key,
    required this.collectionName,
    this.useEnvironmentPrefix = true,
    this.searchQuery = '',
  });

  @override
  State<CollectionViewer> createState() => _CollectionViewerState();
}

class _CollectionViewerState extends State<CollectionViewer> {
  final Set<String> _expandedDocIds = {};

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
        .limit(100)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
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

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'אין מסמכים ב-$_fullCollectionName',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Filter documents based on search query
        final filteredDocs = _filterDocuments(docs);

        return RefreshIndicator(
          onRefresh: _handleRefresh,
          child: Column(
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
                      '${filteredDocs.length} / ${docs.length} מסמכים',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Documents list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];
                    final data = doc.data();
                    final isExpanded = _expandedDocIds.contains(doc.id);

                    return DocumentCard(
                      documentId: doc.id,
                      data: data,
                      isExpanded: isExpanded,
                      onToggle: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedDocIds.remove(doc.id);
                          } else {
                            _expandedDocIds.add(doc.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocuments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (widget.searchQuery.isEmpty) return docs;

    final query = widget.searchQuery.toLowerCase();
    return docs.where((doc) {
      // Search in document ID
      if (doc.id.toLowerCase().contains(query)) return true;

      // Search in document data
      final data = doc.data();
      return _searchInMap(data, query);
    }).toList();
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
          } else if (item is Map<String, dynamic> && _searchInMap(item, query)) {
            return true;
          }
        }
      } else if (value.toString().toLowerCase().contains(query)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _handleRefresh() async {
    setState(() {});
    // Small delay to show the refresh indicator
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
