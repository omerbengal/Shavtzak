import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:developer' as developer;
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../../domain/entities/event.dart';
import '../../bloc/checklist/checklist_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_state.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../widgets/checklist/user_checklist_item_card.dart';

/// User screen for viewing and editing their checklist items
class UserChecklistScreen extends StatefulWidget {
  const UserChecklistScreen({super.key});

  @override
  State<UserChecklistScreen> createState() => _UserChecklistScreenState();
}

class _UserChecklistScreenState extends State<UserChecklistScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Load events and team members for dialog
    context.read<EventBloc>().add(LoadEvents());
    context.read<TeamBloc>().add(LoadTeamMembers());

    // Load checklist items after widget is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userState = context.read<UserSelectionBloc>().state;
      if (userState is UserAuthenticated) {
        developer.log('UserChecklistScreen: Manually triggering LoadUserChecklistItems for user ${userState.user.id}', name: 'Checklist');
        context.read<ChecklistBloc>().add(LoadUserChecklistItems(userState.user.id));
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<UserSelectionBloc, UserSelectionState>(
      listenWhen: (previous, current) {
        final previousId = previous is UserAuthenticated ? previous.user.id : null;
        final currentId = current is UserAuthenticated ? current.user.id : null;
        return previousId != currentId;
      },
      listener: (context, userState) {
        // Reload checklist items when user authentication changes
        if (userState is UserAuthenticated) {
          context.read<ChecklistBloc>().add(LoadUserChecklistItems(userState.user.id));
        }
      },
      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
        buildWhen: (previous, current) {
          final previousId = previous is UserAuthenticated ? previous.user.id : null;
          final currentId = current is UserAuthenticated ? current.user.id : null;
          return previous.runtimeType != current.runtimeType ||
              previousId != currentId;
        },
        builder: (context, userState) {
          if (userState is! UserAuthenticated) {
            return const Center(
              child: Text('אנא התחבר כדי לצפות בצ\'קליסט'),
            );
          }

          final currentUser = userState.user;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('הצ\'קליסט שלי'),
                bottom: TabBar(
                  controller: _tabController,
                  indicator: UnderlineTabIndicator(
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.onPrimary,
                      width: 3.0,
                    ),
                    insets: const EdgeInsets.symmetric(horizontal: 16.0),
                  ),
                  labelColor: Theme.of(context).colorScheme.onPrimary,
                  unselectedLabelColor: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
                  labelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.person),
                      text: 'פריטים שאתה אחראי',
                      iconMargin: EdgeInsets.only(bottom: 4),
                    ),
                    Tab(
                      icon: Icon(Icons.people),
                      text: 'פריטים שאתה מיודע',
                      iconMargin: EdgeInsets.only(bottom: 4),
                    ),
                  ],
                ),
              ),
              body: BlocBuilder<TeamBloc, TeamState>(
                builder: (context, teamState) {
                  return BlocConsumer<ChecklistBloc, ChecklistState>(
                    listener: (context, state) {
                      if (state is ChecklistError) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(state.message),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    builder: (context, state) {
                      if (state is ChecklistLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (state is UserChecklistLoaded) {
                        return TabBarView(
                          controller: _tabController,
                          children: [
                            _buildResponsibleItemsTab(state.responsibleItems, currentUser, teamState),
                            _buildCcItemsTab(state.ccItems, currentUser, teamState),
                          ],
                        );
                      }

                      if (state is ChecklistLoaded) {
                        // Fallback if loaded with different state type
                        final responsibleItems = state.items
                            .where((item) => item.responsibleId == currentUser.id)
                            .toList();
                        final ccItems = state.items
                            .where((item) => item.ccIds.contains(currentUser.id))
                            .toList();

                        return TabBarView(
                          controller: _tabController,
                          children: [
                            _buildResponsibleItemsTab(responsibleItems, currentUser, teamState),
                            _buildCcItemsTab(ccItems, currentUser, teamState),
                          ],
                        );
                      }

                      return const Center(child: Text('לא נמצאו פריטים בצ\'קליסט'));
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResponsibleItemsTab(List<ChecklistItem> items, TeamMember currentUser, TeamState teamState) {
    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'אין לך פריטים שאתה אחראי עליהם',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Get all team members from the passed teamState
    final allTeamMembers = teamState is TeamLoaded ? teamState.members : <TeamMember>[];

    // Group by event
    final grouped = _groupByEvent(items);

    return ListView.builder(
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final entry = grouped.entries.elementAt(index);
        final event = entry.key;
        final eventItems = entry.value;

        return ExpansionTile(
          title: Text(
            event?.name ?? 'אירוע לא ידוע',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${eventItems.length} פריטים • ${_formatDate(event?.startDate)}',
            style: const TextStyle(fontSize: 14),
          ),
          children: eventItems.map((item) => UserChecklistItemCard(
            item: item,
            user: currentUser,
            allTeamMembers: allTeamMembers,
            onStatusChanged: (newStatus) {
              context.read<ChecklistBloc>().add(
                UpdateChecklistItemStatus(
                  itemId: item.id,
                  newStatus: newStatus,
                ),
              );
            },
            onAddNote: (content) {
              context.read<ChecklistBloc>().add(
                AddChecklistNote(
                  itemId: item.id,
                  content: content,
                  authorRole: 'אחראי',
                ),
              );
            },
          )).toList(),
        );
      },
    );
  }

  Widget _buildCcItemsTab(List<ChecklistItem> items, TeamMember currentUser, TeamState teamState) {
    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'אין לך פריטים שאתה מיודע עליהם',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Get all team members from the passed teamState
    final allTeamMembers = teamState is TeamLoaded ? teamState.members : <TeamMember>[];

    // Group by event
    final grouped = _groupByEvent(items);

    return ListView.builder(
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final entry = grouped.entries.elementAt(index);
        final event = entry.key;
        final eventItems = entry.value;

        return ExpansionTile(
          title: Text(
            event?.name ?? 'אירוע לא ידוע',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${eventItems.length} פריטים • ${_formatDate(event?.startDate)}',
            style: const TextStyle(fontSize: 14),
          ),
          children: eventItems.map((item) => UserChecklistItemCard(
            item: item,
            user: currentUser,
            allTeamMembers: allTeamMembers,
            onStatusChanged: (newStatus) {
              context.read<ChecklistBloc>().add(
                UpdateChecklistItemStatus(
                  itemId: item.id,
                  newStatus: newStatus,
                ),
              );
            },
            onAddNote: (content) {
              context.read<ChecklistBloc>().add(
                AddChecklistNote(
                  itemId: item.id,
                  content: content,
                  authorRole: 'מיודע',
                ),
              );
            },
          )).toList(),
        );
      },
    );
  }

  Map<Event?, List<ChecklistItem>> _groupByEvent(List<ChecklistItem> items) {
    final grouped = <Event?, List<ChecklistItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.event, () => []).add(item);
    }

    // Sort events by date (upcoming first)
    final sortedKeys = grouped.keys.toList();
    sortedKeys.sort((a, b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.startDate.compareTo(b.startDate);
    });

    // Create sorted map
    final sortedMap = <Event?, List<ChecklistItem>>{};
    for (final key in sortedKeys) {
      final eventItems = grouped[key]!;
      // Sort items within each event by name
      eventItems.sort((a, b) => a.name.compareTo(b.name));
      sortedMap[key] = eventItems;
    }

    return sortedMap;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'תאריך לא ידוע';
    return '${date.day}/${date.month}/${date.year}';
  }
}
