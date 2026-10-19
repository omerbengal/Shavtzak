import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/debug/logger.dart';
import '../../../../core/utils/search_utils.dart';
import '../../../../domain/entities/team_member.dart';

/// A fixed entry under the member list, e.g. "שובצו כבר". Never filtered by
/// the search.
class MemberPickerAction {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const MemberPickerAction({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
}

/// The assignment cell's member picker on /admin/assignments.
///
/// Replaces a `DropdownButton`, which cannot hold a search field. Tapping
/// opens a menu anchored to the field: a search bar on top — deliberately NOT
/// focused on open, so a phone does not throw its keyboard over the list —
/// then the members, then [actions].
class MemberPickerField extends StatelessWidget {
  final TeamMember? selected;
  final List<TeamMember> members;
  final List<MemberPickerAction> actions;
  final bool enabled;
  final Color backgroundColor;

  /// Narrow cells get less inner padding, so the name keeps the space.
  final bool dense;

  /// A member's id, or one of the [actions]' values.
  final ValueChanged<String> onSelected;

  const MemberPickerField({
    super.key,
    required this.selected,
    required this.members,
    required this.actions,
    required this.enabled,
    required this.backgroundColor,
    required this.onSelected,
    this.dense = false,
  });

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final anchor = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    Logger.action('open:memberPicker');
    final value = await Navigator.of(context).push(_MemberPickerRoute(
      anchor: anchor,
      members: members,
      selectedId: selected?.id,
      actions: actions,
    ));
    if (value != null) onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    final member = selected;
    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: EdgeInsets.symmetric(horizontal: dense ? 4 : 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
          color: backgroundColor,
        ),
        child: Row(
          children: [
            Expanded(
              child: member == null
                  ? const Text(
                      'בחר...',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    )
                  : _MemberName(member: member, fontSize: 12),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: enabled ? null : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberName extends StatelessWidget {
  final TeamMember member;
  final double fontSize;
  final TextStyle? style;

  const _MemberName({required this.member, required this.fontSize, this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            member.name,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 4,
            style: (style ?? const TextStyle(color: Colors.black))
                .copyWith(fontSize: fontSize),
          ),
        ),
        if (member.isPermanent) ...[
          const SizedBox(width: 4),
          Icon(Icons.verified_user, size: 12, color: Colors.blue.shade700),
        ],
      ],
    );
  }
}

class _MemberPickerRoute extends PopupRoute<String> {
  final Rect anchor;
  final List<TeamMember> members;
  final String? selectedId;
  final List<MemberPickerAction> actions;

  _MemberPickerRoute({
    required this.anchor,
    required this.members,
    required this.selectedId,
    required this.actions,
  });

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'סגירה';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final media = MediaQuery.of(context);
    return FadeTransition(
      opacity: animation,
      child: CustomSingleChildLayout(
        delegate: _MenuLayout(
          anchor: anchor,
          // Phones get a menu twice the cell's width, growing towards the
          // screen centre — as the dropdown it replaces did.
          widthFactor: media.size.width < 600 ? 2 : 1,
          padding: media.padding + media.viewInsets,
        ),
        child: _MemberPickerMenu(
          members: members,
          selectedId: selectedId,
          actions: actions,
        ),
      ),
    );
  }
}

/// Lays the menu over the field, its start (right, in RTL) edge on the
/// field's, then pushes it back inside the screen and above the keyboard.
class _MenuLayout extends SingleChildLayoutDelegate {
  static const double _margin = 8;
  static const double _minWidth = 220;
  static const double _maxHeight = 460;

  final Rect anchor;
  final double widthFactor;
  final EdgeInsets padding;

  _MenuLayout({
    required this.anchor,
    required this.widthFactor,
    required this.padding,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth - 2 * _margin;
    final width =
        math.min(maxWidth, math.max(_minWidth, anchor.width * widthFactor));
    final available =
        constraints.maxHeight - padding.top - padding.bottom - 2 * _margin;
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(0, math.min(_maxHeight, available)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = (anchor.right - childSize.width)
        .clamp(_margin, math.max(_margin, size.width - childSize.width - _margin))
        .toDouble();
    final minTop = padding.top + _margin;
    final maxTop = size.height - padding.bottom - _margin - childSize.height;
    final top = anchor.top.clamp(minTop, math.max(minTop, maxTop)).toDouble();
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      widthFactor != oldDelegate.widthFactor ||
      padding != oldDelegate.padding;
}

class _MemberPickerMenu extends StatefulWidget {
  final List<TeamMember> members;
  final String? selectedId;
  final List<MemberPickerAction> actions;

  const _MemberPickerMenu({
    required this.members,
    required this.selectedId,
    required this.actions,
  });

  @override
  State<_MemberPickerMenu> createState() => _MemberPickerMenuState();
}

class _MemberPickerMenuState extends State<_MemberPickerMenu> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = normalizeForSearch(_query);
    final visible = normalizedQuery.isEmpty
        ? widget.members
        : widget.members
            .where((m) =>
                normalizeForSearch(m.name).contains(normalizedQuery))
            .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'חיפוש שם...',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'נקה חיפוש',
                          onPressed: () {
                            Logger.action('tap:clearMemberPickerSearch');
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Flexible(
              child: visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        widget.members.isEmpty
                            ? 'אין חברי צוות זמינים'
                            : 'לא נמצאו חברי צוות',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final member = visible[index];
                        final isSelected = member.id == widget.selectedId;
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(member.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            child: _MemberName(
                              member: member,
                              fontSize: 13,
                              style: isSelected
                                  ? const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    )
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            for (final action in widget.actions)
              InkWell(
                onTap: () => Navigator.of(context).pop(action.value),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(action.icon, size: 16, color: action.color),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          action.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: action.color,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
