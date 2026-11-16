import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/home_card_order.dart';

/// The admin home cards in [order], [columns] to a row (1 = one under the
/// other; on a wide window two rows, the first holding the extra card when
/// the count is odd).
///
/// A long press and a drag moves a card, with a finger or the mouse alike (a
/// tap still opens it). While it is held the cards make room live: holding
/// it over another card puts it in that card's place. On release a changed
/// order goes to [onReorder].
class ReorderableHomeCards extends StatefulWidget {
  const ReorderableHomeCards({
    super.key,
    required this.order,
    required this.columns,
    required this.spacing,
    required this.cardBuilder,
    required this.onReorder,
  });

  final List<String> order;
  final int columns;
  final double spacing;
  final Widget Function(BuildContext context, String id) cardBuilder;
  final ValueChanged<List<String>> onReorder;

  @override
  State<ReorderableHomeCards> createState() => _ReorderableHomeCardsState();
}

class _ReorderableHomeCardsState extends State<ReorderableHomeCards> {
  /// The order while a card is held (null when none is).
  List<String>? _dragOrder;

  /// A global key per card keeps the held card's drag alive when the live
  /// order moves it to the other row.
  final Map<String, GlobalKey> _keys = {};

  void _drop() {
    final next = _dragOrder;
    setState(() => _dragOrder = null);
    if (next == null || listEquals(next, widget.order)) return;
    HapticFeedback.selectionClick();
    Logger.action('drop:homeCard', {'order': next.join(',')});
    widget.onReorder(next);
  }

  Widget _card(String id) {
    final card = widget.cardBuilder(context, id);
    return KeyedSubtree(
      key: _keys.putIfAbsent(id, GlobalKey.new),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) {
          if (details.data != id) {
            setState(() {
              _dragOrder =
                  moveHomeCard(_dragOrder ?? widget.order, details.data, id);
            });
          }
          return true;
        },
        builder: (context, candidates, rejected) => LongPressDraggable<String>(
          key: Key('home-card-drag-$id'),
          data: id,
          feedback: Material(
            color: Colors.transparent,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Transform.scale(scale: 1.04, child: card),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: card),
          onDragStarted: () {
            Logger.action('drag:homeCard', {'card': id});
            setState(() => _dragOrder = widget.order);
          },
          onDragEnd: (_) => _drop(),
          child: card,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = _dragOrder ?? widget.order;
    final columns = math.max(1, widget.columns);
    final rows = <List<String>>[
      for (var i = 0; i < order.length; i += columns)
        order.sublist(i, math.min(i + columns, order.length)),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: widget.spacing),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < rows[r].length; c++) ...[
                if (c > 0) SizedBox(width: widget.spacing),
                _card(rows[r][c]),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
