import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/repositories/assignment_label_repository.dart';
import '../../../../data/repositories/assignment_repository.dart';
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/assignment_label.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/event_item.dart';
import '../../../../domain/entities/role.dart';
import '../../../bloc/event_item/event_item_bloc.dart';
import '../../../bloc/event_item/event_item_state.dart';
import '../../../bloc/role/role_bloc.dart';
import '../../../bloc/role/role_event.dart';
import '../../../bloc/role/role_state.dart';
import '../../event/widgets/event_assignments_share_card.dart';
import '../../event/widgets/event_assignments_share_data_builder.dart';
import '../../event/widgets/event_assignments_share_models.dart';
import '../task_style.dart';

/// The event's assignments drawn as its "תמונת שיבוצים" export picture,
/// read-only, live: the picture is the export's own widget, redrawn as the
/// assignments, labels, roles or the event change. Wires the app's
/// repositories and blocs into [EventAssignmentsQuickViewBody].
class EventAssignmentsQuickView extends StatefulWidget {
  const EventAssignmentsQuickView({
    super.key,
    required this.event,
    required this.onClose,
  });

  final Event event;
  final VoidCallback onClose;

  @override
  State<EventAssignmentsQuickView> createState() =>
      _EventAssignmentsQuickViewState();
}

class _EventAssignmentsQuickViewState extends State<EventAssignmentsQuickView> {
  late final Stream<List<Assignment>> _assignments = context
      .read<AssignmentRepository>()
      .watchAssignmentsByEvent(widget.event.id);
  late final Stream<List<AssignmentLabel>> _labels = context
      .read<AssignmentLabelRepository>()
      .watchAssignmentLabels();

  @override
  void initState() {
    super.initState();
    final roles = context.read<RoleBloc>();
    if (roles.state is RoleInitial) roles.add(const LoadRoles());
  }

  @override
  Widget build(BuildContext context) {
    final roleState = context.watch<RoleBloc>().state;
    final items = context.watch<EventItemBloc>().state.catalogue;
    return EventAssignmentsQuickViewBody(
      event: widget.event,
      assignments: _assignments,
      labels: _labels,
      activeRoles: roleState is RolesLoaded ? roleState.activeRoles : null,
      eventItems: items,
      onClose: widget.onClose,
    );
  }
}

/// The panel itself, fed plain values and streams (so tests need no app).
/// [activeRoles] null = still loading.
class EventAssignmentsQuickViewBody extends StatelessWidget {
  const EventAssignmentsQuickViewBody({
    super.key,
    required this.event,
    required this.assignments,
    required this.labels,
    required this.activeRoles,
    required this.onClose,
    this.eventItems = const [],
  });

  final Event event;
  final Stream<List<Assignment>> assignments;
  final Stream<List<AssignmentLabel>> labels;
  final List<Role>? activeRoles;
  final List<EventItem> eventItems;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= TaskStyle.wideBreakpoint;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ColoredBox(
        color: TaskStyle.editPage,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 6, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'שיבוצים',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('assignments-quick-view-close'),
                      tooltip: 'סגירה',
                      // A wide window closes it only with this button.
                      iconSize: wide
                          ? TaskStyle.assignmentsCloseIconWide
                          : TaskStyle.assignmentsCloseIcon,
                      padding: EdgeInsets.all(wide ? 12 : 8),
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              Expanded(child: _content()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    return StreamBuilder<List<Assignment>>(
      stream: assignments,
      builder: (context, assignmentSnap) {
        return StreamBuilder<List<AssignmentLabel>>(
          stream: labels,
          builder: (context, labelSnap) {
            if (assignmentSnap.hasError) {
              return _message('לא ניתן לטעון את השיבוצים');
            }
            final roles = activeRoles;
            final loaded = assignmentSnap.data;
            if (loaded == null || roles == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final sortedRoles = List<Role>.from(roles)
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
            final data = EventAssignmentsShareDataBuilder.build(
              event: event,
              assignments: loaded,
              activeRoles: sortedRoles,
              labels: labelSnap.data ?? const [],
              groupingMode: EventAssignmentsGroupingMode.role,
              eventItems: eventItems,
            );
            if (data.sections.isEmpty) {
              return _message('אין עדיין שיבוצים לאירוע');
            }
            return SingleChildScrollView(
              key: const Key('assignments-quick-view-scroll'),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Center(
                // The picture is 1080 px wide: shrunk to the panel, and on a
                // wide window to at most assignmentsPictureMaxWidth.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: TaskStyle.assignmentsPictureMaxWidth,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: EventAssignmentsShareCard(data: data),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _message(String text) => Center(
    child: Text(
      text,
      style: const TextStyle(color: TaskStyle.editMuted, fontSize: 16),
    ),
  );
}
