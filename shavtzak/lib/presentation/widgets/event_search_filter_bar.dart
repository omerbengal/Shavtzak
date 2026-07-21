import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/debug/logger.dart';
import '../../core/debug/search_action_logger.dart';
import '../bloc/category/category_bloc.dart';
import '../bloc/category/category_state.dart';
import '../screens/event/widgets/category_filter_modal.dart';

/// Reusable "search + category filter" bar, mirroring the `/admin/events` bar.
///
/// Renders a search field (with a clear button) plus a category filter button
/// with a count badge that opens the existing [CategoryFilterModal]. The
/// category button is shown only when categories are loaded and non-empty, so
/// it degrades gracefully where categories are unavailable (e.g. non-permanent
/// members whose role cannot read the categories collection).
///
/// The widget is controlled: the parent owns [searchQuery] and
/// [selectedCategoryIds] and updates them from the callbacks.
class EventSearchFilterBar extends StatefulWidget {
  const EventSearchFilterBar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.selectedCategoryIds,
    required this.onCategoryFilterChanged,
    this.hintText = 'חיפוש אירוע לפי שם או מיקום...',
    this.logField = 'eventFilterBar',
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  /// Current search query (owned by the parent).
  final String searchQuery;

  /// Called on every keystroke with the new query.
  final ValueChanged<String> onSearchChanged;

  /// Currently selected category IDs (owned by the parent).
  final Set<String> selectedCategoryIds;

  /// Called when the category selection changes in the modal.
  final ValueChanged<Set<String>> onCategoryFilterChanged;

  final String hintText;

  /// Identifier for debounced search logging (never logs raw text).
  final String logField;

  final EdgeInsetsGeometry padding;

  @override
  State<EventSearchFilterBar> createState() => _EventSearchFilterBarState();
}

class _EventSearchFilterBarState extends State<EventSearchFilterBar> {
  late final TextEditingController _controller;
  late final SearchActionLogger _searchLog;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchQuery);
    _searchLog = SearchActionLogger(widget.logField);
  }

  @override
  void didUpdateWidget(covariant EventSearchFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the field in sync when the parent programmatically changes the query
    // (e.g. clears it). Guard against clobbering the caret while typing.
    if (widget.searchQuery != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.searchQuery,
        selection:
            TextSelection.collapsed(offset: widget.searchQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchLog.dispose();
    super.dispose();
  }

  void _openCategoryFilter() {
    Logger.action('open:categoryFilterModal', {'field': widget.logField});
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CategoryFilterModal(
        selectedCategoryIds: widget.selectedCategoryIds,
        onFilterChanged: (selectedIds) {
          Logger.action('filter:categories',
              {'field': widget.logField, 'count': selectedIds.length});
          widget.onCategoryFilterChanged(selectedIds);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Clear button (only when there's text).
                if (widget.searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'נקה חיפוש',
                    onPressed: () {
                      Logger.action(
                          'tap:clearSearch', {'field': widget.logField});
                      _controller.clear();
                      _searchLog.onQueryChanged('');
                      widget.onSearchChanged('');
                    },
                  ),
                // Category filter button — only when categories exist.
                BlocBuilder<CategoryBloc, CategoryState>(
                  builder: (context, state) {
                    final hasCategories = state is CategoriesLoaded &&
                        state.activeCategories.isNotEmpty;
                    if (!hasCategories) return const SizedBox.shrink();
                    final count = widget.selectedCategoryIds.length;
                    return IconButton(
                      icon: Badge(
                        isLabelVisible: count > 0,
                        label: Text('$count'),
                        child: Icon(
                          Icons.filter_list,
                          color: count > 0 ? Colors.blue.shade700 : null,
                        ),
                      ),
                      tooltip: count == 0
                          ? 'סינון לפי קטגוריה'
                          : 'סינון: $count קטגוריות',
                      onPressed: _openCategoryFilter,
                    );
                  },
                ),
              ],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onChanged: (value) {
            _searchLog.onQueryChanged(value);
            widget.onSearchChanged(value);
          },
        ),
      ),
    );
  }
}
