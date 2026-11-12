import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/entities/assignment.dart';
import '../../domain/entities/role.dart';
import '../bloc/assignment/assignment_bloc.dart';
import '../bloc/assignment/assignment_event.dart';
import '../bloc/assignment/assignment_state.dart';
import '../bloc/role/role_bloc.dart';
import '../bloc/role/role_state.dart';
import '../../../core/services/service_locator.dart';
import '../../core/debug/logger.dart';
import '../../domain/entities/assignment_label.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/event_item.dart';
import '../screens/event/widgets/event_assignments_fit_picture.dart';
import '../screens/event/widgets/event_assignments_share_data_builder.dart';
import '../screens/event/widgets/event_assignments_share_models.dart';

/// "מי איתי באירוע?": the event's assignments drawn as its export picture
/// ("תמונת שיבוצים"), live, all of it on one screen, with a phone button per
/// member and the viewer's own row as "אני". No sharing from here.
class EventTeamMembersDialog extends StatefulWidget {
  final Event event;
  final String currentUserId;

  /// The labels, to order members as the export does. Null = none.
  final Stream<List<AssignmentLabel>>? labels;

  /// The "מה יש באירוע" catalogue, for the picture's items line.
  final List<EventItem> eventItems;

  static const double _inset = 6;
  static const double _maxWidth = 620;

  /// Optional injected BLoC. When null (production), the dialog creates and owns
  /// its own AssignmentBloc. Tests inject one so they can drive the stream.
  final AssignmentBloc? assignmentBloc;

  const EventTeamMembersDialog({
    super.key,
    required this.event,
    required this.currentUserId,
    this.labels,
    this.eventItems = const [],
    this.assignmentBloc,
  });

  String get eventId => event.id;

  @override
  State<EventTeamMembersDialog> createState() => _EventTeamMembersDialogState();
}

class _EventTeamMembersDialogState extends State<EventTeamMembersDialog> {
  late final AssignmentBloc _assignmentBloc;
  late final bool _ownsBloc;
  late final Stream<List<AssignmentLabel>> _labels =
      widget.labels ?? Stream.value(const []);

  @override
  void initState() {
    super.initState();
    // A dedicated BLoC is required: the ambient AssignmentBloc on the
    // /user/assignments screen is in "by person" mode, so reusing it would
    // clobber that screen's state. Tests inject one; production creates+owns it.
    final injected = widget.assignmentBloc;
    if (injected != null) {
      _assignmentBloc = injected;
      _ownsBloc = false;
    } else {
      _assignmentBloc = serviceLocator.createAssignmentBloc();
      _ownsBloc = true;
    }

    // Stream-first: paint from the real-time watchAssignmentsByEvent stream,
    // which serves cached data immediately and self-heals from the server.
    //
    // We deliberately do NOT prefetch via a one-shot getAssignmentsByEvent()
    // here. A one-shot .get() uses Firestore's default source (server-first)
    // and can park for ~30s on a transport hiccup, while listeners on the SAME
    // connection keep emitting in ~100ms — which previously froze this dialog
    // on a spinner. Every other assignment view paints from a stream; so does
    // this one now. Dispatch exactly once (the handler is a long-running
    // emit.forEach; re-dispatching spawns competing subscriptions).
    _assignmentBloc.add(LoadAssignmentsByEvent(widget.eventId));
  }

  @override
  void dispose() {
    // Only close the BLoC if we created it — never close an injected one.
    if (_ownsBloc) {
      _assignmentBloc.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocProvider<AssignmentBloc>.value(
        value: _assignmentBloc,
        child: Dialog(
          // As much of the screen as there is: the whole picture fits in it.
          insetPadding: const EdgeInsets.all(EventTeamMembersDialog._inset),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: EventTeamMembersDialog._maxWidth,
            height: MediaQuery.sizeOf(context).height,
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'מי איתי באירוע?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        Logger.action('tap:close:eventTeamMembersDialog');
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Content
                Expanded(
                  child: BlocBuilder<AssignmentBloc, AssignmentState>(
                    builder: (context, state) {
                      // Paint from the real-time stream.
                      if (state is AssignmentsLoaded) {
                        final assignments = state.assignments
                            .where((a) => a.eventId == widget.eventId)
                            .toList();
                        return assignments.isEmpty
                            ? _buildEmptyState()
                            : _buildPicture(context, assignments);
                      }

                      // Definitive "no assignments" from the stream.
                      if (state is AssignmentsEmpty) {
                        return _buildEmptyState();
                      }

                      if (state is AssignmentError) {
                        return Center(
                          child: Text(
                            'שגיאה בטעינת נתונים',
                            style: TextStyle(
                                fontSize: 16, color: Colors.red.shade600),
                          ),
                        );
                      }

                      // Initial/loading: brief spinner until the stream's
                      // first emission (typically ~100ms).
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        'אין חברי צוות נוספים באירוע',
        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
      ),
    );
  }

  /// The event's export picture, laid out narrow (readable once shrunk) and
  /// shrunk so all of it fits the popup: no scrolling.
  Widget _buildPicture(BuildContext context, List<Assignment> assignments) {
    return BlocBuilder<RoleBloc, RoleState>(
      builder: (context, roleState) {
        if (roleState is! RolesLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final roles = List<Role>.from(roleState.activeRoles)
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return StreamBuilder<List<AssignmentLabel>>(
          stream: _labels,
          builder: (context, labelSnap) {
            // The stream's copy of the event is the freshest one.
            final event = assignments
                    .map((a) => a.event)
                    .whereType<Event>()
                    .firstOrNull ??
                widget.event;
            final data = EventAssignmentsShareDataBuilder.build(
              event: event,
              assignments: assignments,
              activeRoles: roles,
              labels: labelSnap.data ?? const [],
              groupingMode: EventAssignmentsGroupingMode.role,
              eventItems: widget.eventItems,
            );
            if (data.sections.isEmpty) return _buildEmptyState();
            return EventAssignmentsFitPicture(
              pictureKey: const Key('who-is-with-me-picture'),
              data: data,
              currentMemberId: widget.currentUserId,
              onCall: _confirmCall,
            );
          },
        );
      },
    );
  }

  /// A row of the shrunk picture is a small target, so a tap first names who
  /// is about to be called; the call itself is one big button.
  Future<void> _confirmCall(EventAssignmentsShareRow row) async {
    final phone = row.phoneNumber;
    if (phone == null) return;
    Logger.action('tap:callRow', {'memberId': row.memberId});
    final call = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          key: const Key('confirm-call'),
          title: Text('להתקשר ל${row.memberName}?'),
          content: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(phone, style: const TextStyle(fontSize: 18)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            FilledButton.icon(
              key: const Key('confirm-call-button'),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.phone),
              label: const Text('התקשר'),
            ),
          ],
        ),
      ),
    );
    if (call != true) return;
    Logger.action('tap:callPhone', {'memberId': row.memberId});
    await _makePhoneCall(phone);
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }
}
