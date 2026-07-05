import 'package:uuid/uuid.dart';
import '../../domain/entities/category.dart';
import '../data_sources/database_interface.dart';

/// Repository for Category operations
class CategoryRepository {
  final DatabaseInterface _database;

  CategoryRepository(this._database);

  /// Watch all categories in real-time
  Stream<List<Category>> watchCategories() {
    return _database.watchCategories();
  }

  /// Watch active categories in real-time
  Stream<List<Category>> watchActiveCategories() {
    return _database.watchActiveCategories();
  }

  /// Get all categories
  Future<List<Category>> getCategories() {
    return _database.getCategories();
  }

  /// Get active categories
  Future<List<Category>> getActiveCategories() {
    return _database.getActiveCategories();
  }

  /// Create a new category
  Future<Category> createCategory(String name, {int? sortOrder, int? colorValue}) async {
    final now = DateTime.now();
    final categories = await getCategories();

    // If sortOrder not provided, use max existing sortOrder + 1
    // This ensures newly created categories get sortOrder larger than ALL existing categories
    // (both archived and non-archived), preventing duplicate sortOrders when archived items are restored
    final maxSortOrder = categories.isEmpty
        ? -1
        : categories.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b);
    final finalSortOrder = sortOrder ?? (maxSortOrder + 1);

    final category = Category(
      id: const Uuid().v4(),
      name: name,
      sortOrder: finalSortOrder,
      isArchived: false,
      colorValue: colorValue,
      createdAt: now,
      updatedAt: now,
    );

    await _database.insertCategory(category);
    return category;
  }

  /// Update an existing category
  Future<Category> updateCategory(Category category) async {
    final updatedCategory = category.copyWith(
      updatedAt: DateTime.now(),
    );

    await _database.updateCategory(updatedCategory);
    return updatedCategory;
  }

  /// Rename a category
  Future<Category> renameCategory(String categoryId, String newName) async {
    final category = await _database.getCategoryById(categoryId);
    if (category == null) {
      throw Exception('Category not found: $categoryId');
    }

    return updateCategory(category.copyWith(name: newName));
  }

  /// Delete (soft archive) a category
  Future<void> deleteCategory(String id) async {
    await _database.deleteCategory(id);
  }

  /// Permanently delete a category
  Future<void> permanentlyDeleteCategory(String id) async {
    await _database.permanentlyDeleteCategory(id);
  }

  /// Restore an archived category
  Future<void> restoreCategory(String id) async {
    await _database.restoreCategory(id);
  }

  /// Reorder categories - updates sortOrder for all categories
  Future<void> reorderCategories(List<Category> categories) async {
    // Update sortOrder for each category
    for (int i = 0; i < categories.length; i++) {
      final category = categories[i];
      if (category.sortOrder != i) {
        final updated = category.copyWith(
          sortOrder: i,
          updatedAt: DateTime.now(),
        );
        await _database.updateCategory(updated);
      }
    }
  }
}
