import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/role_types.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';
import 'team_form_screen.dart';

class TeamListScreen extends StatefulWidget {
  const TeamListScreen({super.key});

  @override
  State<TeamListScreen> createState() => _TeamListScreenState();
}

class _TeamListScreenState extends State<TeamListScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;
  bool _showActiveOnly = false;

  @override
  void initState() {
    super.initState();
    // Load team members on init
    context.read<TeamBloc>().add(const LoadTeamMembers());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      context.read<TeamBloc>().add(const LoadTeamMembers());
    } else {
      context.read<TeamBloc>().add(SearchTeamMembers(query));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: _showSearch
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'חיפוש חבר צוות...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.black54),
                  ),
                  style: const TextStyle(color: Colors.black),
                  onChanged: _onSearchChanged,
                )
              : const Text(AppStrings.team),
          actions: [
            IconButton(
              icon: Icon(_showSearch ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchController.clear();
                    context.read<TeamBloc>().add(const LoadTeamMembers());
                  }
                });
              },
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('הצג פעילים בלבד'),
                Switch(
                  value: _showActiveOnly,
                  onChanged: (value) {
                    setState(() {
                      _showActiveOnly = value;
                    });
                    if (value) {
                      context.read<TeamBloc>().add(const LoadActiveTeamMembers());
                    } else {
                      context.read<TeamBloc>().add(const LoadTeamMembers());
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        body: BlocConsumer<TeamBloc, TeamState>(
          listener: (context, state) {
            if (state is TeamError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                ),
              );
            } else if (state is TeamMemberOperationSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
          builder: (context, state) {
            if (state is TeamLoading || state is TeamMemberOperating) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (state is TeamEmpty) {
              return _buildEmptyState(state.message);
            }

            if (state is TeamLoaded) {
              return _buildTeamList(state);
            }

            if (state is TeamError) {
              return _buildErrorState(state.message);
            }

            return _buildEmptyState('טוען...');
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const TeamFormScreen(),
              ),
            );
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildTeamList(TeamLoaded state) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<TeamBloc>().add(const RefreshTeamMembers());
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: Column(
        children: [
          // Statistics header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('סך הכל', state.totalCount.toString()),
                _buildStatItem('פעילים', state.activeCount.toString()),
                _buildStatItem('לא פעילים', state.inactiveCount.toString()),
              ],
            ),
          ),
          // Team list
          Expanded(
            child: ListView.builder(
              itemCount: state.members.length,
              itemBuilder: (context, index) {
                final member = state.members[index];
                return _buildTeamMemberCard(member);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildTeamMemberCard(TeamMember member) {
    // Count active roles
    final activeRoles =
        member.roleCapabilities.values.where((v) => v == true).length;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: member.isActive ? Colors.green : Colors.grey,
          child: Text(
            member.name.isNotEmpty ? member.name[0] : '?',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(
          member.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: member.isActive ? Colors.black : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '$activeRoles תפקידים',
              style: const TextStyle(fontSize: 12),
            ),
            if (member.constraints.isNotEmpty)
              Text(
                '${member.constraints.length} מגבלות',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
          ],
        ),
        trailing: member.isActive
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.cancel, color: Colors.grey),
        onTap: () {
          // Navigate to team member detail screen
          // TODO: Implement navigation
          _showMemberDetail(member);
        },
      ),
    );
  }

  void _showMemberDetail(TeamMember member) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: scrollController,
                children: [
                  // Header
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor:
                            member.isActive ? Colors.green : Colors.grey,
                        child: Text(
                          member.name.isNotEmpty ? member.name[0] : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member.name,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              member.isActive ? 'פעיל' : 'לא פעיל',
                              style: TextStyle(
                                color: member.isActive
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  // Role capabilities
                  const Text(
                    'תפקידים',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: RoleType.values.map((role) {
                      final canDo = member.canPerformRole(role);
                      return Chip(
                        label: Text(role.hebrewName),
                        backgroundColor:
                            canDo ? Colors.blue.shade100 : Colors.grey.shade200,
                        side: BorderSide(
                          color: canDo ? Colors.blue : Colors.grey,
                        ),
                      );
                    }).toList(),
                  ),

                  // Constraints
                  if (member.constraints.isNotEmpty) ...[
                    const Divider(height: 32),
                    const Text(
                      'מגבלות זמן',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...member.constraints.map((constraint) {
                      return ListTile(
                        leading: const Icon(Icons.event_busy, color: Colors.orange),
                        title: Text(
                          constraint.endDate != null
                              ? '${_formatDate(constraint.startDate)} - ${_formatDate(constraint.endDate!)}'
                              : _formatDate(constraint.startDate),
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 16),

                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  TeamFormScreen(member: member),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('ערוך'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          if (member.isActive) {
                            context
                                .read<TeamBloc>()
                                .add(DeactivateTeamMember(member.id));
                          } else {
                            context
                                .read<TeamBloc>()
                                .add(ReactivateTeamMember(member.id));
                          }
                        },
                        icon: Icon(
                            member.isActive ? Icons.cancel : Icons.check_circle),
                        label: Text(member.isActive ? 'השבת' : 'הפעל'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Delete button
                  TextButton.icon(
                    onPressed: () async {
                      // Store BLoC reference before closing modal
                      final teamBloc = context.read<TeamBloc>();
                      Navigator.pop(context);

                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => Directionality(
                          textDirection: TextDirection.rtl,
                          child: AlertDialog(
                            title: const Text('מחיקת חבר צוות'),
                            content: Text(
                              'האם אתה בטוח שברצונך למחוק את ${member.name}?\nפעולה זו תמחק גם את כל השיבוצים שלו.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('ביטול'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('מחק'),
                              ),
                            ],
                          ),
                        ),
                      );

                      if (confirmed == true) {
                        teamBloc.add(DeleteTeamMember(member.id));
                      }
                    },
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text(
                      'מחק חבר צוות',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TeamFormScreen(),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('הוסף חבר צוות ראשון'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 18,
              color: Colors.red,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              context.read<TeamBloc>().add(const LoadTeamMembers());
            },
            icon: const Icon(Icons.refresh),
            label: const Text('נסה שוב'),
          ),
        ],
      ),
    );
  }
}
