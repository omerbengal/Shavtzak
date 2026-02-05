import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../domain/entities/category.dart';
import '../../../../data/repositories/event_repository.dart';
import '../../../bloc/category/category_bloc.dart';
import '../../../bloc/category/category_event.dart';
import '../../../bloc/category/category_state.dart';
import '../../../widgets/loading_overlay.dart';

/// Dialog for managing categories (add, rename, archive, restore, reorder)
class CategoryManagementDialog extends StatefulWidget {
  const CategoryManagementDialog({super.key});

  @override
  State<CategoryManagementDialog> createState() => _CategoryManagementDialogState();
}

class _CategoryManagementDialogState extends State<CategoryManagementDialog> {
  bool _showArchive = false;
  bool _isLoading = false;

  /// Local optimistic state for reordering - updates immediately via setState
  /// before BLoC/Firestore responds. Cleared when BLoC state updates.
  List<Category>? _pendingReorderedCategories;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Dialog(
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
                    _showArchive ? 'ארכיון קטגוריות' : 'ניהול קטגוריות',
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
                child: BlocConsumer<CategoryBloc, CategoryState>(
                  listener: (context, state) {
                    // Clear pending reorder state when BLoC updates (Firestore caught up)
                    if (state is CategoriesLoaded && _pendingReorderedCategories != null) {
                      setState(() {
                        _pendingReorderedCategories = null;
                        _isLoading = false;
                      });
                    } else if (state is CategoriesLoaded && _isLoading) {
                      setState(() {
                        _isLoading = false;
                      });
                    }

                    if (state is CategoryError) {
                      setState(() => _isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(state.message),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  builder: (context, state) {
                    if (state is CategoryLoading) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (state is CategoriesLoaded) {
                      return _showArchive
                          ? _buildArchiveView(state)
                          : _buildMainView(state);
                    } else if (state is CategoryError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.red),
                            const SizedBox(height: 16),
                            Text('שגיאה בטעינת קטגוריות', style: TextStyle(fontSize: 18, color: Colors.red)),
                            const SizedBox(height: 8),
                            Text(
                              state.message,
                              style: const TextStyle(fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    } else {
                      return const Center(child: Text('טוען קטגוריות...'));
                    }
                  },
                ),
              ),
              // Add new category button (only in main view)
              if (!_showArchive)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showAddCategoryDialog(context),
                      icon: const Icon(Icons.add),
                      label: const Text('צור קטגוריה חדשה'),
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
          LoadingOverlay(isLoading: _isLoading, message: 'מעבד...'),
        ],
      ),
    );
  }

  /// Build main view (active categories)
  Widget _buildMainView(CategoriesLoaded state) {
    // Use pending reordered categories if available (optimistic UI), otherwise use BLoC state
    final activeCategories = _pendingReorderedCategories ?? state.activeCategories;

    if (activeCategories.isEmpty) {
      return const Center(
        child: Text('אין קטגוריות זמינות'),
      );
    }

    return ReorderableListView.builder(
      itemCount: activeCategories.length,
      onReorder: (oldIndex, newIndex) {
        final categories = List<Category>.from(activeCategories);
        if (newIndex > oldIndex) {
          newIndex -= 1;
        }
        final category = categories.removeAt(oldIndex);
        categories.insert(newIndex, category);

        // Optimistic UI update: setState is synchronous, prevents jump-back
        setState(() {
          _pendingReorderedCategories = categories;
        });

        // Dispatch to BLoC for persistence (async)
        context.read<CategoryBloc>().add(ReorderCategories(categories));
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Transform(
                transform: Matrix4.identity()
                  ..scale(1.0, 1.0), // Prevent any transformation
                alignment: Alignment.center,
                child: child,
              ),
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final category = activeCategories[index];
        return Container(
          key: ValueKey(category.id),
          child: _buildCategoryListTile(category, isArchived: false),
        );
      },
    );
  }

  /// Build archive view (archived categories)
  Widget _buildArchiveView(CategoriesLoaded state) {
    final archivedCategories = state.archivedCategories;

    if (archivedCategories.isEmpty) {
      return const Center(
        child: Text('אין קטגוריות בארכיון'),
      );
    }

    return ListView.builder(
      itemCount: archivedCategories.length,
      itemBuilder: (context, index) {
        final category = archivedCategories[index];
        return _buildCategoryListTile(category, isArchived: true);
      },
    );
  }

