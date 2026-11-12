import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_card.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_models.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_fit_picture.dart';

void main() {
  group('columns follow the screen width', () {
    test('a phone gets 3, a narrow phone 2, the computer popup more', () {
      expect(EventAssignmentsFitPicture.layoutFor(342, 8).columns, 3);
      expect(EventAssignmentsFitPicture.layoutFor(280, 8).columns, 2);
      expect(EventAssignmentsFitPicture.layoutFor(596, 8).columns, 5);
    });

    test('never more columns than roles, never fewer than one', () {
      expect(EventAssignmentsFitPicture.layoutFor(596, 2).columns, 2);
      expect(EventAssignmentsFitPicture.layoutFor(80, 5).columns, 1);
      expect(EventAssignmentsFitPicture.layoutFor(342, 0).columns, 1);
    });

    test('drawn at the target scale', () {
      expect(EventAssignmentsFitPicture.layoutFor(342, 5).pictureWidth,
          342 / EventAssignmentsFitPicture.targetScale);
    });
  });

  group('the exported image is laid out for a phone', () {
    EventAssignmentsShareData data(int roles, int perRole) =>
        EventAssignmentsShareData(
          eventName: 'אירוע',
          dateLine: 'יום',
          timeLine: '',
          locationLine: '',
          sections: [
            for (var r = 0; r < roles; r++)
              EventAssignmentsShareSection(
                title: 'תפקיד $r',
                rows: [
                  for (var i = 0; i < perRole; i++)
                    EventAssignmentsShareRow(memberName: 'אדם $r-$i'),
                ],
              ),
          ],
        );

    Future<Size> pumpExport(WidgetTester tester, EventAssignmentsShareData d)
        async {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: FittedBox(child: EventAssignmentsExportPicture(data: d)),
        ),
      ));
      return tester.renderObject<RenderBox>(
              find.byType(EventAssignmentsExportPicture))
          .size;
    }

    testWidgets('as many columns as a phone gets, at phone text size',
        (tester) async {
      final size = await pumpExport(tester, data(6, 2));
      final card = tester.widget<EventAssignmentsShareCard>(
          find.byType(EventAssignmentsShareCard));
      expect(card.columns, 3);
      // 390 px phone at the 0.75 target scale.
      expect(size.width, moreOrLessEquals(520));
    });

    testWidgets('a tall event is widened to stay within a phone screen',
        (tester) async {
      final size = await pumpExport(tester, data(6, 20));
      const phone = EventAssignmentsFitPicture.exportPhone;
      expect(size.height / size.width,
          lessThanOrEqualTo(phone.height / phone.width + 0.01));
      expect(size.width, greaterThan(520));
    });
  });
}
