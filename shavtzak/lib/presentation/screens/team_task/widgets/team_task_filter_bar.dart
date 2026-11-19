import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/team_task_rules.dart';
import '../../../../domain/entities/team_member.dart';
import '../../../../domain/entities/team_task.dart';
import '../../../bloc/team_task/team_task_bloc.dart';
import '../../../widgets/rtl_arrow_keys.dart';
import '../../task/task_style.dart';
import 'task_link_picker.dart';
import 'team_task_style.dart';

/// The row above the list: a narrow search field, then the filters
/// (status, owner, urgency, link, late) as chips. While the search is in use (focused or
/// holding text) the chips fold into one funnel button whose menu holds the
/// same three filters as rows (Omer, round 3).
///
/// [showOwner] false hides the owner filter ("המשימות שלי": they are all the
/// viewer's) and the two time chips, "יצירה" and "עדכון סטטוס" (Omer,
/// 19/11/2026: "כל המשימות" only).
class TeamTaskFilterBar extends StatefulWidget {
  const TeamTaskFilterBar({super.key, required this.state, required this.showOwner});

  final TeamTasksLoaded state;
  final bool showOwner;

  /// The search field's width while the chips are shown.
  static const double searchWidth = 140;

  /// On a phone (narrower than [compactWidth]) the field and the chips are
  /// tighter, so the four chips fit beside the field (round 7: "באיחור").
  static const double compactSearchWidth = 90;
  static const double compactWidth = 480;

  @override
  State<TeamTaskFilterBar> createState() => _TeamTaskFilterBarState();
}

class _TeamTaskFilterBarState extends State<TeamTaskFilterBar> {
  late final TextEditingController _search = TextEditingController(text: widget.state.filter.query);
  final FocusNode _focus = FocusNode();
  final MenuController _menu = MenuController();

  /// Keeps the one search field alive when the tap that focuses it folds the
  /// row into its wide layout. Without it the field is rebuilt under its new
  /// parent: on the web that closes the browser input the tap focused and
  /// opens a new one after the tap, and iPhone opens the keyboard only for
  /// the input focused inside the tap (`web/ios_keyboard_fix.js`), so the
  /// field turned blue with no keyboard.
  final GlobalKey _fieldKey = GlobalKey(debugLabel: 'team-filter-search');
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  TeamTaskFilter get _filter => widget.state.filter;

  void _set(TeamTaskFilter filter) =>
      context.read<TeamTaskBloc>().add(TeamTaskFilterChanged(filter));

  bool get _compact => MediaQuery.sizeOf(context).width < TeamTaskFilterBar.compactWidth;

  bool get _folded => _focus.hasFocus || _search.text.isNotEmpty || _menuOpen;

  // ---- what each filter offers ----

  String get _statusLabel {
    final statuses = _filter.statuses;
    if (statuses.length == TeamTaskStatus.values.length) return 'כל הסטטוסים';
    if (!_filter.statusesChanged) return 'סטטוס';
    return 'סטטוס (${statuses.length})';
  }

  void _toggleStatus(TeamTaskStatus status) {
    final next = {..._filter.statuses};
    if (!next.remove(status)) next.add(status);
    if (next.isEmpty) return;
    _set(_filter.copyWith(statuses: next));
  }

  /// The owner chip's label: "אחראי/ת", the one name, or "אחראי/ת (n)"
  /// (Omer, round 7: several owners, like the statuses).
  String get _ownerLabel {
    final ids = _filter.ownerIds;
    if (ids.isEmpty) return 'אחראי/ת';
    if (ids.length == 1) {
      return widget.state.members.where((m) => m.id == ids.first).firstOrNull?.name ??
          unknownMemberLabel;
    }
    return 'אחראי/ת (${ids.length})';
  }

  void _toggleOwner(String id) {
    final next = {..._filter.ownerIds};
    if (!next.remove(id)) next.add(id);
    _set(_filter.copyWith(ownerIds: next));
  }

  /// The urgency chip's label: "דחיפות", the one level, or "דחיפות (n)".
  String get _urgencyLabel {
    final urgencies = _filter.urgencies;
    if (urgencies.isEmpty) return 'דחיפות';
    if (urgencies.length == 1) return 'דחיפות ${urgencies.first.hebrewLabel}';
    return 'דחיפות (${urgencies.length})';
  }

