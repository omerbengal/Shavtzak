import 'dart:convert';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

/// Result of an export operation
class ExportResult {
  final bool success;
  final String? spreadsheetUrl;
  final String? error;

  const ExportResult({
    required this.success,
    this.spreadsheetUrl,
    this.error,
  });
}

/// Service that exports all production Firestore data to Google Sheets.
///
/// Reads directly from Firestore with hardcoded production collection names
/// (no environment prefix) to guarantee production data is always exported.
/// IDs are resolved to human-readable names where possible.
class ExportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Hardcoded production collection names — no environment prefix
  static const _teamMembers = 'teamMembers';
  static const _events = 'events';
  static const _assignments = 'assignments';
  static const _checklistItems = 'checklist_items';
  static const _checklistPresets = 'checklist_presets';
  static const _calendarSync = 'calendar_sync';
  static const _keys = 'keys';
  static const _utilities = 'utilities';

  /// Export all production data to a new Google Sheet (full DB export).
  Future<ExportResult> exportToSheets() async {
    final driveConfig = await _fetchLiveDriveConfig();
    if (driveConfig == null) {
      return const ExportResult(
        success: false,
        error: 'Missing Google Drive export config in keys/googleDrive',
      );
    }

    try {
      // 1. Fetch all raw documents in parallel
      final results = await Future.wait([
        _firestore.collection(_teamMembers).get(),    // 0
        _firestore.collection(_events).get(),          // 1
        _firestore.collection(_assignments).get(),     // 2
        _firestore.collection(_checklistItems).get(),  // 3
        _firestore.collection(_checklistPresets).get(),// 4
        _firestore.collection(_calendarSync).get(),    // 5
        _firestore.collection(_keys).get(),            // 6
        _firestore.collection(_utilities).doc('Lists').get(), // 7
      ]);

      final teamSnap = results[0] as QuerySnapshot;
      final eventsSnap = results[1] as QuerySnapshot;
      final assignSnap = results[2] as QuerySnapshot;
      final checklistSnap = results[3] as QuerySnapshot;
      final presetsSnap = results[4] as QuerySnapshot;
      final calSyncSnap = results[5] as QuerySnapshot;
      final keysSnap = results[6] as QuerySnapshot;
      final listsDoc = results[7] as DocumentSnapshot;

      // ── Build lookup maps ──

      // Team member id → name
      final memberNames = <String, String>{};
      for (final doc in teamSnap.docs) {
        memberNames[doc.id] = (doc.data() as Map<String, dynamic>)['name'] as String? ?? '';
      }

      // Event id → event document data (for full details)
      final eventsData = <String, Map<String, dynamic>>{};
      final eventNames = <String, String>{};
      for (final doc in eventsSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        eventsData[doc.id] = data;
        eventNames[doc.id] = data['name'] as String? ?? '';
      }

      // Role key → hebrewName
      final roleHebrewNames = <String, String>{};
      if (listsDoc.exists) {
        final listsData = listsDoc.data() as Map<String, dynamic>?;
        final roles = listsData?['Roles'] as List<dynamic>? ?? [];
        for (final r in roles) {
          final rm = r as Map<String, dynamic>;
          final key = rm['key'] as String? ?? '';
          final hebrew = rm['hebrewName'] as String? ?? key;
          if (key.isNotEmpty) roleHebrewNames[key] = hebrew;
        }
      }

      // Category id → name
      final categoryNames = <String, String>{};
      if (listsDoc.exists) {
        final listsData = listsDoc.data() as Map<String, dynamic>?;
        final categories = listsData?['Categories'] as List<dynamic>? ?? [];
        for (int i = 0; i < categories.length; i++) {
          final cm = categories[i] as Map<String, dynamic>;
          final id = cm['id'] as String? ?? '$i';
          categoryNames[id] = cm['name'] as String? ?? '';
        }
      }

      // Checklist item id → name
      final checklistNames = <String, String>{};
      for (final doc in checklistSnap.docs) {
        checklistNames[doc.id] = (doc.data() as Map<String, dynamic>)['name'] as String? ?? '';
      }

      // Preset id → name
      final presetNames = <String, String>{};
      for (final doc in presetsSnap.docs) {
        presetNames[doc.id] = (doc.data() as Map<String, dynamic>)['name'] as String? ?? '';
      }

      // ── Serialize each collection into sheets ──
      final sheets = <Map<String, dynamic>>[];

      sheets.add(_serializeTeamMembers(teamSnap, eventsData, roleHebrewNames));
      sheets.add(_serializeConstraints(teamSnap, memberNames));
      sheets.add(_serializeEvents(eventsSnap, memberNames, categoryNames, roleHebrewNames));
      sheets.add(_serializeAssignments(assignSnap, eventsData, memberNames, roleHebrewNames));
      sheets.add(_serializeChecklistItems(checklistSnap, eventsData, memberNames));
      sheets.add(_serializeChecklistNotes(checklistSnap, checklistNames, memberNames));
      sheets.add(_serializePresets(presetsSnap));
      sheets.add(_serializePresetItems(presetsSnap, presetNames, memberNames));
      sheets.add(_serializeCalendarSync(calSyncSnap));
      sheets.add(_serializeKeys(keysSnap));
      sheets.add(_serializeRoles(listsDoc));
      sheets.add(_serializeCategories(listsDoc));
      sheets.add(_serializeMetadata(
        teamCount: teamSnap.docs.length,
        eventCount: eventsSnap.docs.length,
        assignmentCount: assignSnap.docs.length,
        checklistCount: checklistSnap.docs.length,
        presetCount: presetsSnap.docs.length,
        calSyncCount: calSyncSnap.docs.length,
        keysCount: keysSnap.docs.length,
      ));

      // 3. Build payload and POST to Apps Script
      final payload = {
        'action': 'exportToSheets',
        'apiKey': driveConfig.apiKey,
        'exportData': {
          'sheets': sheets,
        },
      };

      final response = await http.post(
        Uri.parse(driveConfig.scriptUrl),
        headers: {'Content-Type': 'text/plain;charset=UTF-8'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['success'] == true) {
          return ExportResult(
            success: true,
            spreadsheetUrl: body['spreadsheetUrl'] as String?,
          );
        } else {
          return ExportResult(
            success: false,
            error: body['error'] as String? ?? 'Unknown Apps Script error',
          );
        }
      } else {
        return ExportResult(
          success: false,
          error: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      developer.log('ExportService: Export failed: $e', name: 'Export', error: e);
      return ExportResult(success: false, error: e.toString());
    }
  }

  /// Export only assignments to a new Google Sheet (simplified export).
  Future<ExportResult> exportAssignmentsOnly() async {
    final driveConfig = await _fetchLiveDriveConfig();
    if (driveConfig == null) {
      return const ExportResult(
        success: false,
        error: 'Missing Google Drive export config in keys/googleDrive',
      );
    }

    try {
      // Fetch only needed collections
      final results = await Future.wait([
        _firestore.collection(_assignments).get(),
        _firestore.collection(_events).get(),
        _firestore.collection(_teamMembers).get(),
        _firestore.collection(_utilities).doc('Lists').get(),
      ]);

      final assignSnap = results[0] as QuerySnapshot;
      final eventsSnap = results[1] as QuerySnapshot;
      final teamSnap = results[2] as QuerySnapshot;
      final listsDoc = results[3] as DocumentSnapshot;

      // Build lookup maps
      final memberNames = <String, String>{};
      for (final doc in teamSnap.docs) {
        memberNames[doc.id] = (doc.data() as Map<String, dynamic>)['name'] as String? ?? '';
      }

      final eventsData = <String, Map<String, dynamic>>{};
      for (final doc in eventsSnap.docs) {
        eventsData[doc.id] = doc.data() as Map<String, dynamic>;
      }

      final roleHebrewNames = <String, String>{};
      if (listsDoc.exists) {
        final listsData = listsDoc.data() as Map<String, dynamic>?;
        final roles = listsData?['Roles'] as List<dynamic>? ?? [];
        for (final r in roles) {
          final rm = r as Map<String, dynamic>;
          final key = rm['key'] as String? ?? '';
          final hebrew = rm['hebrewName'] as String? ?? key;
          if (key.isNotEmpty) roleHebrewNames[key] = hebrew;
        }
      }

      // Serialize
      final sheet = _serializeAssignmentsOnly(assignSnap, eventsData, memberNames, roleHebrewNames);

      // Build payload
      final payload = {
        'action': 'exportAssignmentsOnly',
        'apiKey': driveConfig.apiKey,
        'exportData': {'sheets': [sheet]},
      };

      final response = await http.post(
        Uri.parse(driveConfig.scriptUrl),
        headers: {'Content-Type': 'text/plain;charset=UTF-8'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['success'] == true) {
          return ExportResult(
            success: true,
            spreadsheetUrl: body['spreadsheetUrl'] as String?,
          );
        } else {
          return ExportResult(
            success: false,
            error: body['error'] as String? ?? 'Unknown Apps Script error',
          );
        }
      } else {
        return ExportResult(
          success: false,
          error: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      developer.log('ExportService: Assignments export failed: $e', name: 'Export', error: e);
      return ExportResult(success: false, error: e.toString());
    }
  }

  /// Always read the latest Google Drive export config from Firestore.
  Future<_DriveExportConfig?> _fetchLiveDriveConfig() async {
    try {
      final doc = await _firestore.collection(_keys).doc('googleDrive').get();
      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      final scriptUrl = (data['scriptUrl'] as String?)?.trim();
      final apiKey = (data['apiKey'] as String?)?.trim();

      if (scriptUrl == null ||
          scriptUrl.isEmpty ||
          apiKey == null ||
          apiKey.isEmpty) {
        return null;
      }

      return _DriveExportConfig(
        scriptUrl: scriptUrl,
        apiKey: apiKey,
      );
    } catch (e) {
      developer.log(
        'ExportService: Failed to fetch drive config: $e',
        name: 'Export',
        error: e,
      );
      return null;
    }
  }

  // ───────────────────────── Serializers ─────────────────────────

  /// Sheet 1: חברי צוות
  Map<String, dynamic> _serializeTeamMembers(
    QuerySnapshot snap,
    Map<String, Map<String, dynamic>> eventsData,
    Map<String, String> roleHebrewNames,
  ) {
    final headers = [
      'id', 'name', 'isActive', 'isPermanent', 'isArchived', 'comments',
      'uniqueKey', 'isAdmin', 'passcode', 'passcodeLength',
      'allowMultipleAssignments', 'phoneNumber', 'birthday',
      'canAccessSummaryScreen', 'vehicleNumber', 'vehicleManufacturer',
      'vehicleModel', 'vehicleColor', 'availableEvents',
      'roleCapabilities', 'createdAt', 'updatedAt',
    ];

    // passcode is col index 8, vehicleNumber is col index 14
    final textColumns = [8, 14];

    final rows = <List<dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final vehicle = d['vehicleInfo'] as Map<String, dynamic>?;
      rows.add([
        doc.id,
        d['name'] ?? '',
        d['isActive'] ?? true,
        d['isPermanent'] ?? false,
        d['isArchived'] ?? false,
        d['comments'] ?? '',
        d['uniqueKey'] ?? '',
        d['isAdmin'] ?? false,
        d['passcode'] ?? '',
        d['passcodeLength'],
        d['allowMultipleAssignments'] ?? false,
        d['phoneNumber'] ?? '',
        _formatDate(d['birthday']),
        d['canAccessSummaryScreen'] ?? false,
        vehicle?['vehicleNumber'] ?? '',
        vehicle?['manufacturer'] ?? '',
        vehicle?['model'] ?? '',
        vehicle?['color'] ?? '',
        _formatAvailableEvents(d['availableEventIds'], eventsData),
        _roleCapabilitiesToHebrew(d['roleCapabilities'], roleHebrewNames),
        _ts(d['createdAt']),
        _ts(d['updatedAt']),
      ]);
    }

    return {
      'sheetName': 'חברי צוות',
      'headers': headers,
      'rows': rows,
      'textColumns': textColumns,
    };
  }

  /// Sheet 2: מגבלות חברי צוות
  Map<String, dynamic> _serializeConstraints(
    QuerySnapshot snap,
    Map<String, String> memberNames,
  ) {
    final headers = [
      'teamMemberId', 'teamMemberName', 'constraintId', 'startDate',
      'endDate', 'startTime', 'endTime', 'note', 'status',
      'constraintType', 'wasAutoRejectedFromCalendar',
    ];

    final rows = <List<dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final constraints = d['constraints'] as List<dynamic>? ?? [];
      for (final c in constraints) {
        final cm = c as Map<String, dynamic>;
        rows.add([
          doc.id,
          memberNames[doc.id] ?? '',
          cm['id'] ?? '',
          _formatDate(cm['startDate']),
          _formatDate(cm['endDate']),
          cm['startTime'] ?? '',
          cm['endTime'] ?? '',
          cm['note'] ?? '',
          cm['status'] ?? '',
          cm['constraintType'] ?? '',
          cm['wasAutoRejectedFromCalendar'] ?? false,
        ]);
      }
    }

    return {'sheetName': 'מגבלות חברי צוות', 'headers': headers, 'rows': rows};
  }

  /// Sheet 3: אירועים
  Map<String, dynamic> _serializeEvents(
    QuerySnapshot snap,
    Map<String, String> memberNames,
    Map<String, String> categoryNames,
    Map<String, String> roleHebrewNames,
  ) {
    final headers = [
      'id', 'name', 'startDate', 'endDate', 'startTime', 'endTime',
      'assemblyTime', 'actualShowStartTime', 'location', 'parkingLocation',
      'parkingEditors', 'requiresArmed', 'comments', 'category',
      'roleRequirements', 'driveFolderId', 'driveFolderLink',
      'isArchived', 'relevantForExtendedTeam', 'createdAt', 'updatedAt',
    ];

    final rows = <List<dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      rows.add([
        doc.id,
        d['name'] ?? '',
        _formatDate(d['startDate']),
        _formatDate(d['endDate']),
        d['startTime'] ?? '',
        d['endTime'] ?? '',
        d['assemblyTime'] ?? '',
        d['actualShowStartTime'] ?? '',
        d['location'] ?? '',
        d['parkingLocation'] ?? '',
        _idsToNames(d['parkingEditorIds'], memberNames),
        d['requiresArmed'] ?? false,
        d['comments'] ?? d['notes'] ?? '',
        categoryNames[d['categoryId']] ?? '',
        _roleRequirementsToHebrew(d['roleRequirements'], roleHebrewNames),
        d['driveFolderId'] ?? '',
        d['driveFolderLink'] ?? '',
        d['isArchived'] ?? false,
        d['relevantForExtendedTeam'] ?? false,
        _ts(d['createdAt']),
        _ts(d['updatedAt']),
      ]);
    }

    return {'sheetName': 'אירועים', 'headers': headers, 'rows': rows};
  }

  /// Sheet 4: שיבוצים
  Map<String, dynamic> _serializeAssignments(
    QuerySnapshot snap,
    Map<String, Map<String, dynamic>> eventsData,
    Map<String, String> memberNames,
    Map<String, String> roleHebrewNames,
  ) {
    final headers = [
      'id', 'event', 'eventStartDate', 'eventEndDate', 'eventStartTime', 'eventEndTime',
      'teamMember', 'roleType', 'slotIndex',
      'status', 'notes', 'alternativePhoneNumber', 'createdAt', 'updatedAt',
    ];

    final rows = <List<dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final eventId = d['eventId'] as String? ?? '';
      final eventData = eventsData[eventId];
      final eventName = eventData?['name'] as String? ?? eventId;

      final roleKey = d['roleType'] as String? ?? '';
      rows.add([
        doc.id,
        eventName,
        _formatDate(eventData?['startDate']),
        _formatDate(eventData?['endDate']),
        eventData?['startTime'] ?? '',
        eventData?['endTime'] ?? '',
        memberNames[d['teamMemberId']] ?? d['teamMemberId'] ?? '',
        roleHebrewNames[roleKey] ?? roleKey,
        d['slotIndex'] ?? 0,
        d['status'] ?? '',
        d['notes'] ?? '',
        d['alternativePhoneNumber'] ?? '',
        _ts(d['createdAt']),
        _ts(d['updatedAt']),
      ]);
    }

    return {'sheetName': 'שיבוצים', 'headers': headers, 'rows': rows};
  }

  /// Sheet 5: צ'קליסט
  Map<String, dynamic> _serializeChecklistItems(
    QuerySnapshot snap,
    Map<String, Map<String, dynamic>> eventsData,
    Map<String, String> memberNames,
  ) {
    final headers = [
      'id', 'event', 'name', 'responsible', 'CCs', 'status',
      'createdByAdmin', 'createdAt', 'updatedAt', 'statusLastUpdatedAt',
    ];

    final rows = <List<dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final eventId = d['eventId'] as String? ?? '';
      final eventData = eventsData[eventId];
      rows.add([
        doc.id,
        eventData?['name'] as String? ?? eventId,
        d['name'] ?? '',
        memberNames[d['responsibleId']] ?? d['responsibleId'] ?? '',
        _idsToNames(d['ccIds'], memberNames),
        d['status'] ?? false,
        memberNames[d['createdByAdminId']] ?? d['createdByAdminId'] ?? '',
        _ts(d['createdAt']),
        _ts(d['updatedAt']),
        _ts(d['statusLastUpdatedAt']),
      ]);
    }

    return {'sheetName': 'צ\'קליסט', 'headers': headers, 'rows': rows};
  }

  /// Sheet 6: הערות צ'קליסט
  Map<String, dynamic> _serializeChecklistNotes(
    QuerySnapshot snap,
    Map<String, String> checklistNames,
    Map<String, String> memberNames,
  ) {
    final headers = [
      'checklistItemId', 'checklistItemName', 'noteId', 'content',
      'createdByTeamMemberId', 'createdByTeamMemberName', 'authorRole',
      'createdAt',
    ];

    final rows = <List<dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final notes = d['notes'] as List<dynamic>? ?? [];
      for (final n in notes) {
        final nm = n as Map<String, dynamic>;
        rows.add([
          doc.id,
          checklistNames[doc.id] ?? '',
          nm['id'] ?? '',
          nm['content'] ?? '',
          nm['createdByTeamMemberId'] ?? '',
          nm['createdByTeamMemberName'] ?? memberNames[nm['createdByTeamMemberId']] ?? '',
          nm['authorRole'] ?? '',
          _ts(nm['createdAt']),
        ]);
      }
    }

    return {'sheetName': 'הערות צ\'קליסט', 'headers': headers, 'rows': rows};
  }

  /// Sheet 7: תבניות צ'קליסט
  Map<String, dynamic> _serializePresets(QuerySnapshot snap) {
    final headers = ['id', 'name', 'itemCount', 'createdAt', 'updatedAt'];

    final rows = <List<dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final items = d['items'] as List<dynamic>? ?? [];
      rows.add([
        doc.id,
        d['name'] ?? '',
        items.length,
        _ts(d['createdAt']),
        _ts(d['updatedAt']),
      ]);
    }

    return {'sheetName': 'תבניות צ\'קליסט', 'headers': headers, 'rows': rows};
  }

  /// Sheet 8: פריטי תבניות
  Map<String, dynamic> _serializePresetItems(
    QuerySnapshot snap,
    Map<String, String> presetNames,
    Map<String, String> memberNames,
  ) {
    final headers = [
      'presetId', 'presetName', 'itemName', 'responsible',
      'CCs', 'adminNote',
    ];

    final rows = <List<dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final items = d['items'] as List<dynamic>? ?? [];
      for (final item in items) {
        final im = item as Map<String, dynamic>;
        rows.add([
          doc.id,
          presetNames[doc.id] ?? '',
          im['name'] ?? '',
          memberNames[im['responsibleId']] ?? im['responsibleId'] ?? '',
          _idsToNames(im['ccIds'], memberNames),
          im['adminNote'] ?? '',
        ]);
      }
    }

    return {'sheetName': 'פריטי תבניות', 'headers': headers, 'rows': rows};
  }

  /// Sheet 9: סנכרון יומן
  Map<String, dynamic> _serializeCalendarSync(QuerySnapshot snap) {
    final headers = [
      'constraintId', 'calendarEventId', 'teamMemberId', 'status',
      'syncedAt', 'updatedAt', 'retryCount', 'errorMessage',
    ];

    final rows = <List<dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      rows.add([
        doc.id,
        d['calendarEventId'] ?? '',
        d['teamMemberId'] ?? '',
        d['status'] ?? '',
        _ts(d['syncedAt']),
        _ts(d['updatedAt']),
        d['retryCount'] ?? 0,
        d['errorMessage'] ?? '',
      ]);
    }

    return {'sheetName': 'סנכרון יומן', 'headers': headers, 'rows': rows};
  }

  /// Sheet 10: מפתחות (vertical key-value layout)
  Map<String, dynamic> _serializeKeys(QuerySnapshot snap) {
    final headers = ['documentId', 'field', 'value'];

    final rows = <List<dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      for (final entry in d.entries) {
        rows.add([
          doc.id,
          entry.key,
          entry.value is Map || entry.value is List
              ? _jsonEncode(entry.value)
              : entry.value?.toString() ?? '',
        ]);
      }
    }

    return {'sheetName': 'מפתחות', 'headers': headers, 'rows': rows};
  }

  /// Sheet 11: תפקידים
  Map<String, dynamic> _serializeRoles(DocumentSnapshot listsDoc) {
    final headers = [
      'id', 'key', 'hebrewName', 'isVisible', 'isArchived',
      'sortOrder', 'createdAt', 'updatedAt',
    ];

    final rows = <List<dynamic>>[];
    if (listsDoc.exists) {
      final data = listsDoc.data() as Map<String, dynamic>?;
      final roles = data?['Roles'] as List<dynamic>? ?? [];
      for (final r in roles) {
        final rm = r as Map<String, dynamic>;
        rows.add([
          rm['id'] ?? rm['key'] ?? '',
          rm['key'] ?? '',
          rm['hebrewName'] ?? '',
          rm['isVisible'] ?? true,
          rm['isArchived'] ?? false,
          rm['sortOrder'] ?? 0,
          _ts(rm['createdAt']),
          _ts(rm['updatedAt']),
        ]);
      }
    }

    return {'sheetName': 'תפקידים', 'headers': headers, 'rows': rows};
  }

  /// Sheet 12: קטגוריות
  Map<String, dynamic> _serializeCategories(DocumentSnapshot listsDoc) {
    final headers = [
      'id', 'name', 'sortOrder', 'isArchived', 'createdAt', 'updatedAt',
    ];

    final rows = <List<dynamic>>[];
    if (listsDoc.exists) {
      final data = listsDoc.data() as Map<String, dynamic>?;
      final categories = data?['Categories'] as List<dynamic>? ?? [];
      for (int i = 0; i < categories.length; i++) {
        final cm = categories[i] as Map<String, dynamic>;
        rows.add([
          cm['id'] ?? '$i',
          cm['name'] ?? '',
          cm['sortOrder'] ?? i,
          cm['isArchived'] ?? false,
          _ts(cm['createdAt']),
          _ts(cm['updatedAt']),
        ]);
      }
    }

    return {'sheetName': 'קטגוריות', 'headers': headers, 'rows': rows};
  }

  /// Sheet 13: _metadata
  Map<String, dynamic> _serializeMetadata({
    required int teamCount,
    required int eventCount,
    required int assignmentCount,
    required int checklistCount,
    required int presetCount,
    required int calSyncCount,
    required int keysCount,
  }) {
    final headers = ['key', 'value'];
    final rows = <List<dynamic>>[
      ['exportedAt', DateTime.now().toIso8601String()],
      ['teamMembers', teamCount],
      ['events', eventCount],
      ['assignments', assignmentCount],
      ['checklist_items', checklistCount],
      ['checklist_presets', presetCount],
      ['calendar_sync', calSyncCount],
      ['keys', keysCount],
    ];

    return {'sheetName': '_metadata', 'headers': headers, 'rows': rows};
  }

  // ───────────────────────── Helpers ─────────────────────────

  /// Convert a Firestore Timestamp to ISO 8601 string (for timestamps).
  String _ts(dynamic value) {
    if (value == null) return '';
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is String) return value;
    return value.toString();
  }

  /// Convert a Firestore Timestamp to DD/MM/YYYY string (for date-only fields).
  String _formatDate(dynamic value) {
    if (value == null) return '';
    DateTime dt;
    if (value is Timestamp) {
      dt = value.toDate();
    } else if (value is DateTime) {
      dt = value;
    } else if (value is String && value.isNotEmpty) {
      dt = DateTime.tryParse(value) ?? (throw FormatException('Bad date: $value'));
    } else {
      return '';
    }
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$m/$y';
  }

  /// Encode a value to JSON string for cells that hold arrays/maps.
  String _jsonEncode(dynamic value) {
    if (value == null) return '';
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  /// Convert a list of IDs to a comma-separated string of names.
  String _idsToNames(dynamic ids, Map<String, String> lookup) {
    if (ids == null) return '';
    if (ids is! List) return '';
    final names = <String>[];
    for (final id in ids) {
      final idStr = id.toString();
      names.add(lookup[idStr] ?? idStr);
    }
    return names.join(', ');
  }

  /// Convert roleCapabilities map to newline-separated Hebrew names (true roles only).
  String _roleCapabilitiesToHebrew(
    dynamic capabilities,
    Map<String, String> roleHebrewNames,
  ) {
    if (capabilities == null || capabilities is! Map) return '';
    final names = <String>[];
    for (final entry in capabilities.entries) {
      if (entry.value == true) {
        final key = entry.key.toString();
        names.add(roleHebrewNames[key] ?? key);
      }
    }
    // Use placeholder that will be replaced with newline in Apps Script
    return names.join('<<<NEWLINE>>>');
  }

  /// Convert roleRequirements map to "hebrewName: count" format.
  String _roleRequirementsToHebrew(
    dynamic requirements,
    Map<String, String> roleHebrewNames,
  ) {
    if (requirements == null || requirements is! Map) return '';
    final parts = <String>[];
    for (final entry in requirements.entries) {
      final key = entry.key.toString();
      final hebrew = roleHebrewNames[key] ?? key;
      parts.add('$hebrew: ${entry.value}');
    }
    return parts.join(', ');
  }

  /// Format event IDs as "<event name> (dates and times)" for availableEvents.
  String _formatAvailableEvents(
    dynamic eventIds,
    Map<String, Map<String, dynamic>> eventsData,
  ) {
    if (eventIds == null || eventIds is! List) return '';
    if (eventIds.isEmpty) return '';

    final parts = <String>[];
    for (final id in eventIds) {
      final idStr = id.toString();
      final eventData = eventsData[idStr];
      if (eventData != null) {
        final name = eventData['name'] as String? ?? idStr;
        final dateRange = _formatEventDateTimeRange(eventData);
        parts.add('$name ($dateRange)');
      } else {
        parts.add(idStr);
      }
    }
    // Use placeholder that will be replaced with newline in Apps Script
    return parts.join('<<<NEWLINE>>>');
  }

  /// Format an event's date/time range as "DD/MM/YYYY HH:mm - DD/MM/YYYY HH:mm".
  String _formatEventDateTimeRange(Map<String, dynamic> eventData) {
    final startDate = _formatDate(eventData['startDate']);
    final startTime = eventData['startTime'] as String? ?? '';
    final endDate = _formatDate(eventData['endDate']);
    final endTime = eventData['endTime'] as String? ?? '';

    // If single day, show as "DD/MM/YYYY HH:mm - HH:mm"
    if (startDate == endDate) {
      if (startTime.isNotEmpty && endTime.isNotEmpty) {
        return '$startDate $startTime - $endTime';
      } else if (startTime.isNotEmpty) {
        return '$startDate $startTime';
      } else {
        return startDate;
      }
    }

    // Multi-day event: "DD/MM/YYYY HH:mm - DD/MM/YYYY HH:mm"
    final start = startTime.isNotEmpty ? '$startDate $startTime' : startDate;
    final end = endTime.isNotEmpty ? '$endDate $endTime' : endDate;
    return '$start - $end';
  }

  /// Sheet: שיבוצים (assignments-only export)
  Map<String, dynamic> _serializeAssignmentsOnly(
    QuerySnapshot snap,
    Map<String, Map<String, dynamic>> eventsData,
    Map<String, String> memberNames,
    Map<String, String> roleHebrewNames,
  ) {
    // Hebrew headers for this export
    final headers = [
      'שם חבר צוות',         // teamMember
      'תפקיד',                // roleType
      'אירוע',                 // event
      'תאריך תחילת אירוע', // eventStartDate
      'תאריך סיום',             // eventEndDate
      'שעת התייצבות',          // assemblyTime
      'שעת תחילת אירוע',     // eventStartTime
      'שעת סיום אירוע',         // eventEndTime
      'מיקום',                 // location
      'הערות שיבוץ',           // notes
    ];

    // Collect all assignments for sorting
    final assignments = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final eventId = d['eventId'] as String? ?? '';
      final eventData = eventsData[eventId];

      if (eventData == null) {
        continue; // Skip assignments with missing event data
      }

      // Clean location: remove "||" separator and coordinates
      String location = _cleanLocation(eventData['location']);

      // Format dates - column D always shows start date
      // Column E shows end date ONLY for multi-day events
      final startDate = _parseDate(eventData['startDate']);
      final endDate = _parseDate(eventData['endDate']);
      final isSingleDay = startDate != null && endDate != null &&
          _isSameDay(startDate, endDate);

      assignments.add({
        'teamMember': memberNames[d['teamMemberId']] ?? '',
        'roleType': roleHebrewNames[d['roleType']] ?? '',
        'roleTypeKey': d['roleType'] as String? ?? '', // For sorting
        'event': eventData['name'] as String? ?? '',
        'eventStartDate': _formatDate(eventData['startDate']), // Always show start date in column D
        'eventEndDate': isSingleDay ? '' : _formatDate(eventData['endDate']), // Column E empty for single-day
        'eventStartDateObj': eventData['startDate'], // For sorting
        'eventStartTime': eventData['startTime'] as String? ?? '',
        'eventEndTime': eventData['endTime'] as String? ?? '',
        'location': location,
        'assemblyTime': eventData['assemblyTime'] as String? ?? '',
        'notes': d['notes'] ?? '',
        'teamMemberId': d['teamMemberId'] as String? ?? '', // For sorting
      });
    }

    // Sort by: team member name (asc), event start date (asc), event start time (asc), role (asc)
    assignments.sort((a, b) {
      // 1. Team member name (alphabetically)
      final memberCompare = (a['teamMember'] as String).compareTo(b['teamMember'] as String);
      if (memberCompare != 0) return memberCompare;

      // 2. Event start date (ascending)
      final aStart = a['eventStartDateObj'];
      final bStart = b['eventStartDateObj'];
      if (aStart != null && bStart != null) {
        final aDate = aStart is Timestamp ? aStart.toDate() : (aStart is DateTime ? aStart : null);
        final bDate = bStart is Timestamp ? bStart.toDate() : (bStart is DateTime ? bStart : null);
        if (aDate != null && bDate != null) {
          final dateCompare = aDate.compareTo(bDate);
          if (dateCompare != 0) return dateCompare;
        }
      } else if (aStart != null) {
        return -1;
      } else if (bStart != null) {
        return 1;
      }

      // 3. Event start time (ascending)
      final aTime = a['eventStartTime'] as String;
      final bTime = b['eventStartTime'] as String;
      if (aTime.isNotEmpty && bTime.isNotEmpty) {
        final timeCompare = aTime.compareTo(bTime);
        if (timeCompare != 0) return timeCompare;
      } else if (aTime.isNotEmpty) {
        return -1;
      } else if (bTime.isNotEmpty) {
        return 1;
      }

      // 4. Role (alphabetically)
      return (a['roleType'] as String).compareTo(b['roleType'] as String);
    });

    // Convert sorted assignments to rows
    final rows = <List<dynamic>>[];
    for (final assignment in assignments) {
      rows.add([
        assignment['teamMember'],
        assignment['roleType'],
        assignment['event'],
        assignment['eventStartDate'],  // Always shows start date (for single-day: the date, for multi-day: start date)
        assignment['eventEndDate'],    // Empty for single-day events, end date for multi-day
        assignment['assemblyTime'],
        assignment['eventStartTime'],
        assignment['eventEndTime'],
        assignment['location'],
        assignment['notes'],
      ]);
    }

    return {
      'sheetName': 'שיבוצים',
      'headers': headers,
      'rows': rows,
      'colorByTeamMember': true, // Flag for Apps Script to color rows by team member (using column 0)
    };
  }

  /// Parse date from Timestamp, DateTime, or String
  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  /// Check if two dates fall on the same day (ignoring time)
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  /// Clean location string: remove "||" separator and GPS coordinates
  String _cleanLocation(dynamic location) {
    if (location == null || location is! String) return '';

    String loc = location as String;

    // Remove "||" separator - keep only the first part
    if (loc.contains('||')) {
      loc = loc.split('||')[0].trim();
    }

    // Remove GPS coordinates pattern like (31.1234, 34.5678) or [31.1234, 34.5678]
    // Matches: optional opening bracket/paren, digits.digits, comma, digits.digits, optional closing
    loc = loc.replaceAll(RegExp(r'[\(\[]?\d+\.\d+,\s*\d+\.\d+[\)\]]?'), '');

    return loc.trim();
  }
}

class _DriveExportConfig {
  final String scriptUrl;
  final String apiKey;

  const _DriveExportConfig({
    required this.scriptUrl,
    required this.apiKey,
  });
}