  /// Build a list tile for a category
  Widget _buildCategoryListTile(Category category, {required bool isArchived}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: ListTile(
        leading: isArchived
            ? const Icon(Icons.archive, color: Colors.grey)
            : const Icon(Icons.category, color: Colors.blue),
        title: Text(
          category.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isArchived ? Colors.grey : Colors.black,
          ),
        ),
        subtitle: Text(
          isArchived ? 'בארכיון' : 'פעיל',
          style: TextStyle(
            color: isArchived ? Colors.grey : Colors.green,
          ),
        ),
        trailing: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isArchived) ...[
                // Restore button
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      context.read<CategoryBloc>().add(RestoreCategory(category.id));
                    },
                    icon: const Icon(Icons.restore, size: 16, color: Colors.white),
                    label: const Text('שחזר'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              ] else ...[
                // Reorder handle icon
                const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
                const SizedBox(width: 4),
                // Archive button
                IconButton(
                  icon: const Icon(Icons.archive, color: Colors.orange, size: 20),
                  tooltip: 'העבר לארכיון',
                  onPressed: () => _confirmArchiveCategory(context, category),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                // Delete button
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  tooltip: 'מחק לצמיתות',
                  onPressed: () => _confirmDeleteCategory(context, category),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
        ),
        onTap: isArchived
            ? null
            : () => _showRenameDialog(context, category),
      ),
    );
  }

  /// Show confirmation dialog for archiving a category
  Future<void> _confirmArchiveCategory(BuildContext context, Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('העבר לארכיון?'),
          content: Text('האם להעביר את הקטגוריה "${category.name}" לארכיון?\n\nניתן יהיה לשחזר את הקטגוריה מהארכיון לאחר מכן.'),
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

    if (confirmed == true && context.mounted) {
      context.read<CategoryBloc>().add(DeleteCategory(category.id));
    }
  }

  /// Show confirmation dialog for permanently deleting a category.
  /// If events use this category, the admin is prompted to either
  /// clear the association on all events and then delete, or archive instead.
  Future<void> _confirmDeleteCategory(BuildContext context, Category category) async {
    // Check if any events reference this category
    final eventRepo = context.read<EventRepository>();
    final allEvents = await eventRepo.getAllEvents();
    final affectedEvents = allEvents.where((e) => e.categoryId == category.id).toList();

    if (!context.mounted) return;

    if (affectedEvents.isNotEmpty) {
      // Events use this category — offer: archive, or clear + delete
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              'מחק קטגוריה "${category.name}"?',
              style: const TextStyle(color: Colors.red),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'אירועים שמשויכים לקטגוריה:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...affectedEvents.map((event) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(event.name),
                    ],
                  ),
                )),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('ביטול'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop('archive'),
                icon: const Icon(Icons.archive, color: Colors.white),
                label: const Text('העבר לארכיון'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop('clear_and_delete'),
                icon: const Icon(Icons.delete, color: Colors.white),
                label: const Text('הסר מכל האירועים ומחק לצמיתות'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );

      if (!context.mounted) return;

      if (choice == 'archive') {
        context.read<CategoryBloc>().add(DeleteCategory(category.id));
      } else if (choice == 'clear_and_delete') {
        setState(() => _isLoading = true);
        // Clear categoryId on every affected event
        for (final event in affectedEvents) {
          await eventRepo.updateEvent(event.copyWith(clearCategoryId: true));
        }
        // Now safe to permanently delete the category
        if (context.mounted) {
          context.read<CategoryBloc>().add(PermanentlyDeleteCategory(category.id));
        }
        // _isLoading is cleared by the BlocListener when CategoriesLoaded arrives
      }
    } else {
      // No events use this category — simple confirmation
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('מחק קטגוריה?', style: TextStyle(color: Colors.red)),
            content: Text('האם למחוק את הקטגוריה "${category.name}" לצמיתות?\n\nלא ניתן יהיה לשחזר את הקטגוריה לאחר מחיקה!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('מחק לצמיתות'),
              ),
            ],
          ),
        ),
      );

      if (confirmed == true && context.mounted) {
        context.read<CategoryBloc>().add(PermanentlyDeleteCategory(category.id));
      }
    }
  }

  /// Show dialog to add a new category
  void _showAddCategoryDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('צור קטגוריה חדשה'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'שם הקטגוריה',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  context.read<CategoryBloc>().add(CreateCategory(
                        controller.text.trim(),
                      ));
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('צור'),
            ),
          ],
        ),
      ),
    );
  }

  /// Show dialog to rename a category
  void _showRenameDialog(BuildContext context, Category category) {
    final controller = TextEditingController(text: category.name);

    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('שנה שם קטגוריה'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'שם הקטגוריה',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty &&
                    controller.text.trim() != category.name) {
                  context.read<CategoryBloc>().add(RenameCategory(
                        category.id,
                        controller.text.trim(),
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