  void _toggleUrgency(TeamTaskUrgency urgency) {
    Logger.action('tap:teamTasksUrgencyFilter', {'urgency': urgency.key});
    final next = {..._filter.urgencies};
    if (!next.remove(urgency)) next.add(urgency);
    // Every level ticked = no filter.
    _set(_filter.copyWith(
        urgencies: next.length == TeamTaskUrgency.values.length ? const {} : next));
  }

  List<Widget> _urgencyRows({required String keyPrefix}) => [
        for (final urgency in TeamTaskUrgency.values.reversed)
          CheckboxMenuButton(
            key: Key('$keyPrefix-${urgency.key}'),
            value: _filter.urgencies.contains(urgency),
            closeOnActivate: false,
            onChanged: (_) => _toggleUrgency(urgency),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TeamTaskUrgencyIcon(urgency: urgency, size: 16),
                const SizedBox(width: 6),
                Text(urgency.hebrewLabel),
              ],
            ),
          ),
      ];

  // ---- the time chips (19/11/2026) ----

  /// "יצירה" or "עדכון סטטוס", and the range once one is picked.
  static String _timeLabel(String name, TeamTaskTimeRange? range) =>
      range == null ? name : '$name: ${range.hebrewLabel}';

  /// A title row inside the funnel's "זמן" submenu.
  Widget _menuHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: TaskStyle.neutralText)),
      );

  void _setCreated(TeamTaskTimeRange range) {
    Logger.action('tap:teamTasksCreatedFilter', {'range': range.name});
    // Picking the ticked range again clears it.
    final next = _filter.created == range ? null : range;
    _set(_filter.copyWith(created: () => next));
  }

  void _setStatusChanged(TeamTaskTimeRange range) {
    Logger.action('tap:teamTasksStatusChangedFilter', {'range': range.name});
    final next = _filter.statusChanged == range ? null : range;
    _set(_filter.copyWith(statusChanged: () => next));
  }

  /// One row per range; one range at a time, so a pick closes the menu.
  List<Widget> _timeRows({
    required String keyPrefix,
    required TeamTaskTimeRange? selected,
    required void Function(TeamTaskTimeRange) onPick,
  }) =>
      [
        for (final range in TeamTaskTimeRange.values)
          CheckboxMenuButton(
            key: Key('$keyPrefix-${range.name}'),
            value: selected == range,
            onChanged: (_) => onPick(range),
            child: Text(range.hebrewLabel),
          ),
      ];

  Widget _timeChip({
    required String keyName,
    required String name,
    required String tooltip,
    required TeamTaskTimeRange? selected,
    required void Function(TeamTaskTimeRange) onPick,
  }) =>
      MenuAnchor(
        menuChildren: _timeRows(keyPrefix: keyName, selected: selected, onPick: onPick),
        builder: (context, controller, _) => Tooltip(
          message: tooltip,
          child: InkWell(
            key: Key(keyName),
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Logger.action('tap:${keyName}Chip');
              controller.isOpen ? controller.close() : controller.open();
            },
            child: _FilterChipLook(
              compact: _compact,
              icon: Icons.schedule,
              label: _timeLabel(name, selected),
              active: selected != null,
            ),
          ),
        ),
      );

  void _toggleLate() {
    Logger.action('tap:teamTasksLateChip', {'on': !_filter.lateOnly});
    _set(_filter.copyWith(lateOnly: !_filter.lateOnly));
  }

  /// The owner menu's rows, each name centred across the menu's width
  /// (Omer, round 7): every row gets the width of the longest name.
  List<Widget> _ownerRows({required String keyPrefix}) {
    final options = _ownerOptions;
    final style = Theme.of(context).textTheme.labelLarge;
    var width = 0.0;
    for (final label in ['כל האחראים', for (final m in options) m.name]) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.rtl,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      if (painter.width > width) width = painter.width;
      painter.dispose();
    }
    // Room for the permanent member's mark after a name.
    width += 22;
    Widget centred(Widget child) => SizedBox(width: width, child: Center(child: child));
    final ids = _filter.ownerIds;
    return [
      MenuItemButton(
        key: Key('$keyPrefix-all'),
        closeOnActivate: false,
        onPressed: ids.isEmpty ? null : () => _set(_filter.copyWith(ownerIds: const {})),
        // The checkboxes' room, so this row's text is centred like the names.
        leadingIcon: const SizedBox(width: 24),
        child: centred(const Text('כל האחראים')),
      ),
      for (final member in options)
        CheckboxMenuButton(
          key: Key('$keyPrefix-${member.id}'),
          value: ids.contains(member.id),
          closeOnActivate: false,
          onChanged: (_) => _toggleOwner(member.id),
          child: centred(MemberNameText(name: member.name, permanent: member.isPermanent)),
        ),
    ];
  }

  List<TeamMember> get _ownerOptions {
    final owners = {for (final task in widget.state.all) ...task.ownerIds};
    return widget.state.members.where((m) => owners.contains(m.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _tapLink() async {
    if (_filter.link != null) {
      _set(_filter.copyWith(link: () => null));
      return;
    }
    final choice = await showTaskLinkPicker(
      context,
      allowNone: false,
      multiEvents: false,
      // Filtering never creates a new "אירוע שעוד לא נוצר" (Omer, 16/11/2026).
      allowNewPending: false,
    );
    if (choice?.link == null || !mounted) return;
    _set(_filter.copyWith(link: () => choice!.link));
  }

  String get _linkLabel {
    final name = taskLinkName(widget.state, _filter.link);
    return name == null ? 'שיוך' : '$name ✕';
  }

  bool get _anyFilterSet =>
      _filter.statusesChanged ||
      (widget.showOwner && _filter.ownerIds.isNotEmpty) ||
      _filter.urgencies.isNotEmpty ||
      _filter.link != null ||
      _filter.lateOnly ||
      (widget.showOwner && (_filter.created != null || _filter.statusChanged != null));

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final folded = _folded;
    final field = _searchField();
    if (!folded) {
      // Closed: the field and the chips centred as one row (Omer, round 4),
      // scrolling sideways only when they do not fit.
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: _compact ? 4 : 8, vertical: 6),
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _compact
                      ? TeamTaskFilterBar.compactSearchWidth
                      : TeamTaskFilterBar.searchWidth,
                  child: field,
                ),
                const SizedBox(width: 6),
                ..._chips(),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(child: field),
          const SizedBox(width: 6),
          // Tapping the funnel keeps the field's focus, so it stays folded.
          TextFieldTapRegion(child: _funnel()),
        ],
      ),
    );
  }

  Widget _searchField() {
    return SizedBox(
      key: _fieldKey,
      height: 34,
      child: RtlArrowKeys(
        child: TextField(
          key: const Key('team-filter-search'),
          controller: _search,
          focusNode: _focus,
          style: const TextStyle(fontSize: TaskStyle.filterFontSize),
          textInputAction: TextInputAction.search,
          onChanged: (value) {
            setState(() {});
            _set(_filter.copyWith(query: value));
          },
          onTapOutside: (_) => _focus.unfocus(),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'חיפוש',
            prefixIcon: const Icon(Icons.search, size: 18),
            prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    key: const Key('team-filter-search-clear'),
                    tooltip: 'ניקוי',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      _search.clear();
                      _focus.unfocus();
                      setState(() {});
                      _set(_filter.copyWith(query: ''));
                    },
                  ),
            suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: TaskStyle.rest),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: TaskStyle.rest),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _chips() {
    final filter = _filter;
    final gap = SizedBox(width: _compact ? 4 : 6);
    return [
      // A MenuAnchor rather than a PopupMenuButton: ticking a status keeps
      // the menu open, so several are set in one go (Omer, round 6).
      MenuAnchor(
        menuChildren: [
          for (final status in TeamTaskStatus.values)
            CheckboxMenuButton(
              key: Key('team-filter-status-${status.name}'),
              value: filter.statuses.contains(status),
              closeOnActivate: false,
              onChanged: (_) => _toggleStatus(status),
              child: Text(status.hebrewLabel),
            ),
        ],
        builder: (context, controller, _) => Tooltip(
          message: 'סינון לפי סטטוס',
          child: InkWell(
            key: const Key('team-filter-status'),
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Logger.action('tap:teamTasksStatusChip');
              controller.isOpen ? controller.close() : controller.open();
            },
            child: _FilterChipLook(
                compact: _compact, label: _statusLabel, active: filter.statusesChanged),
          ),
        ),
      ),
      if (widget.showOwner) ...[
        gap,
        // Several owners ticked in one go, as the statuses (round 7).
        MenuAnchor(
          menuChildren: _ownerRows(keyPrefix: 'team-filter-owner'),
          builder: (context, controller, _) => Tooltip(
            message: 'סינון לפי אחראי/ת',
            child: InkWell(
              key: const Key('team-filter-owner'),
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Logger.action('tap:teamTasksOwnerChip');
                controller.isOpen ? controller.close() : controller.open();
              },
              child: _FilterChipLook(
                  compact: _compact, label: _ownerLabel, active: filter.ownerIds.isNotEmpty),
            ),
          ),
        ),
      ],
      gap,
      // Urgency (16/11/2026), several ticked in one go like the statuses.
      MenuAnchor(
        menuChildren: _urgencyRows(keyPrefix: 'team-filter-urgency'),
        builder: (context, controller, _) => Tooltip(
          message: 'סינון לפי דחיפות',
          child: InkWell(
            key: const Key('team-filter-urgency'),
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Logger.action('tap:teamTasksUrgencyChip');
              controller.isOpen ? controller.close() : controller.open();
            },
            child: _FilterChipLook(
                compact: _compact, label: _urgencyLabel, active: filter.urgencies.isNotEmpty),
          ),
        ),
      ),
      gap,
      InkWell(
        key: const Key('team-filter-link'),
        borderRadius: BorderRadius.circular(16),
        onTap: _tapLink,
        child: _FilterChipLook(compact: _compact, label: _linkLabel, active: filter.link != null),
      ),
      if (widget.showOwner) ...[
        gap,
        _timeChip(
          keyName: 'team-filter-created',
          name: 'יצירה',
          tooltip: 'סינון לפי מועד היצירה',
          selected: filter.created,
          onPick: _setCreated,
        ),
        gap,
        _timeChip(
          keyName: 'team-filter-status-changed',
          name: 'עדכון סטטוס',
          tooltip: 'סינון לפי מועד שינוי הסטטוס',
          selected: filter.statusChanged,
          onPick: _setStatusChanged,
        ),
      ],
      gap,
      // "באיחור" (round 7): a plain on/off chip, the last one, at the far
      // left (Omer, round 8).
      InkWell(
        key: const Key('team-filter-late'),
        borderRadius: BorderRadius.circular(16),
        onTap: _toggleLate,
        child: _FilterChipLook(
            compact: _compact, label: 'באיחור', active: filter.lateOnly, dropdown: false),
      ),
    ];
  }

  /// The funnel sits at the far left of the screen (the row's end in RTL), so
  /// Flutter has no room for a submenu on the left, where RTL puts it, and
  /// opens it on the right. The arrow points there (round 4) and sits on the
  /// right of the word, the side it opens to (round 5): it leads the label,
  /// and the trailing slot stays empty so the menu keeps its width (a wider
  /// menu leaves no room on a phone for the submenu beside it).
  ///
  /// [arrow] false keeps the arrow's room empty, so the words of every row
  /// start at the same place (round 9).
  static Widget _withArrow(Widget label, {bool arrow = true}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow
              ? const Directionality(
                  textDirection: TextDirection.ltr,
                  child: Icon(Icons.arrow_right, key: Key('team-filter-submenu-arrow'), size: 24),
                )
              : const SizedBox(width: 24),
          // Arrow + gap = the checkbox + its gap of the "באיחור" row, so every
          // word starts at the same place (round 9).
          const SizedBox(width: 6),
          Flexible(child: label),
        ],
      );
  static const WidgetStateProperty<Widget?> _noTrailingArrow =
      WidgetStatePropertyAll(SizedBox.shrink());

  /// The three filters folded into one funnel; its menu lists them as rows.
  Widget _funnel() {
    final filter = _filter;
    final active = _anyFilterSet;
    return MenuAnchor(
      controller: _menu,
      onOpen: () => setState(() => _menuOpen = true),
      onClose: () => setState(() => _menuOpen = false),
      menuChildren: [
        SubmenuButton(
          key: const Key('team-filter-menu-status'),
          submenuIcon: _noTrailingArrow,
          menuChildren: [
            for (final status in TeamTaskStatus.values)
              CheckboxMenuButton(
                key: Key('team-filter-menu-status-${status.name}'),
                value: filter.statuses.contains(status),
                closeOnActivate: false,
                onChanged: (_) => _toggleStatus(status),
                child: Text(status.hebrewLabel),
              ),
          ],
          child: _withArrow(Text(_statusLabel)),
        ),
        if (widget.showOwner)
          SubmenuButton(
            key: const Key('team-filter-menu-owner'),
            submenuIcon: _noTrailingArrow,
            menuChildren: _ownerRows(keyPrefix: 'team-filter-menu-owner'),
            child: _withArrow(Text(_ownerLabel)),
          ),
        SubmenuButton(
          key: const Key('team-filter-menu-urgency'),
          submenuIcon: _noTrailingArrow,
          menuChildren: _urgencyRows(keyPrefix: 'team-filter-menu-urgency'),
          child: _withArrow(Text(_urgencyLabel)),
        ),
        // "שיוך" opens the link picker, so it carries the same arrow as the
        // rows above (Omer, round 9); once a link is set the row clears it
        // ("<name> ✕") and the arrow's room stays empty.
        MenuItemButton(
          key: const Key('team-filter-menu-link'),
          onPressed: _tapLink,
          child: _withArrow(Text(_linkLabel), arrow: filter.link == null),
        ),
        // Both time chips in ONE row, "זמן": a row as long as "עדכון סטטוס"
        // widens the menu until a phone has no room for a submenu beside it.
        if (widget.showOwner)
          SubmenuButton(
            key: const Key('team-filter-menu-time'),
            submenuIcon: _noTrailingArrow,
            menuChildren: [
              _menuHeader('יצירה'),
              ..._timeRows(
                  keyPrefix: 'team-filter-menu-created',
                  selected: filter.created,
                  onPick: _setCreated),
              const Divider(height: 1),
              _menuHeader('עדכון סטטוס'),
              ..._timeRows(
                  keyPrefix: 'team-filter-menu-status-changed',
                  selected: filter.statusChanged,
                  onPick: _setStatusChanged),
            ],
            child: _withArrow(Text(
                filter.created != null || filter.statusChanged != null ? 'זמן •' : 'זמן')),
          ),
        // Last in the menu, as its chip is last in the row (round 8).
        CheckboxMenuButton(
          key: const Key('team-filter-menu-late'),
          value: filter.lateOnly,
          closeOnActivate: false,
          onChanged: (_) => _toggleLate(),
          child: const Text('באיחור'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        key: const Key('team-filter-funnel'),
        tooltip: 'סינון',
        style: IconButton.styleFrom(
          backgroundColor: active ? TaskStyle.currentLight : null,
        ),
        icon: Icon(
          active ? Icons.filter_alt : Icons.filter_alt_outlined,
          color: active ? TaskStyle.mine : TaskStyle.neutralText,
        ),
        onPressed: () {
          Logger.action('tap:teamTasksFunnel');
          controller.isOpen ? controller.close() : controller.open();
        },
      ),
    );
  }
}

class _FilterChipLook extends StatelessWidget {
  const _FilterChipLook({
    required this.label,
    required this.active,
    this.dropdown = true,
    this.compact = false,
    this.icon,
  });

  /// Shown beside the label (the time chips' clock, 19/11/2026).
  final IconData? icon;

  /// A phone: less room inside the chip.
  final bool compact;

  final String label;
  final bool active;

  /// The arrow of a chip that opens a menu; an on/off chip has none.
  final bool dropdown;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? TaskStyle.currentLight : Colors.transparent,
        border: Border.all(color: active ? TaskStyle.mine : TaskStyle.rest),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: active ? TaskStyle.mine : TaskStyle.neutralText),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: TaskStyle.filterFontSize,
              color: active ? TaskStyle.mine : TaskStyle.neutralText,
            ),
          ),
          if (dropdown) const Icon(Icons.arrow_drop_down, size: 18, color: TaskStyle.neutralText),
        ],
      ),
    );
  }
}
