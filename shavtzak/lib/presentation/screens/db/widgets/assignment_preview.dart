import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/services/environment_service.dart';
import '../../../../core/constants/role_types.dart';

/// Widget that displays assignment preview with fetched names
/// Shows: "Team Member Name | Role Name | Event Name"
class AssignmentPreview extends StatefulWidget {
  final Map<String, dynamic> data;
  final Map<String, Map<String, Map<String, dynamic>>>? collectionsData;

  const AssignmentPreview({
    super.key,
    required this.data,
    this.collectionsData,
  });

  @override
  State<AssignmentPreview> createState() => _AssignmentPreviewState();
}

class _AssignmentPreviewState extends State<AssignmentPreview> {
  String? _teamMemberName;
  String? _eventName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchNames();
  }

  Future<void> _fetchNames() async {
    // Use cached data if available (faster, no Firestore queries)
    if (widget.collectionsData != null) {
      // Get team member name
      final teamMemberId = widget.data['teamMemberId'] as String?;
      if (teamMemberId != null) {
        final membersData = widget.collectionsData!['teamMembers'];
        if (membersData != null) {
          final member = membersData[teamMemberId];
          if (member != null && member['name'] != null) {
            _teamMemberName = member['name'] as String;
          }
        }
      }

      // Fetch event name
      final eventId = widget.data['eventId'] as String?;
      if (eventId != null) {
        final eventsData = widget.collectionsData!['events'];
        if (eventsData != null) {
          final event = eventsData[eventId];
          if (event != null && event['name'] != null) {
            _eventName = event['name'] as String;
          }
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    // Fallback: Fetch from Firestore if cache not available
    final prefix = EnvironmentService.instance.collectionPrefix;

    // Fetch team member name
    final teamMemberId = widget.data['teamMemberId'] as String?;
    if (teamMemberId != null) {
      try {
        final memberDoc = await FirebaseFirestore.instance
            .collection('${prefix}teamMembers')
            .doc(teamMemberId)
            .get();
        if (memberDoc.exists) {
          final memberData = memberDoc.data() as Map<String, dynamic>;
          _teamMemberName = memberData['name'] as String?;
        }
      } catch (_) {
        // Ignore fetch errors
      }
    }

    // Fetch event name
    final eventId = widget.data['eventId'] as String?;
    if (eventId != null) {
      try {
        final eventDoc = await FirebaseFirestore.instance
            .collection('${prefix}events')
            .doc(eventId)
            .get();
        if (eventDoc.exists) {
          final eventData = eventDoc.data() as Map<String, dynamic>;
          _eventName = eventData['name'] as String?;
        }
      } catch (_) {
        // Ignore fetch errors
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Text(
        'טוען...',
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey.shade600,
        ),
      );
    }

    final memberName = _teamMemberName ?? 'חבר צוות לא ידוע';
    final eventName = _eventName ?? 'אירוע לא ידוע';

    // Get role name in Hebrew
    final roleType = widget.data['roleType'] as String?;
    String roleName = 'לא ידוע';
    if (roleType != null) {
      try {
        roleName = RoleTypeExtension.fromString(roleType).hebrewName;
      } catch (_) {
        roleName = roleType;
      }
    }

    return Text(
      '$memberName | $roleName | $eventName',
      style: TextStyle(
        fontSize: 14,
        color: Colors.grey.shade800,
      ),
    );
  }
}
