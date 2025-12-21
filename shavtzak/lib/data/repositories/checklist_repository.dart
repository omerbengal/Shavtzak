import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/checklist_item.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import '../../core/services/environment_service.dart';
import '../data_sources/database_interface.dart';

/// Repository for managing checklist items with real-time updates
class ChecklistRepository {
  final DatabaseInterface _database;

  ChecklistRepository(this._database);

  /// Get all checklist items (one-time)
  Future<List<ChecklistItem>> getChecklistItems() async {
    return await _database.getChecklistItems();
  }

  /// Watch all checklist items for real-time updates
  Stream<List<ChecklistItem>> watchChecklistItems() {
    return FirebaseFirestore.instance
          .collection('${_getEnvironmentPrefix()}checklistItems')
          .orderBy('updatedAt', descending: true)
          .snapshots()
          .asyncMap((snapshot) async {
        developer.log('ChecklistRepository: Processing ${snapshot.docs.length} checklist items', name: 'Checklist');

        final items = <ChecklistItem>[];

        // Get all related data once for efficiency
        final allEvents = await _database.getEvents();
        final allTeamMembers = await _database.getTeamMembers();
        final eventMap = {for (var event in allEvents) event.id: event};
        final memberMap = {for (var member in allTeamMembers) member.id: member};

        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;

          final eventId = data['eventId'] as String;
          final event = eventMap[eventId];

          final responsibleId = data['responsibleId'] as String;
          final responsible = memberMap[responsibleId];

          // Get CC members
          final ccIds = (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
          final ccMembers = ccIds
              .map((id) => memberMap[id])
              .where((member) => member != null)
              .cast<TeamMember>()
              .toList();

          final item = ChecklistItem(
            id: doc.id,
            eventId: eventId,
            name: data['name'] as String,
            responsibleId: responsibleId,
            responsibleNote: data['responsibleNote'] as String? ?? '',
            adminNote: data['adminNote'] as String? ?? '',
            ccIds: ccIds,
            ccNotes: _convertCcNotes(data['ccNotes']),
            status: data['status'] as bool,
            createdAt: (data['createdAt'] as Timestamp).toDate(),
            updatedAt: (data['updatedAt'] as Timestamp).toDate(),
            statusLastUpdatedAt: (data['statusLastUpdatedAt'] as Timestamp).toDate(),
            event: event,
            responsible: responsible,
            ccMembers: ccMembers,
          );

          items.add(item);
        }

        return items;
      })
          .handleError((error, stackTrace) {
        developer.log('Error watching checklist items: $error', name: 'Checklist', error: error, stackTrace: stackTrace);
        return <ChecklistItem>[];
      });
  }

  /// Watch checklist items for a specific event
  Stream<List<ChecklistItem>> watchChecklistItemsByEvent(String eventId) {
    return FirebaseFirestore.instance
          .collection('${_getEnvironmentPrefix()}checklistItems')
          .where('eventId', isEqualTo: eventId)
          .orderBy('name')
          .snapshots()
          .asyncMap((snapshot) async {
        developer.log('ChecklistRepository: Processing ${snapshot.docs.length} items for event $eventId', name: 'Checklist');

        final items = <ChecklistItem>[];

        // Get related data once
        final event = await _database.getEventById(eventId);
        final allTeamMembers = await _database.getTeamMembers();
        final memberMap = {for (var member in allTeamMembers) member.id: member};

        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;

          final responsibleId = data['responsibleId'] as String;
          final responsible = memberMap[responsibleId];

          // Get CC members
          final ccIds = (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
          final ccMembers = ccIds
              .map((id) => memberMap[id])
              .where((member) => member != null)
              .cast<TeamMember>()
              .toList();

          final item = ChecklistItem(
            id: doc.id,
            eventId: eventId,
            name: data['name'] as String,
            responsibleId: responsibleId,
            responsibleNote: data['responsibleNote'] as String? ?? '',
            adminNote: data['adminNote'] as String? ?? '',
            ccIds: ccIds,
            ccNotes: _convertCcNotes(data['ccNotes']),
            status: data['status'] as bool,
            createdAt: (data['createdAt'] as Timestamp).toDate(),
            updatedAt: (data['updatedAt'] as Timestamp).toDate(),
            statusLastUpdatedAt: (data['statusLastUpdatedAt'] as Timestamp).toDate(),
            event: event,
            responsible: responsible,
            ccMembers: ccMembers,
          );

          items.add(item);
        }

        return items;
      })
          .handleError((error, stackTrace) {
        developer.log('Error watching checklist items for event: $error', name: 'Checklist', error: error, stackTrace: stackTrace);
        return <ChecklistItem>[];
      });
  }

