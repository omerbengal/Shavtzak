import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_models.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_preview_dialog.dart';

void main() {
  testWidgets('renders separate share and copy-image actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EventAssignmentsSharePreviewDialog(
          data: _shareData(),
          autoStartShare: false,
        ),
      ),
    );

    expect(find.text('שתף'), findsOneWidget);
    expect(find.text('העתק תמונה'), findsOneWidget);
    expect(find.text('נסה לשתף שוב'), findsNothing);
  });
}

EventAssignmentsShareData _shareData() {
  return const EventAssignmentsShareData(
    eventName: 'טקס פתיחה',
    dateLine: 'יום שני 4 במאי',
    timeLine: 'התייצבות - 17:00',
    locationLine: 'היכל התרבות',
    sections: [
      EventAssignmentsShareSection(
        title: 'מפקד אירוע',
        rows: [
          EventAssignmentsShareRow(memberName: 'נועה כהן'),
        ],
      ),
    ],
    notes: [],
  );
}
