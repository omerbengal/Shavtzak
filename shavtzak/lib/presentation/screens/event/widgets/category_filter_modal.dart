import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/debug/logger.dart';
import '../../../../domain/entities/category.dart';
import '../../../bloc/category/category_bloc.dart';
import '../../../bloc/category/category_state.dart';

/// Bottom sheet modal for filtering events by categories.
/// Applies filters immediately via callback when selections change.
class CategoryFilterModal extends StatefulWidget {
  final Set<String> selectedCategoryIds;
  final ValueChanged<Set<String>> onFilterChanged;

  const CategoryFilterModal({
    super.key,
    required this.selectedCategoryIds,
    required this.onFilterChanged,
  });

  @override
  State<CategoryFilterModal> createState() => _CategoryFilterModalState();
}

class _CategoryFilterModalState extends State<CategoryFilterModal> {
  late Set<String> _selectedCategoryIds;

  @override
  void initState() {
    super.initState();
    _selectedCategoryIds = Set.from(widget.selectedCategoryIds);
  }

  void _onSelectionChanged() {
    widget.onFilterChanged(Set.from(_selectedCategoryIds));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.filter_list, color: Colors.blue),
                  const SizedBox(width: 12),
                  const Text(
                    'סינון לפי קטגוריות',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Content - read categories reactively from BLoC
            Flexible(
              child: BlocBuilder<CategoryBloc, CategoryState>(
                builder: (context, categoryState) {
                  if (categoryState is CategoryLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final List<Category> categories =
                      categoryState is CategoriesLoaded
                          ? categoryState.activeCategories
                          : [];

                  if (categories.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.category_outlined, size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'אין קטגוריות זמינות',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'צור קטגוריות חדשות דרך ניהול קטגוריות',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final isSelected = _selectedCategoryIds.contains(category.id);

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (bool? checked) {
                          Logger.action('filter:categoryFilter', {'categoryId': category.id, 'on': checked});
                          setState(() {
                            if (checked == true) {
                              _selectedCategoryIds.add(category.id);
                            } else {
                              _selectedCategoryIds.remove(category.id);
                            }
                          });
                          _onSelectionChanged();
                        },
                        title: Text(
                          category.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Footer with Close and Clear buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Logger.action('tap:clearCategoryFilter');
                      setState(() {
                        _selectedCategoryIds.clear();
                      });
                      _onSelectionChanged();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('נקה'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Logger.action('tap:close:categoryFilterModal');
                      Navigator.pop(context);
                    },
                    child: const Text('סגור'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
