import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/event.dart';
import '../../../core/utils/filter_persistence.dart';
import '../../bloc/category/category_bloc.dart';
import '../../bloc/category/category_state.dart';

/// Modal for filtering assignments by events
class AssignmentFilterModal extends StatefulWidget {
  final List<Event> availableEvents;
  final Set<String> selectedEventIds;

  const AssignmentFilterModal({
    super.key,
    required this.availableEvents,
    required this.selectedEventIds,
  });

  @override
  State<AssignmentFilterModal> createState() => _AssignmentFilterModalState();
}

class _AssignmentFilterModalState extends State<AssignmentFilterModal> {
  late Set<String> _selectedEventIds;
  late Set<String> _selectedCategoryIds;
  bool _eventsExpanded = true;
  bool _categoriesExpanded = true;

  @override
  void initState() {
    super.initState();
    _selectedEventIds = Set.from(widget.selectedEventIds);
    _selectedCategoryIds = Set.from(FilterPersistence.selectedAssignmentCategoryIds);

    // Log dialog initialization
    developer.log(
      'AssignmentFilterModal: initState called - $_selectedEventIds events, $_selectedCategoryIds categories selected',
      name: 'AssignmentFilterModal',
    );

    // Log CategoryBloc state after a short delay to see what state we're in
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      final categoryBloc = context.read<CategoryBloc>();
      developer.log(
        'AssignmentFilterModal: CategoryBloc state after 100ms = ${categoryBloc.state.runtimeType}',
        name: 'AssignmentFilterModal',
      );
      if (categoryBloc.state is CategoriesLoaded) {
        final loadedState = categoryBloc.state as CategoriesLoaded;
        developer.log(
          'AssignmentFilterModal: CategoriesLoaded state has ${loadedState.activeCategories.length} active categories',
          name: 'AssignmentFilterModal',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Log build calls
    developer.log(
      'AssignmentFilterModal: build() called',
      name: 'AssignmentFilterModal',
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.filter_list, color: Colors.blue),
                    const SizedBox(width: 12),
                    const Text(
                      'סינון שיבוצים',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'סגור',
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: BlocBuilder<CategoryBloc, CategoryState>(
                  builder: (context, categoryState) {
                    // Log state in BlocBuilder
                    developer.log(
                      'AssignmentFilterModal: BlocBuilder called with state = ${categoryState.runtimeType}',
                      name: 'AssignmentFilterModal',
                    );

                    // Handle loading state
                    if (categoryState is CategoryLoading) {
                      developer.log('AssignmentFilterModal: Showing loading indicator', name: 'AssignmentFilterModal');
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (categoryState is CategoryError) {
                      developer.log('AssignmentFilterModal: Showing error state', name: 'AssignmentFilterModal');
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.red),
                            const SizedBox(height: 16),
                            Text(
                              'שגיאה בטעינת קטגוריות',
                              style: TextStyle(fontSize: 18, color: Colors.red),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              categoryState.message,
                              style: const TextStyle(fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }

                    final List<Category> categories = categoryState is CategoriesLoaded
                        ? categoryState.activeCategories
                        : [];

                    developer.log(
                      'AssignmentFilterModal: Extracted ${categories.length} categories from state (state type: ${categoryState.runtimeType})',
                      name: 'AssignmentFilterModal',
                    );

                    // Filter events based on selected categories
                    final filteredEvents = _selectedCategoryIds.isEmpty
                        ? widget.availableEvents
                        : widget.availableEvents.where((e) =>
                            _selectedCategoryIds.contains(e.categoryId)).toList();

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Categories section with dropdown arrow (always visible)
                          InkWell(
                            onTap: () {
                              setState(() {
                                _categoriesExpanded = !_categoriesExpanded;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _categoriesExpanded
                                        ? Icons.arrow_drop_down
                                        : Icons.arrow_left,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'קטגוריות',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_selectedCategoryIds.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${_selectedCategoryIds.length}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                          // Categories list
                          if (_categoriesExpanded) ...[
                              const SizedBox(height: 12),
                              if (categoryState is CategoryLoading || categoryState is CategoryInitial)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(32.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (categories.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Center(
                                    child: Text(
                                      'אין קטגוריות זמינות',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                ...categories.map((category) {
                                  final isSelected =
                                      _selectedCategoryIds.contains(category.id);
                                  return CheckboxListTile(
                                    value: isSelected,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          // Add category to selection
                                          _selectedCategoryIds.add(category.id);

                                          // Auto-select all events in this category
                                          for (final event in widget.availableEvents) {
                                            if (event.categoryId == category.id) {
                                              _selectedEventIds.add(event.id);
                                            }
                                          }
                                        } else {
                                          // Remove category from selection
                                          _selectedCategoryIds.remove(category.id);

                                          // Remove all events in this category from selection
                                          for (final event in widget.availableEvents) {
                                            if (event.categoryId == category.id) {
                                              _selectedEventIds.remove(event.id);
                                            }
                                          }
                                        }
                                      });
                                    },
                                    title: Text(
                                      category.name,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    controlAffinity: ListTileControlAffinity.leading,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 0),
                                    dense: true,
                                  );
                                }),
                              const SizedBox(height: 16),
                            ],

                          // Events section with dropdown arrow
                          InkWell(
                            onTap: () {
                              setState(() {
                                _eventsExpanded = !_eventsExpanded;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _eventsExpanded
                                        ? Icons.arrow_drop_down
                                        : Icons.arrow_left,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'אירועים',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_selectedEventIds.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${_selectedEventIds.length}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          // Events list
                          if (_eventsExpanded) ...[
                            const SizedBox(height: 12),
                            if (filteredEvents.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(
                                  child: Text(
                                    'אין אירועים זמינים לסינון',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              )
                            else
                              ...filteredEvents.map((event) {
                                final isSelected =
                                    _selectedEventIds.contains(event.id);
                                return CheckboxListTile(
                                  value: isSelected,
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedEventIds.add(event.id);
                                      } else {
                                        _selectedEventIds.remove(event.id);
                                      }
                                    });
                                  },
                                  title: Text(
                                    event.name,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    _formatEventDate(event),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 0),
                                  dense: true,
                                );
                              }),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Footer with buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Clear button (left side)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedEventIds.clear();
                          _selectedCategoryIds.clear();
                        });
                      },
                      child: const Text(
                        'ניקוי',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.red,
                        ),
                      ),
                    ),
                    // Cancel and Apply buttons (right side)
                    Row(
                      children: [
                        // Cancel button
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'ביטול',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Apply button
                        ElevatedButton(
                          onPressed: () {
                            // Save selected category IDs to filter persistence
                            FilterPersistence.selectedAssignmentCategoryIds = _selectedCategoryIds;
                            Navigator.of(context).pop(_selectedEventIds);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                          child: const Text(
                            'החל',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
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

  String _formatEventDate(Event event) {
    final startDate =
        '${event.startDate.day.toString().padLeft(2, '0')}/${event.startDate.month.toString().padLeft(2, '0')}';
    if (_isSameDay(event.startDate, event.endDate)) {
      return startDate;
    } else {
      final endDate =
          '${event.endDate.day.toString().padLeft(2, '0')}/${event.endDate.month.toString().padLeft(2, '0')}';
      return '$startDate - $endDate';
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}
