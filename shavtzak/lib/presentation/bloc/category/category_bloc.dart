import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../domain/entities/category.dart' as domain_category;
import '../../../core/utils/crud_action_result.dart';
import 'category_event.dart';
import 'category_state.dart';

/// BLoC for managing Category state
class CategoryBloc extends Bloc<CategoryEvent, CategoryState> {
  final CategoryRepository _categoryRepository;

  // Flag to track if we're currently subscribed to prevent multiple listeners
  bool _isSubscribed = false;

  // Timestamp of last reorder to suppress stale stream emissions
  DateTime? _lastReorderTimestamp;

  static const _reorderGracePeriod = Duration(milliseconds: 1500);

  CategoryBloc(this._categoryRepository) : super(const CategoryInitial()) {
    on<LoadCategories>(_onLoadCategories);
    on<CreateCategory>(_onCreateCategory);
    on<UpdateCategory>(_onUpdateCategory);
    on<RenameCategory>(_onRenameCategory);
    on<DeleteCategory>(_onDeleteCategory);
    on<PermanentlyDeleteCategory>(_onPermanentlyDeleteCategory);
    on<RestoreCategory>(_onRestoreCategory);
    on<ReorderCategories>(_onReorderCategories);
  }

  /// Load all categories with real-time updates
  Future<void> _onLoadCategories(
    LoadCategories event,
    Emitter<CategoryState> emit,
  ) async {
    // If already subscribed, don't start another subscription
    if (_isSubscribed) {
      developer.log('CategoryBloc._onLoadCategories: Already subscribed, skipping', name: 'CategoryBloc');
      return;
    }

    emit(const CategoryLoading());
    _isSubscribed = true;

    try {
      await emit.forEach<List<domain_category.Category>>(
        _categoryRepository.watchCategories(),
        onData: (categories) {
          // Check if we're in the grace period after a reorder
          // If so, skip this emission to prevent showing stale data
          if (_lastReorderTimestamp != null) {
            final timeSinceReorder = DateTime.now().difference(_lastReorderTimestamp!);
            if (timeSinceReorder < _reorderGracePeriod) {
              developer.log(
                'CategoryBloc: Skipping emission ${timeSinceReorder.inMilliseconds}ms after reorder (grace period: ${_reorderGracePeriod.inMilliseconds}ms)',
                name: 'CategoryBloc',
              );
              // Return current state to skip this emission
              return state;
            } else {
              // Grace period over, clear the timestamp
              _lastReorderTimestamp = null;
            }
          }

          // Separate active and archived
          final active = categories.where((c) => !c.isArchived).toList();
          final archived = categories.where((c) => c.isArchived).toList();

          return CategoriesLoaded(
            activeCategories: active,
            archivedCategories: archived,
          );
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
          return CategoryError(error.toString());
        },
      ).then((_) {
        // Subscription ended (shouldn't happen with Firestore)
        _isSubscribed = false;
      });
    } catch (e) {
      _isSubscribed = false;
      developer.log('CategoryBloc._onLoadCategories: Error: $e', name: 'CategoryBloc');
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onCreateCategory(
    CreateCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _categoryRepository.createCategory(event.name);
      _completeActionSuccess(event.completion, 'הקטגוריה נוצרה בהצלחה');
    } catch (e) {
      _completeActionFailure(event.completion, 'שגיאה ביצירת קטגוריה: $e');
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onUpdateCategory(
    UpdateCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _categoryRepository.updateCategory(event.category);
      _completeActionSuccess(event.completion, 'הקטגוריה עודכנה בהצלחה');
    } catch (e) {
      _completeActionFailure(event.completion, 'שגיאה בעדכון קטגוריה: $e');
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onRenameCategory(
    RenameCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _categoryRepository.renameCategory(event.categoryId, event.newName);
      _completeActionSuccess(event.completion, 'שם הקטגוריה עודכן בהצלחה');
    } catch (e) {
      _completeActionFailure(event.completion, 'שגיאה בעדכון שם קטגוריה: $e');
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onDeleteCategory(
    DeleteCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _categoryRepository.deleteCategory(event.categoryId);
      _completeActionSuccess(event.completion, 'הקטגוריה הועברה לארכיון');
    } catch (e) {
      _completeActionFailure(event.completion, 'שגיאה בהעברת קטגוריה לארכיון: $e');
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onPermanentlyDeleteCategory(
    PermanentlyDeleteCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _categoryRepository.permanentlyDeleteCategory(event.categoryId);
      _completeActionSuccess(event.completion, 'הקטגוריה נמחקה לצמיתות');
    } catch (e) {
      _completeActionFailure(event.completion, 'שגיאה במחיקת קטגוריה: $e');
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onRestoreCategory(
    RestoreCategory event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      await _categoryRepository.restoreCategory(event.categoryId);
      _completeActionSuccess(event.completion, 'הקטגוריה שוחזרה בהצלחה');
    } catch (e) {
      _completeActionFailure(event.completion, 'שגיאה בשחזור קטגוריה: $e');
      emit(CategoryError(e.toString()));
    }
  }

  Future<void> _onReorderCategories(
    ReorderCategories event,
    Emitter<CategoryState> emit,
  ) async {
    try {
      // Set timestamp to suppress stale stream emissions during the write
      _lastReorderTimestamp = DateTime.now();

      developer.log(
        'CategoryBloc._onReorderCategories: Starting reorder, suppressing stream emissions for ${_reorderGracePeriod.inMilliseconds}ms',
        name: 'CategoryBloc',
      );

      // Don't emit optimistic state here - dialog handles optimistic UI with _pendingReorderedCategories
      // Just persist to database and let the stream handle updates naturally after grace period
      await _categoryRepository.reorderCategories(event.categories);

      developer.log(
        'CategoryBloc._onReorderCategories: Reorder complete',
        name: 'CategoryBloc',
      );
    } catch (e) {
      // Clear timestamp on error so we don't suppress legitimate error emissions
      _lastReorderTimestamp = null;
      emit(CategoryError(e.toString()));
    }
  }

  void _completeActionSuccess(
    CrudActionCompleter? completion, [
    String? message,
  ]) {
    completeCrudAction(completion, CrudActionResult.success(message));
  }

  void _completeActionFailure(
    CrudActionCompleter? completion,
    String message,
  ) {
    completeCrudAction(completion, CrudActionResult.failure(message));
  }
}
