import 'package:flutter/material.dart';

import '../../../widgets/fill_box_width.dart';
import 'event_assignments_share_card.dart';
import 'event_assignments_share_models.dart';

/// The event's assignments picture ("תמונת שיבוצים") drawn to fill the room
/// it is given, all of it at once (no scrolling): as many columns of role
/// cards as the width allows, names about 16 px, and a tall event laid out
/// wider so that, shrunk to fit the height, it still fills the width.
///
/// Used by "מי איתי באירוע?" (with [currentMemberId] and [onCall]) and the
/// דו יומי עריכה screen's assignments panel (read-only).
class EventAssignmentsFitPicture extends StatelessWidget {
  const EventAssignmentsFitPicture({
    super.key,
    required this.data,
    this.pictureKey,
    this.currentMemberId,
    this.onCall,
  });

  final EventAssignmentsShareData data;
  final Key? pictureKey;
  final String? currentMemberId;
  final void Function(EventAssignmentsShareRow row)? onCall;

  /// A column of role cards is at least this wide on screen (px).
  static const double minColumnWidth = 112;

  /// Screen px per picture unit when the picture fits: its names (21 units)
  /// come out about 16 px. It shrinks further only to fit the height.
  static const double targetScale = 0.75;

  /// For [width] px of room and [sectionCount] role cards: as many columns
  /// as fit [minColumnWidth] each (at least 1, at most one per card), and
  /// the picture's layout width that draws it at [targetScale].
  static ({int columns, double pictureWidth}) layoutFor(
    double width,
    int sectionCount,
  ) {
    final fit = (width / minColumnWidth).floor();
    final columns = fit.clamp(1, sectionCount < 1 ? 1 : sectionCount);
    return (columns: columns, pictureWidth: width / targetScale);
  }

  /// The phone screen an exported image is laid out for (logical px): it is
  /// mostly opened on a phone, full width.
  static const Size exportPhone = Size(390, 780);

  /// The exported PNG's width (px): [exportPhone] drawn at high resolution.
  static const double exportPixelWidth = 1080;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final layout = layoutFor(constraints.maxWidth, data.sections.length);
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: FillBoxWidth(
            available: constraints.biggest,
            minWidth: layout.pictureWidth,
            child: EventAssignmentsShareCard(
              key: pictureKey,
              data: data,
              width: layout.pictureWidth,
              columns: layout.columns,
              currentMemberId: currentMemberId,
              onCall: onCall,
            ),
          ),
        ),
      );
    });
  }
}

/// The exported "תמונת שיבוצים": what [EventAssignmentsFitPicture] shows on a
/// phone of [EventAssignmentsFitPicture.exportPhone] size — same columns and
/// text size — at its natural height (a short event makes a short image; a
/// tall one is laid out wider so it stays within the phone's shape). Captured
/// at [EventAssignmentsFitPicture.exportPixelWidth] px wide.
class EventAssignmentsExportPicture extends StatelessWidget {
  const EventAssignmentsExportPicture({super.key, required this.data});

  final EventAssignmentsShareData data;

  @override
  Widget build(BuildContext context) {
    const phone = EventAssignmentsFitPicture.exportPhone;
    final layout =
        EventAssignmentsFitPicture.layoutFor(phone.width, data.sections.length);
    return FillBoxWidth(
      available: phone,
      minWidth: layout.pictureWidth,
      child: EventAssignmentsShareCard(
        data: data,
        width: layout.pictureWidth,
        columns: layout.columns,
      ),
    );
  }
}
