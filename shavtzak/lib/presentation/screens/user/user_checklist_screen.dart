import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:developer' as developer;
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../../domain/entities/event.dart';
import '../../bloc/checklist/checklist_bloc.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_state.dart';
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

  void _showCcNoteDialog(ChecklistItem item) {
    final currentUser = (context.read<UserSelectionBloc>().state as UserAuthenticated).user;
    final controller = TextEditingController(text: item.getCcNote(currentUser.id) ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('הערה עבור ${item.name}'),
        content: TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'הערה שלך',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<ChecklistBloc>().add(
                UpdateCcNote(
                  itemId: item.id,
                  ccMemberId: currentUser.id,
                  note: controller.text.trim(),
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }

  void _showEditResponsibleNoteDialog(ChecklistItem item) {
    final controller = TextEditingController(text: item.responsibleNote);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ערוך פירוט אחראי עבור ${item.name}'),
        content: TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'פירוט אחראי',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim() != item.responsibleNote) {
                context.read<ChecklistBloc>().add(
                  UpdateResponsibleNote(
                    itemId: item.id,
                    note: controller.text.trim(),
                  ),
                );
              }
              Navigator.pop(context);
            },
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<UserSelectionBloc, UserSelectionState>(
      listener: (context, userState) {
        // Reload checklist items when user authentication changes
        if (userState is UserAuthenticated) {
          context.read<ChecklistBloc>().add(LoadUserChecklistItems(userState.user.id));
        }
      },
      child: BlocBuilder<UserSelectionBloc, UserSelectionState>(
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
              body: BlocConsumer<ChecklistBloc, ChecklistState>(
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
                    developer.log('UserChecklistScreen: Received UserChecklistLoaded with ${state.responsibleItems.length} responsible and ${state.ccItems.length} CC items', name: 'Checklist');

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildResponsibleItemsTab(state.responsibleItems, currentUser),
                        _buildCcItemsTab(state.ccItems, currentUser),
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
                        _buildResponsibleItemsTab(responsibleItems, currentUser),
                        _buildCcItemsTab(ccItems, currentUser),
                      ],
                    );
                  }

                  return const Center(child: Text('לא נמצאו פריטים בצ\'קליסט'));
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResponsibleItemsTab(List<ChecklistItem> items, TeamMember currentUser) {
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
            onStatusChanged: (newStatus) {
              context.read<ChecklistBloc>().add(
                UpdateChecklistItemStatus(
                  itemId: item.id,
                  newStatus: newStatus,
                ),
              );
            },
            onEditNote: () => _showEditResponsibleNoteDialog(item),
          )).toList(),
        );
      },
    );
  }

  Widget _buildCcItemsTab(List<ChecklistItem> items, TeamMember currentUser) {
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
            onEditNote: () => _showCcNoteDialog(item),
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