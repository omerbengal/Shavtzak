part of 'checklist_bloc.dart';

abstract class ChecklistState extends Equatable {
  const ChecklistState();

  @override
  List<Object?> get props => [];
}

class ChecklistInitial extends ChecklistState {}

class ChecklistLoading extends ChecklistState {}

class ChecklistLoaded extends ChecklistState {
  final List<ChecklistItem> items;

  const ChecklistLoaded(this.items);

  @override
  List<Object?> get props => [items];
}

class ChecklistError extends ChecklistState {
  final String message;

  const ChecklistError(this.message);

  @override
  List<Object?> get props => [message];
}

class UserChecklistLoaded extends ChecklistState {
  final List<ChecklistItem> responsibleItems;
  final List<ChecklistItem> ccItems;

  const UserChecklistLoaded({
    required this.responsibleItems,
    required this.ccItems,
  });

  @override
  List<Object?> get props => [responsibleItems, ccItems];
}

class ChecklistItemUpdated extends ChecklistState {
  final ChecklistItem item;

  const ChecklistItemUpdated(this.item);

  @override
  List<Object?> get props => [item];
}