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
/// (status, owner, link) as chips. While the search is in use (focused or
/// holding text) the chips fold into one funnel button whose menu holds the
/// same three filters as rows (Omer, round 3).
///
/// [showOwner] false hides the owner filter ("המשימות שלי": they are all the
/// viewer's).
class TeamTaskFilterBar extends StatefulWidget {
  const TeamTaskFilterBar({super.key, required this.state, required this.showOwner});

  final TeamTasksLoaded state;
  final bool showOwner;

  /// The search field's width while the chips are shown.
  static const double searchWidth = 140;

  @override
  State<TeamTaskFilterBar> createState() => _TeamTaskFilterBarState();
}

class _TeamTaskFilterBarState extends State<TeamTaskFilterBar> {
  late final TextEditingController _search = TextEditingController(text: widget.state.filter.query);
  final FocusNode _focus = FocusNode();
  final MenuController _menu = MenuController();
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

  String? get _ownerName => _filter.ownerId == null
      ? null
      : widget.state.members.where((m) => m.id == _filter.ownerId).firstOrNull?.name;

  List<TeamMember> get _ownerOptions {
    final owners = {for (final task in widget.state.all) ...task.ownerIds};
    return widget.state.members.where((m) => owners.contains(m.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void _setOwner(String? id) => _set(_filter.copyWith(ownerId: () => id));

  Future<void> _tapLink() async {
    if (_filter.link != null) {
      _set(_filter.copyWith(link: () => null));
      return;
    }
    final choice = await showTaskLinkPicker(context, allowNone: false);
    if (choice?.link == null || !mounted) return;
    _set(_filter.copyWith(link: () => choice!.link));
  }

  String get _linkLabel {
    final name = taskLinkName(widget.state, _filter.link);
    return name == null ? 'שיוך' : '$name ✕';
  }

  bool get _anyFilterSet =>
      _filter.statusesChanged ||
      (widget.showOwner && _filter.ownerId != null) ||
      _filter.link != null;

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final folded = _folded;
    final field = _searchField();
    if (!folded) {
      // Closed: the field and the chips centred as one row (Omer, round 4),
      // scrolling sideways only when they do not fit.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: TeamTaskFilterBar.searchWidth, child: field),
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
            child: _FilterChipLook(label: _statusLabel, active: filter.statusesChanged),
          ),
        ),
      ),
      if (widget.showOwner) ...[
        const SizedBox(width: 6),
        PopupMenuButton<String>(
          key: const Key('team-filter-owner'),
          tooltip: 'סינון לפי אחראי',
          onSelected: (id) => _setOwner(id.isEmpty ? null : id),
          itemBuilder: (context) => [
            const PopupMenuItem(value: '', child: Text('כל האחראים')),
            for (final member in _ownerOptions)
              PopupMenuItem(
                value: member.id,
                child: MemberNameText(name: member.name, permanent: member.isPermanent),
              ),
          ],
          child: _FilterChipLook(label: _ownerName ?? 'אחראי', active: filter.ownerId != null),
        ),
      ],
      const SizedBox(width: 6),
      InkWell(
        key: const Key('team-filter-link'),
        borderRadius: BorderRadius.circular(16),
        onTap: _tapLink,
        child: _FilterChipLook(label: _linkLabel, active: filter.link != null),
      ),
    ];
  }

  /// The funnel sits at the far left of the screen (the row's end in RTL), so
  /// Flutter has no room for a submenu on the left, where RTL puts it, and
  /// opens it on the right. The arrow points there (round 4) and sits on the
  /// right of the word, the side it opens to (round 5): it leads the label,
  /// and the trailing slot stays empty so the menu keeps its width (a wider
  /// menu leaves no room on a phone for the submenu beside it).
  static Widget _withArrow(Widget label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Directionality(
            textDirection: TextDirection.ltr,
            child: Icon(Icons.arrow_right, key: Key('team-filter-submenu-arrow'), size: 24),
          ),
          const SizedBox(width: 2),
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
            menuChildren: [
              MenuItemButton(
                onPressed: () => _setOwner(null),
                child: const Text('כל האחראים'),
              ),
              for (final member in _ownerOptions)
                MenuItemButton(
                  key: Key('team-filter-menu-owner-${member.id}'),
                  onPressed: () => _setOwner(member.id),
                  trailingIcon:
                      member.id == filter.ownerId ? const Icon(Icons.check, size: 18) : null,
                  child: MemberNameText(name: member.name, permanent: member.isPermanent),
                ),
            ],
            child: _withArrow(Text(_ownerName == null ? 'אחראי' : 'אחראי: $_ownerName')),
          ),
        MenuItemButton(
          key: const Key('team-filter-menu-link'),
          onPressed: _tapLink,
          child: Text(_linkLabel),
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
  const _FilterChipLook({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? TaskStyle.currentLight : Colors.transparent,
        border: Border.all(color: active ? TaskStyle.mine : TaskStyle.rest),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: TaskStyle.filterFontSize,
              color: active ? TaskStyle.mine : TaskStyle.neutralText,
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18, color: TaskStyle.neutralText),
        ],
      ),
    );
  }
}
