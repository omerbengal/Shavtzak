import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../widgets/share_preview_dialog.dart';
import 'calendar_share_card.dart';
import 'calendar_share_models.dart';

/// Thin wrapper over [SharePreviewDialog] for the events-calendar share.
class CalendarSharePreviewDialog extends StatelessWidget {
  final CalendarShareData data;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final bool autoStartShare;

  const CalendarSharePreviewDialog({
    super.key,
    required this.data,
    required this.rangeStart,
    required this.rangeEnd,
    this.autoStartShare = true,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('yyyy-MM-dd');
    return SharePreviewDialog(
      card: CalendarShareCard(data: data),
      appBarTitle: 'לוח אירועים',
      filename: 'shavtzak_events_calendar_'
          '${formatter.format(rangeStart)}_'
          '${formatter.format(rangeEnd)}.png',
      shareTitle: 'לוח אירועים',
      shareText: 'לוח אירועים ${data.rangeTitle}',
      closeLogAction: 'tap:close:calendarSharePreview',
      shareLogAction: 'tap:shareCalendarImage',
      copyLogAction: 'tap:copyCalendarImage',
      autoStartShare: autoStartShare,
    );
  }
}