  /// Watch checklist items for a specific team member (both responsible and CC'd)
  Stream<Map<String, List<ChecklistItem>>> watchChecklistItemsForUser(String teamMemberId) {
    final collectionName = '${_getEnvironmentPrefix()}checklistItems';
    developer.log('ChecklistRepository: Starting watchChecklistItemsForUser for $teamMemberId from collection $collectionName', name: 'Checklist');

    // Get all checklist items and filter on client side (more reliable than Filter.or)
    return FirebaseFirestore.instance
        .collection(collectionName)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          developer.log('ChecklistRepository: Received snapshot with ${snapshot.docs.length} total items', name: 'Checklist');

          final responsibleItems = <ChecklistItem>[];
          final ccItems = <ChecklistItem>[];

          // Always get related data, even if no docs
          try {
            final allEvents = await _database.getEvents();
            final allTeamMembers = await _database.getTeamMembers();
            final eventMap = {for (var event in allEvents) event.id: event};
            final memberMap = {for (var member in allTeamMembers) member.id: member};

            developer.log('ChecklistRepository: Found ${allEvents.length} events and ${allTeamMembers.length} team members', name: 'Checklist');

          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;

            final eventId = data['eventId'] as String;
            final event = eventMap[eventId];

            final responsibleId = data['responsibleId'] as String;
            final responsible = memberMap[responsibleId];

            // Get CC members
            final ccIds = (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
            final ccMembers = ccIds
                .map((id) => memberMap[id])
                .where((member) => member != null)
                .cast<TeamMember>()
                .toList();

            final item = ChecklistItem(
              id: doc.id,
              eventId: eventId,
              name: data['name'] as String,
              responsibleId: responsibleId,
              responsibleNote: data['responsibleNote'] as String? ?? '',
              adminNote: data['adminNote'] as String? ?? '',
              ccIds: ccIds,
              ccNotes: _convertCcNotes(data['ccNotes']),
              status: data['status'] as bool,
              createdAt: (data['createdAt'] as Timestamp).toDate(),
              updatedAt: (data['updatedAt'] as Timestamp).toDate(),
              statusLastUpdatedAt: (data['statusLastUpdatedAt'] as Timestamp).toDate(),
              event: event,
              responsible: responsible,
              ccMembers: ccMembers,
            );

            // Categorize based on user's role
            if (responsibleId == teamMemberId) {
              responsibleItems.add(item);
            }
            if (ccIds.contains(teamMemberId)) {
              ccItems.add(item);
            }
          }

          final result = {
            'responsible': responsibleItems,
            'cc': ccItems,
          };

          developer.log('ChecklistRepository: Returning ${responsibleItems.length} responsible and ${ccItems.length} CC items for user $teamMemberId', name: 'Checklist');
          return result;
          } catch (e) {
            developer.log('Error processing checklist data: $e', name: 'Checklist', error: e);
            return {
              'responsible': <ChecklistItem>[],
              'cc': <ChecklistItem>[],
            };
          }
        })
        .handleError((error, stackTrace) {
          developer.log('Error in watchChecklistItemsForUser stream: $error', name: 'Checklist', error: error, stackTrace: stackTrace);
          // Return empty lists on error to prevent endless loading
          return {
            'responsible': <ChecklistItem>[],
            'cc': <ChecklistItem>[],
          };
        });
  }

  /// Get a single checklist item by ID
  Future<ChecklistItem?> getChecklistItemById(String id) async {
    return await _database.getChecklistItemById(id);
  }

  /// Create a new checklist item
  Future<void> createChecklistItem(ChecklistItem item) async {
    await _database.insertChecklistItem(item);
  }

  /// Update an existing checklist item
  Future<void> updateChecklistItem(ChecklistItem item) async {
    await _database.updateChecklistItem(item);
  }

  /// Delete a checklist item
  Future<void> deleteChecklistItem(String id) async {
    await _database.deleteChecklistItem(id);
  }

  /// Delete all checklist items for an event
  Future<void> deleteChecklistItemsByEvent(String eventId) async {
    await _database.deleteChecklistItemsByEvent(eventId);
  }

  /// Convert Firestore ccNotes Map to proper Map<String, CcNoteEntry>
  Map<String, CcNoteEntry> _convertCcNotes(dynamic ccNotes) {
    if (ccNotes == null) return {};

    final notesMap = ccNotes as Map;
    return notesMap.map((key, value) {
      // Handle new format: {note: String, updatedAt: Timestamp}
      if (value is Map && value.containsKey('note')) {
        final noteText = value['note']?.toString() ?? '';
        final updatedAt = value['updatedAt'] is Timestamp
            ? (value['updatedAt'] as Timestamp).toDate()
            : null;
        return MapEntry(key.toString(), CcNoteEntry(note: noteText, updatedAt: updatedAt));
      }
      // Handle old format: just a string
      return MapEntry(key.toString(), CcNoteEntry(note: value.toString(), updatedAt: null));
    });
  }

  /// Get environment prefix for collection names
  String _getEnvironmentPrefix() {
    return EnvironmentService.instance.collectionPrefix;
  }

  /// Dispose of all stream subscriptions
  void dispose() {
    // No subscriptions to cancel - emit.forEach handles them automatically
  }
}