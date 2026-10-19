import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/member_picker_field.dart';

TeamMember _member(String id, String name) => TeamMember(
      id: id,
      name: name,
      isActive: true,
      isPermanent: false,
      constraints: const [],
      roleCapabilities: const {},
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
      uniqueKey: 'key-$id',
    );

void main() {
  final members = [
    _member('m1', 'דנה כהן'),
    _member('m2', 'יוסי לוי'),
    _member('m3', 'דני אברהם'),
  ];

  Future<List<String>> pump(WidgetTester tester, {TeamMember? selected}) async {
    final picked = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 140,
              child: MemberPickerField(
                selected: selected,
                members: members,
                enabled: true,
                backgroundColor: Colors.white,
                actions: const [
                  MemberPickerAction(
                    value: '__show_already_assigned__',
                    label: 'שובצו כבר',
                    icon: Icons.people,
                    color: Colors.orange,
                  ),
                ],
                onSelected: picked.add,
              ),
            ),
          ),
        ),
      ),
    ));
    return picked;
  }

  testWidgets('opens with the search bar unfocused', (tester) async {
    await pump(tester);
    await tester.tap(find.text('בחר...'));
    await tester.pumpAndSettle();

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isFalse);
    expect(find.text('יוסי לוי'), findsOneWidget);
    expect(find.text('שובצו כבר'), findsOneWidget);
  });

  testWidgets('search narrows the members but keeps the actions',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('בחר...'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'דנ');
    await tester.pumpAndSettle();

    expect(find.text('דנה כהן'), findsOneWidget);
    expect(find.text('דני אברהם'), findsOneWidget);
    expect(find.text('יוסי לוי'), findsNothing);
    expect(find.text('שובצו כבר'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zz');
    await tester.pumpAndSettle();
    expect(find.text('לא נמצאו חברי צוות'), findsOneWidget);
  });

  testWidgets('picking a member or an action reports its value',
      (tester) async {
    final picked = await pump(tester, selected: members[1]);
    expect(find.text('יוסי לוי'), findsOneWidget);

    await tester.tap(find.text('יוסי לוי'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('דנה כהן'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('יוסי לוי'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('שובצו כבר'));
    await tester.pumpAndSettle();

    expect(picked, ['m1', '__show_already_assigned__']);
  });

  testWidgets('tapping outside closes without picking', (tester) async {
    final picked = await pump(tester);
    await tester.tap(find.text('בחר...'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(picked, isEmpty);
  });
}
