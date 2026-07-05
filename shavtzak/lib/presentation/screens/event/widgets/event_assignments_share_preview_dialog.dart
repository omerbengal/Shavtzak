import 'package:flutter/material.dart';

import '../../../widgets/share_preview_dialog.dart';
import 'event_assignments_share_card.dart';
import 'event_assignments_share_models.dart';

/// Thin wrapper over [SharePreviewDialog] for the assignments-image share.
/// Public API is unchanged — the call site in event_assignments_dialog.dart
/// must not need any modification.
class EventAssignmentsSharePreviewDialog extends StatelessWidget {
  final EventAssignmentsShareData data;
  final bool autoStartShare;

  const EventAssignmentsSharePreviewDialog({
    super.key,
    required this.data,
    this.autoStartShare = true,
  });

  @override
  Widget build(BuildContext context) {
    return SharePreviewDialog(
      card: EventAssignmentsShareCard(data: data),
      appBarTitle: 'תמונת שיבוצים',
      filename: _buildFilename(data.eventName),
      shareTitle: 'תמונת שיבוצים',
      shareText: 'שיבוצים ל${data.eventName}',
      closeLogAction: 'tap:close:sharePreview',
      shareLogAction: 'tap:shareImage',
      copyLogAction: 'tap:copyImage',
      autoStartShare: autoStartShare,
    );
  }

  String _buildFilename(String eventName) {
    final safeName = eventName
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final suffix = safeName.isEmpty ? 'event' : safeName;
    return 'shavtzak_assignments_$suffix.png';
  }
}
