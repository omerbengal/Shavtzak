import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/utils/task_schedule.dart';
import '../task_style.dart';

final DateFormat _dayKeyFormat = DateFormat('yyyy-MM-dd');

/// The phone's "כל השלבים": [top] (the summary and the managers' check)
/// scrolls away, the filter row stays pinned, and the calendar, every day of
/// it one under the other, scrolls under it.
///
/// It opens with the block carrying [focusKey] just under the pinned row,
/// and scrolls it there again each time [focusRequest] changes, so a stage
/// opened in the sheet sits above it.
class CalendarTab extends StatefulWidget {
  const CalendarTab({
    super.key,
    required this.top,
    required this.filterBar,
    required this.calendar,
    this.focusKey,
    this.focusRequest = 0,
    this.bottomPadding = 0,
  });

  final Widget top;
  final Widget filterBar;
  final Widget calendar;
  final GlobalKey? focusKey;
  final int focusRequest;

  /// Room below the calendar for an open sheet.
  final double bottomPadding;

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _pinnedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocus(animate: false));
  }

  @override
  void didUpdateWidget(CalendarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusRequest != oldWidget.focusRequest) {
      // After the frame, once the sheet's room is laid out below.
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocus());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToFocus({bool animate = true}) {
    if (!mounted || !_scroll.hasClients) return;
    final target = widget.focusKey?.currentContext?.findRenderObject();
    if (target == null || !target.attached) return;
    final reveal = RenderAbstractViewport.of(target).getOffsetToReveal(target, 0);
    final pinned = _pinnedKey.currentContext?.findRenderObject();
    final pinnedHeight = pinned is RenderBox && pinned.hasSize ? pinned.size.height : 0;
    final position = _scroll.position;
    final offset = (reveal.offset - pinnedHeight - TaskStyle.focusTopMargin)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (!animate) {
      _scroll.jumpTo(offset);
      return;
    }
    _scroll.animateTo(
      offset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(child: widget.top),
        PinnedHeaderSliver(
          child: KeyedSubtree(
            key: _pinnedKey,
            child: Container(
              key: const Key('calendar-pinned'),
              color: background,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [widget.filterBar],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          sliver: SliverToBoxAdapter(child: widget.calendar),
        ),
        // Room for an open sheet, or for the floating button.
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: widget.bottomPadding > 0 ? widget.bottomPadding + 8 : 96,
          ),
        ),
      ],
    );
  }
}

/// A chip per day of the calendar, in a row that scrolls sideways when the
/// days do not fit.
class CalendarDayChips extends StatelessWidget {
  const CalendarDayChips({
    super.key,
    required this.days,
    required this.selectedDay,
    required this.now,
    required this.onSelectDay,
  });

  final List<DateTime> days;
  final DateTime selectedDay;
  final DateTime now;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          for (final day in days) ...[
            ChoiceChip(
              key: Key('calendar-day-${_dayKeyFormat.format(day)}'),
              label: Text(
                dayLabel(day, now),
                style: const TextStyle(fontSize: TaskStyle.filterFontSize),
              ),
              selected: day == selectedDay,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selectedColor: TaskStyle.currentLight,
              onSelected: (_) => onSelectDay(day),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// The line above each day of the phone's calendar, naming the day.
class CalendarDayDivider extends StatelessWidget {
  const CalendarDayDivider({super.key, required this.day, required this.now});

  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key('calendar-day-divider-${_dayKeyFormat.format(day)}'),
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
      child: Row(
        children: [
          const Expanded(child: Divider(color: TaskStyle.dayDividerLine)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              dayLabel(day, now),
              style: const TextStyle(
                fontSize: TaskStyle.filterFontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Expanded(child: Divider(color: TaskStyle.dayDividerLine)),
        ],
      ),
    );
  }
}
