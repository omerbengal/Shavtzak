import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/event_items.dart';
import '../../../../domain/entities/event_item.dart';
import '../../../bloc/event_item/event_item_bloc.dart';
import '../../../bloc/event_item/event_item_state.dart';

/// What the event has ("מה יש באירוע") on the admin event card, under the
/// card's Drive / constraints icons (Omer, 25/11/2026): each item's emoji, or
/// its name when it has none, in the catalogue's order. Long-press / hover
/// shows the item's name. Nothing at all when the event has no items.
class EventItemsIconsRow extends StatelessWidget {
  final List<EventItemChoice> choices;

  const EventItemsIconsRow({super.key, required this.choices});

  @override
  Widget build(BuildContext context) {
    if (choices.isEmpty) return const SizedBox.shrink();
    return BlocBuilder<EventItemBloc, EventItemState>(
      builder: (context, state) {
        final items = eventItemsOf(choices, state.catalogue);
        if (items.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(top: 2, end: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final item in items)
                  Tooltip(
                    message: item.name,
                    child: Text(
                      item.compact,
                      style: TextStyle(
                        fontSize: item.emoji == null ? 12 : 18,
                        color: Colors.black87,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
