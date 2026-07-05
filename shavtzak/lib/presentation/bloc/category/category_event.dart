import '../../../domain/entities/category.dart';
import '../../../core/utils/crud_action_result.dart';

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
  final int? colorValue;
  final CrudActionCompleter? completion;

  const CreateCategory(this.name, {this.colorValue, this.completion});
}

/// Update a category
class UpdateCategory extends CategoryEvent {
  final Category category;
  final CrudActionCompleter? completion;

  const UpdateCategory(this.category, {this.completion});
}

/// Rename a category
class RenameCategory extends CategoryEvent {
  final String categoryId;
  final String newName;
  final CrudActionCompleter? completion;

  const RenameCategory(this.categoryId, this.newName, {this.completion});
}

/// Delete (archive) a category
class DeleteCategory extends CategoryEvent {
  final String categoryId;
  final CrudActionCompleter? completion;

  const DeleteCategory(this.categoryId, {this.completion});
}

/// Permanently delete a category
class PermanentlyDeleteCategory extends CategoryEvent {
  final String categoryId;
  final CrudActionCompleter? completion;

  const PermanentlyDeleteCategory(this.categoryId, {this.completion});
}

/// Restore an archived category
class RestoreCategory extends CategoryEvent {
  final String categoryId;
  final CrudActionCompleter? completion;

  const RestoreCategory(this.categoryId, {this.completion});
}

/// Reorder categories
class ReorderCategories extends CategoryEvent {
  final List<Category> categories;

  const ReorderCategories(this.categories);
}
