import '../../../domain/entities/category.dart';

/// Base class for Category events
abstract class CategoryEvent {
  const CategoryEvent();
}

/// Load all categories
class LoadCategories extends CategoryEvent {
  const LoadCategories();
}

/// Create a new category
class CreateCategory extends CategoryEvent {
  final String name;

  const CreateCategory(this.name);
}

/// Update a category
class UpdateCategory extends CategoryEvent {
  final Category category;

  const UpdateCategory(this.category);
}

/// Rename a category
class RenameCategory extends CategoryEvent {
  final String categoryId;
  final String newName;

  const RenameCategory(this.categoryId, this.newName);
}

/// Delete (archive) a category
class DeleteCategory extends CategoryEvent {
  final String categoryId;

  const DeleteCategory(this.categoryId);
}

/// Permanently delete a category
class PermanentlyDeleteCategory extends CategoryEvent {
  final String categoryId;

  const PermanentlyDeleteCategory(this.categoryId);
}

/// Restore an archived category
class RestoreCategory extends CategoryEvent {
  final String categoryId;

  const RestoreCategory(this.categoryId);
}

/// Reorder categories
class ReorderCategories extends CategoryEvent {
  final List<Category> categories;

  const ReorderCategories(this.categories);
}
