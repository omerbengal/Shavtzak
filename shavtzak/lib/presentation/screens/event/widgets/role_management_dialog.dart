import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/entities/role.dart';
import '../../../bloc/role/role_bloc.dart';
import '../../../bloc/role/role_event.dart';
import '../../../bloc/role/role_state.dart';

/// Dialog for managing roles (add, rename, archive, restore, reorder, toggle visibility)
class RoleManagementDialog extends StatefulWidget {
  const RoleManagementDialog({super.key});

  @override
  State<RoleManagementDialog> createState() => _RoleManagementDialogState();
}

class _RoleManagementDialogState extends State<RoleManagementDialog> {
  bool _showArchive = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _showArchive ? 'ארכיון תפקידים' : 'ניהול תפקידים',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      // Toggle archive view button
                      IconButton(
                        icon: Icon(_showArchive ? Icons.list : Icons.history),
                        onPressed: () {
                          setState(() {
                            _showArchive = !_showArchive;
                          });
                        },
                        tooltip: _showArchive ? 'חזרה לרשימה הראשית' : 'צפייה בארכיון',
                      ),
                      // Close button
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Content
              Expanded(
                child: BlocConsumer<RoleBloc, RoleState>(
                  listener: (context, state) {
                    if (state is RoleError) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(state.message),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  builder: (context, state) {
                    if (state is RoleLoading) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (state is RolesLoaded) {
                      return _showArchive
                          ? _buildArchiveView(state)
                          : _buildMainView(state);
                    } else if (state is RolesEmpty) {
                      return Center(child: Text(state.message));
                    } else {
                      return const Center(child: Text('טוען תפקידים...'));
                    }
                  },
                ),
              ),
              // Add new role button (only in main view)
              if (!_showArchive)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showAddRoleDialog(context),
                      icon: const Icon(Icons.add),
                      label: const Text('הוסף תפקיד חדש'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build main view (non-archived roles)
  Widget _buildMainView(RolesLoaded state) {
    final activeRoles = state.activeRoles;

    if (activeRoles.isEmpty) {
      return const Center(
        child: Text('אין תפקידים זמינים'),
      );
    }

    return ReorderableListView.builder(
      itemCount: activeRoles.length,
      onReorder: (oldIndex, newIndex) {
        final roles = List<Role>.from(activeRoles);
        if (newIndex > oldIndex) {
          newIndex -= 1;
        }
        final role = roles.removeAt(oldIndex);
        roles.insert(newIndex, role);

        // Update sort order and dispatch to BLoC
        context.read<RoleBloc>().add(ReorderRoles(roles));
      },
      itemBuilder: (context, index) {
        final role = activeRoles[index];
        return Dismissible(
          key: ValueKey(role.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            child: const Icon(Icons.archive, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) => Directionality(
                textDirection: TextDirection.rtl,
                child: AlertDialog(
                  title: const Text('העבר לארכיון?'),
                  content: Text('האם להעביר את התפקיד "${role.hebrewName}" לארכיון?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('ביטול'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('העבר לארכיון'),
                    ),
                  ],
                ),
              ),
            );
          },
          onDismissed: (direction) {
            context.read<RoleBloc>().add(ArchiveRole(role.id));
          },
          child: _buildRoleListTile(role, isArchived: false),
        );
      },
    );
  }

  /// Build archive view (archived roles)
  Widget _buildArchiveView(RolesLoaded state) {
    final archivedRoles = state.archivedRoles;

    if (archivedRoles.isEmpty) {
      return const Center(
        child: Text('אין תפקידים בארכיון'),
      );
    }

    return ListView.builder(
      itemCount: archivedRoles.length,
      itemBuilder: (context, index) {
        final role = archivedRoles[index];
        return _buildRoleListTile(role, isArchived: true);
      },
    );
  }

  /// Build a list tile for a role
  Widget _buildRoleListTile(Role role, {required bool isArchived}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: isArchived
            ? const Icon(Icons.archive, color: Colors.grey)
            : Icon(
                role.isVisible ? Icons.visibility : Icons.visibility_off,
                color: role.isVisible ? Colors.green : Colors.grey,
              ),
        title: Text(
          role.hebrewName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isArchived ? Colors.grey : Colors.black,
          ),
        ),
        subtitle: Text(
          isArchived
              ? 'בארכיון'
              : role.isVisible
                  ? 'פעיל'
                  : 'לא פעיל',
          style: TextStyle(
            color: isArchived
                ? Colors.grey
                : role.isVisible
                    ? Colors.green
                    : Colors.orange,
          ),
        ),
        trailing: isArchived
            ? ElevatedButton.icon(
                onPressed: () {
                  context.read<RoleBloc>().add(RestoreRole(role.id));
                },
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('שחזר'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Toggle visibility button
                  IconButton(
                    icon: Icon(
                      role.isVisible ? Icons.visibility_off : Icons.visibility,
                    ),
                    tooltip: role.isVisible ? 'הסתר' : 'הצג',
                    onPressed: () {
                      context.read<RoleBloc>().add(ToggleRoleVisibility(role.id));
                    },
                  ),
                  // Reorder handle (this is implicit with ReorderableListView)
                  const Icon(Icons.drag_handle, color: Colors.grey),
                ],
              ),
        onTap: isArchived
            ? null
            : () => _showRenameDialog(context, role),
      ),
    );
  }

  /// Show dialog to add a new role
  void _showAddRoleDialog(BuildContext context) {
    final controller = TextEditingController();
    bool isVisible = true;

    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (statefulContext, setState) {
            return AlertDialog(
              title: const Text('הוסף תפקיד חדש'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'שם התפקיד בעברית',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: isVisible,
                        onChanged: (value) {
                          setState(() {
                            isVisible = value ?? true;
                          });
                        },
                      ),
                      const Text('תפקיד פעיל (מוצג בהגדרות אירוע)'),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('ביטול'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (controller.text.trim().isNotEmpty) {
                      context.read<RoleBloc>().add(CreateRole(
                            hebrewName: controller.text.trim(),
                            isVisible: isVisible,
                          ));
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: const Text('הוסף'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Show dialog to rename a role
  void _showRenameDialog(BuildContext context, Role role) {
    final controller = TextEditingController(text: role.hebrewName);

    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('שנה שם תפקיד'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'שם התפקיד בעברית',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty &&
                    controller.text.trim() != role.hebrewName) {
                  context.read<RoleBloc>().add(RenameRole(
                        roleId: role.id,
                        newHebrewName: controller.text.trim(),
                      ));
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    );
  }
}
