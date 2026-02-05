import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/category_repository.dart';
import 'category_event.dart';
import 'category_state.dart';

/// BLoC for managing Category state
class CategoryBloc extends Bloc<CategoryEvent, CategoryState> {
  final CategoryRepository _categoryRepository;
  StreamSubscription<List<dynamic>>? _categoriesSubscription;

  CategoryBloc(this._categoryRepository) : super(const CategoryInitial()) {
    on<LoadCategories>(_onLoadCategories);
    on<CreateCategory>(_onCreateCategory);
    on<UpdateCategory>(_onUpdateCategory);
    on<RenameCategory>(_onRenameCategory);
    on<DeleteCategory>(_onDeleteCategory);
    on<PermanentlyDeleteCategory>(_onPermanentlyDeleteCategory);
    on<RestoreCategory>(_onRestoreCategory);
    on<ReorderCategories>(_onReorderCategories);
    on<CategoriesDataUpdated>(_onCategoriesDataUpdated);
  }

  @override
  Future<void> close() {
    // Cancel subscription when BLoC is closed
    _categoriesSubscription?.cancel();
    return super.close();
  }

  Future<void> _onLoadCategories(
    LoadCategories event,
    Emitter<CategoryState> emit,
  ) async {
    emit(const CategoryLoading());

    // Cancel previous subscription before starting new one to prevent memory leaks
    await _categoriesSubscription?.cancel();

    try {
      // Subscribe to categories stream
      _categoriesSubscription = _categoryRepository.watchCategories().listen(
        (categories) {
          // Add internal event when data arrives
          add(CategoriesDataUpdated(categories));
        },
        onError: (error, stackTrace) {
          if (kDebugMode) {
            developer.log(
              'CategoryBloc: Error loading categories - $error',
              name: 'CategoryBloc',
              error: error,
              stackTrace: stackTrace,
            );
          }
          // Emit error state
          emit(CategoryError(error.toString()));
        },
      );
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onCategoriesDataUpdated(
    CategoriesDataUpdated event,
    Emitter<CategoryState> emit,
  ) async {
    // Separate active and archived
    final active = event.categories.where((c) => !c.isArchived).toList();
    final archived = event.categories.where((c) => c.isArchived).toList();

    if (kDebugMode) {
      developer.log(
        'CategoryBloc: Categories updated - ${event.categories.length} total, ${active.length} active, ${archived.length} archived',
        name: 'CategoryBloc',
      );
    }

    emit(CategoriesLoaded(
      activeCategories: active,
      archivedCategories: archived,
    ));
  }

  Future<void> _onCreateCategory(
    CreateCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _categoryRepository.createCategory(event.name);
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onUpdateCategory(
    UpdateCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _categoryRepository.updateCategory(event.category);
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onRenameCategory(
    RenameCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _categoryRepository.renameCategory(event.categoryId, event.newName);
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onDeleteCategory(
    DeleteCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _categoryRepository.deleteCategory(event.categoryId);
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onPermanentlyDeleteCategory(
    PermanentlyDeleteCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _categoryRepository.permanentlyDeleteCategory(event.categoryId);
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onRestoreCategory(
    RestoreCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _categoryRepository.restoreCategory(event.categoryId);
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onReorderCategories(
    ReorderCategories event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      // Optimistic update - emit new order immediately
      final currentState = state;
      if (currentState is CategoriesLoaded) {
        emit(CategoriesLoaded(
          activeCategories: event.categories,
          archivedCategories: currentState.archivedCategories,
        ));
      }

      // Then persist to database
      await _categoryRepository.reorderCategories(event.categories);
    } catch (e) {
      emit(CategoryError(e.toString()));
    }
  }
}
