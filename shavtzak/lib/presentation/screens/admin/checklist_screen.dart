import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/checklist/checklist_bloc.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../bloc/user_selection/user_selection_event.dart';
import '../../bloc/user_selection/user_selection_state.dart';
import '../../widgets/checklist/checklist_form_modal.dart';
import '../../widgets/checklist/checklist_item_card.dart';
import '../../widgets/checklist/presets_dialog.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../core/utils/rtl_text_field_utils.dart';

/// Admin screen for managing all checklist items
class AdminChecklistScreen extends StatefulWidget {
  const AdminChecklistScreen({super.key});

  @override
  State<AdminChecklistScreen> createState() => _AdminChecklistScreenState();
}

class _AdminChecklistScreenState extends State<AdminChecklistScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  String _searchQuery = '';
  String? _selectedEventId;
  String? _selectedResponsibleId;
  bool? _statusFilter;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = createRtlCursorFixedFocusNode(_searchController);
    _tabController = TabController(length: 2, vsync: this);
    // Load events and team members for dropdowns
    context.read<EventBloc>().add(LoadEvents());
    context.read<TeamBloc>().add(LoadTeamMembers());
    // Load all checklist items
    context.read<ChecklistBloc>().add(LoadChecklistItems());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _selectedEventId = null;
      _selectedResponsibleId = null;
      _statusFilter = null;
    });
    _searchController.clear();
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('אישור התנתקות'),
          content: const Text('האם את/ה בטוח/ה שברצונך להתנתק?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.read<UserSelectionBloc>().add(const SignOut());
              },
              child: const Text(
                'התנתקות',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<ChecklistItem> _filterItems(List<ChecklistItem> items) {
    var filtered = items;

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final normalizedQuery = _searchQuery.toLowerCase();
      filtered = filtered
          .where((item) =>
              item.name.toLowerCase().contains(normalizedQuery) ||
              (item.event?.name.toLowerCase().contains(normalizedQuery) ??
                  false) ||
              (item.responsible?.name.toLowerCase().contains(normalizedQuery) ??
                  false))
          .toList();
    }

    // Event filter
    if (_selectedEventId != null) {
      filtered =
          filtered.where((item) => item.eventId == _selectedEventId).toList();
    }

    // Responsible filter
    if (_selectedResponsibleId != null) {
      filtered = filtered
          .where((item) => item.responsibleId == _selectedResponsibleId)
          .toList();
    }

    // Status filter
    if (_statusFilter != null) {
      filtered =
          filtered.where((item) => item.status == _statusFilter).toList();
    }

    return filtered;
  }

  Map<String, List<ChecklistItem>> _groupByEvent(List<ChecklistItem> items) {
    final grouped = <String, List<ChecklistItem>>{};
    for (final item in items) {
      final key = item.eventId;
      grouped.putIfAbsent(key, () => []).add(item);
    }

    // Sort items within each event by name
    for (final list in grouped.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }

    return grouped;
  }

  void _showAddModal() {
    // Get current user ID for tracking creator
    final userState = context.read<UserSelectionBloc>().state;
    final currentUserId =
        userState is UserAuthenticated ? userState.user.id : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) => ChecklistFormModal(
        currentUserId: currentUserId,
        onSave: (item) => _waitForChecklistAction(
          (completion) => context.read<ChecklistBloc>().add(
                AddChecklistItem(item, completion: completion),
              ),
        ),
      ),
    );
  }

  Color _getItemColor(ChecklistItem item) {
    // Use same colors as EventListScreen
    return item.status
        ? Colors.lightGreen.withOpacity(0.3)
        : Colors.red.withOpacity(0.3);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Row(
            children: [
              // Leading: filter icon
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _showFilterSheet,
                tooltip: 'סינון',
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
              // Centered title
              const Expanded(
                child: Center(
                    child: Text('צ\'קליסט אירועים',
                        style: TextStyle(fontSize: 20))),
              ),
              // Trailing icons
              IconButton(
                icon: const Icon(Icons.home),
                tooltip: 'בית',
                onPressed: () {
                  final envPrefix = EnvironmentService.instance.routePrefix;
                  context.go('$envPrefix/admin');
                },
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'התנתק',
                onPressed: () => _logout(context),
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              ),
            ],
          ),
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
            unselectedLabelColor:
                Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
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
                icon: Icon(Icons.list_alt),
                text: 'כל הפריטים',
                iconMargin: EdgeInsets.only(bottom: 4),
              ),
              Tab(
                icon: Icon(Icons.event),
                text: 'לפי אירוע',
                iconMargin: EdgeInsets.only(bottom: 4),
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildAllItemsTab(),
            _buildByEventTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              builder: (bottomSheetContext) => Directionality(
                textDirection: TextDirection.rtl,
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text('הוסף פריט'),
                        onTap: () {
                          Navigator.pop(bottomSheetContext);
                          _showAddModal();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.bookmark),
                        title: const Text('פריסטים'),
                        onTap: () {
                          Navigator.pop(bottomSheetContext);
                          PresetsDialog.show(context);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildAllItemsTab() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: const InputDecoration(
              labelText: 'חיפוש...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        // Active filters chips
        if (_hasActiveFilters())
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Wrap(
              spacing: 8.0,
              children: [
                Chip(
                  label: const Text('נקה סינונים'),
                  deleteIcon: const Icon(Icons.clear),
                  onDeleted: _clearFilters,
                ),
              ],
            ),
          ),
        // Items list
        Expanded(
          child: BlocBuilder<TeamBloc, TeamState>(
            builder: (context, teamState) {
              final allTeamMembers =
                  teamState is TeamLoaded ? teamState.members : <TeamMember>[];

              return BlocBuilder<ChecklistBloc, ChecklistState>(
                builder: (context, state) {
                  if (state is ChecklistLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (state is ChecklistError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(state.message),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => context
                                .read<ChecklistBloc>()
                                .add(LoadChecklistItems()),
                            child: const Text('נסה שוב'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (state is ChecklistLoaded) {
                    final filteredItems = _filterItems(state.items);
                    if (filteredItems.isEmpty) {
                      return const Center(
                        child: Text('לא נמצאו פריטים בצ\'קליסט'),
                      );
                    }

                    // Sort by: event start date (asc), event name (asc), checklist item name (asc)
                    final sortedItems = filteredItems.sorted((a, b) {
                      // First compare by event start date
                      final aDate = a.event?.startDate ?? DateTime(0);
                      final bDate = b.event?.startDate ?? DateTime(0);
                      final dateCompare = aDate.compareTo(bDate);
                      if (dateCompare != 0) return dateCompare;

                      // Then compare by event name
                      final aEventName = a.event?.name ?? '';
                      final bEventName = b.event?.name ?? '';
                      final eventNameCompare = aEventName.compareTo(bEventName);
                      if (eventNameCompare != 0) return eventNameCompare;

                      // Finally compare by checklist item name
                      return a.name.compareTo(b.name);
                    });

                    // Get current user ID for personal note display
                    final userState = context.read<UserSelectionBloc>().state;
                    final currentUserId = userState is UserAuthenticated
                        ? userState.user.id
                        : null;

                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: sortedItems.length,
                      itemBuilder: (context, index) {
                        final item = sortedItems[index];
                        return ChecklistItemCard(
                          item: item,
                          allTeamMembers: allTeamMembers,
                          isAdmin: true,
                          currentUserId: currentUserId,
                          onTap: () => _showEditModal(item),
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
                                    authorRole: 'מנהל',
                                  ),
                                );
                          },
                        );
                      },
                    );
                  }
                  return const SizedBox.shrink();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildByEventTab() {
    return BlocBuilder<TeamBloc, TeamState>(
      builder: (context, teamState) {
        final allTeamMembers =
            teamState is TeamLoaded ? teamState.members : <TeamMember>[];

        return BlocBuilder<ChecklistBloc, ChecklistState>(
          builder: (context, state) {
            if (state is ChecklistLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is ChecklistError) {
              return Center(child: Text(state.message));
            }
            if (state is ChecklistLoaded) {
              final filteredItems = _filterItems(state.items);
              final groupedItems = _groupByEvent(filteredItems);

              // Sort events by date (asc), then by name (asc)
              final sortedEventIds = groupedItems.keys.toList();
              sortedEventIds.sort((a, b) {
                final aItems = groupedItems[a]!;
                final bItems = groupedItems[b]!;
                if (aItems.isEmpty || bItems.isEmpty) return 0;

                // First compare by event start date (asc)
                final aDate = aItems.first.event?.startDate ?? DateTime(0);
                final bDate = bItems.first.event?.startDate ?? DateTime(0);
                final dateCompare = aDate.compareTo(bDate);
                if (dateCompare != 0) return dateCompare;

                // Then compare by event name (asc)
                final aEventName = aItems.first.event?.name ?? '';
                final bEventName = bItems.first.event?.name ?? '';
                return aEventName.compareTo(bEventName);
              });

              if (sortedEventIds.isEmpty) {
                return const Center(child: Text('לא נמצאו פריטים בצ\'קליסט'));
              }

              // Get current user ID for personal note display
              final userState = context.read<UserSelectionBloc>().state;
              final currentUserId =
                  userState is UserAuthenticated ? userState.user.id : null;

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: sortedEventIds.length,
                itemBuilder: (context, index) {
                  final eventId = sortedEventIds[index];
                  final items = groupedItems[eventId]!;
                  final event = items.first.event;

                  return ExpansionTile(
                    title: Text(event?.name ?? 'אירוע לא ידוע'),
                    subtitle: Text('${items.length} פריטים'),
                    children: items
                        .map((item) => ChecklistItemCard(
                              item: item,
                              allTeamMembers: allTeamMembers,
                              isAdmin: true,
                              currentUserId: currentUserId,
                              onTap: () => _showEditModal(item),
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
                                        authorRole: 'מנהל',
                                      ),
                                    );
                              },
                            ))
                        .toList(),
                  );
                },
              );
            }
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  bool _hasActiveFilters() {
    return _searchQuery.isNotEmpty ||
        _selectedEventId != null ||
        _selectedResponsibleId != null ||
        _statusFilter != null;
  }

  Widget _buildCenteredDropdownText(String text) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(
        width: double.infinity,
        child: Text(
          text,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ),
    );
  }

  Future<CrudActionResult> _waitForChecklistAction(
    void Function(CrudActionCompleter completion) dispatch,
  ) {
    final completion = Completer<CrudActionResult>();
    dispatch(completion);
    return completion.future;
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'סינון צ\'קליסט',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    // Event filter
                    BlocBuilder<EventBloc, EventState>(
                      builder: (context, state) {
                        if (state is EventsLoaded) {
                          final eventItems = [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: SizedBox.shrink(),
                            ),
                            ...state.events.map(
                              (event) => DropdownMenuItem<String>(
                                value: event.id,
                                child: _buildCenteredDropdownText(event.name),
                              ),
                            ),
                          ];
                          return DropdownButtonFormField<String>(
                            value: _selectedEventId,
                            alignment: AlignmentDirectional.center,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'אירוע',
                              border: OutlineInputBorder(),
                            ),
                            selectedItemBuilder: (context) => [
                              _buildCenteredDropdownText('כל האירועים'),
                              ...state.events.map(
                                (event) =>
                                    _buildCenteredDropdownText(event.name),
                              ),
                            ],
                            items: eventItems,
                            onChanged: (value) {
                              setModalState(() => _selectedEventId = value);
                              setState(() => _selectedEventId = value);
                            },
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(height: 16),
                    // Responsible filter
                    BlocBuilder<TeamBloc, TeamState>(
                      builder: (context, state) {
                        if (state is TeamLoaded) {
                          final memberItems = [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: SizedBox.shrink(),
                            ),
                            ...state.members.map(
                              (member) => DropdownMenuItem<String>(
                                value: member.id,
                                child: _buildCenteredDropdownText(member.name),
                              ),
                            ),
                          ];
                          return DropdownButtonFormField<String>(
                            value: _selectedResponsibleId,
                            alignment: AlignmentDirectional.center,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'אחראי',
                              border: OutlineInputBorder(),
                            ),
                            selectedItemBuilder: (context) => [
                              _buildCenteredDropdownText('כל האחראים'),
                              ...state.members.map(
                                (member) =>
                                    _buildCenteredDropdownText(member.name),
                              ),
                            ],
                            items: memberItems,
                            onChanged: (value) {
                              setModalState(
                                  () => _selectedResponsibleId = value);
                              setState(() => _selectedResponsibleId = value);
                            },
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(height: 16),
                    // Status filter
                    DropdownButtonFormField<bool>(
                      value: _statusFilter,
                      alignment: AlignmentDirectional.center,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'סטטוס',
                        border: OutlineInputBorder(),
                      ),
                      selectedItemBuilder: (context) => [
                        _buildCenteredDropdownText('הכל'),
                        _buildCenteredDropdownText('קיים (כן)'),
                        _buildCenteredDropdownText('לא קיים (לא)'),
                      ],
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: _buildCenteredDropdownText('הכל'),
                        ),
                        DropdownMenuItem(
                          value: true,
                          child: _buildCenteredDropdownText('קיים (כן)'),
                        ),
                        DropdownMenuItem(
                          value: false,
                          child: _buildCenteredDropdownText('לא קיים (לא)'),
                        ),
                      ],
                      onChanged: (value) {
                        setModalState(() => _statusFilter = value);
                        setState(() => _statusFilter = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setModalState(() {
                              _selectedEventId = null;
                              _selectedResponsibleId = null;
                              _statusFilter = null;
                            });
                            setState(() {
                              _selectedEventId = null;
                              _selectedResponsibleId = null;
                              _statusFilter = null;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('נקה'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('סגור'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditModal(ChecklistItem item) {
    // Get current user ID for tracking creator
    final userState = context.read<UserSelectionBloc>().state;
    final currentUserId =
        userState is UserAuthenticated ? userState.user.id : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) => ChecklistFormModal(
        item: item,
        currentUserId: currentUserId,
        onSave: (updatedItem) => _waitForChecklistAction(
          (completion) => context.read<ChecklistBloc>().add(
                UpdateChecklistItem(
                  updatedItem,
                  completion: completion,
                ),
              ),
        ),
        onDelete: () => _deleteItem(item),
      ),
    );
  }

  Future<CrudActionResult> _deleteItem(ChecklistItem item) {
    return _waitForChecklistAction(
      (completion) => context.read<ChecklistBloc>().add(
            DeleteChecklistItem(
              item.id,
              completion: completion,
            ),
          ),
    );
  }
}
