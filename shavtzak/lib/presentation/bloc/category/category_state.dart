import 'package:equatable/equatable.dart';
import '../../../domain/entities/category.dart';

/// Base class for Category states
abstract class CategoryState extends Equatable {
  const CategoryState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class CategoryInitial extends CategoryState {
  const CategoryInitial();
}

/// Loading state
class CategoryLoading extends CategoryState {
  const CategoryLoading();
}

/// Categories loaded successfully
class CategoriesLoaded extends CategoryState {
  final List<Category> activeCategories;
  final List<Category> archivedCategories;

  const CategoriesLoaded({
    required this.activeCategories,
    required this.archivedCategories,
  });

  @override
  List<Object?> get props => [activeCategories, archivedCategories];
}

/// Error state
class CategoryError extends CategoryState {
  final String message;

  const CategoryError(this.message);

  @override
  List<Object?> get props => [message];
}
