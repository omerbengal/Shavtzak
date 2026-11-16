import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/admin/widgets/reorderable_home_cards.dart';

const _ids = ['a', 'b', 'c', 'd', 'e'];

Future<List<List<String>>> _pump(
  WidgetTester tester, {
  int columns = 1,
  List<String>? tapsOut,
}) async {
  final saved = <List<String>>[];
  await tester.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: ReorderableHomeCards(
            order: _ids,
            columns: columns,
            spacing: 16,
            cardBuilder: (context, id) => SizedBox(
              key: Key('card-$id'),
              width: 200,
              height: 100,
              child: Card(
                child: InkWell(
                  onTap: () => tapsOut?.add(id),
                  child: Center(child: Text(id)),
                ),
              ),
            ),
            onReorder: saved.add,
          ),
        ),
      ),
    ),
  ));
  return saved;
}

Offset _at(WidgetTester tester, String id) =>
    tester.getCenter(find.byKey(Key('card-$id')));

Future<void> _longPressDrag(
  WidgetTester tester,
  String from,
  String to, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  // Measured before the drag: the held card's copy carries the same key.
  final start = _at(tester, from);
  final target = _at(tester, to);
  final gesture = await tester.startGesture(start, kind: kind);
  await tester.pump(const Duration(milliseconds: 600));
  // Small steps, as a real drag, so the target under the pointer is seen.
  for (var i = 1; i <= 10; i++) {
    await gesture.moveTo(Offset.lerp(start, target, i / 10)!);
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one column: every card under the previous one', (tester) async {
    await _pump(tester);
    final xs = _ids.map((id) => _at(tester, id).dx).toSet();
    expect(xs.length, 1);
    expect(_at(tester, 'b').dy, greaterThan(_at(tester, 'a').dy));
  });

  testWidgets('three columns: 5 cards in two rows, 3 + 2', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, columns: 3);
    final rowOf = {for (final id in _ids) id: _at(tester, id).dy};
    expect(rowOf['a'], rowOf['b']);
    expect(rowOf['b'], rowOf['c']);
    expect(rowOf['d'], rowOf['e']);
    expect(rowOf['d'], greaterThan(rowOf['a']!));
  });

  testWidgets('a long press and a drag with a finger moves the card',
      (tester) async {
    final saved = await _pump(tester);
    await _longPressDrag(tester, 'a', 'c');
    expect(saved, [
      ['b', 'c', 'a', 'd', 'e'],
    ]);
  });

  testWidgets('the mouse moves a card the same way (long press + drag)',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final saved = await _pump(tester, columns: 3);
    await _longPressDrag(tester, 'e', 'a', kind: PointerDeviceKind.mouse);
    expect(saved, [
      ['e', 'a', 'b', 'c', 'd'],
    ]);
  });

  testWidgets('a tap still opens the card', (tester) async {
    final taps = <String>[];
    final saved = await _pump(tester, tapsOut: taps);
    await tester.tap(find.byKey(const Key('card-c')));
    await tester.pumpAndSettle();
    expect(taps, ['c']);
    expect(saved, isEmpty);
  });

  testWidgets('a drop where it started saves nothing', (tester) async {
    final saved = await _pump(tester);
    final gesture = await tester.startGesture(_at(tester, 'b'));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 5));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });
}
