import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'package:shavtzak/core/debug/logging_bloc_observer.dart';

class _FxState extends Equatable {
  const _FxState(this.x, this.y);
  final int x;
  final int y;
  @override
  List<Object?> get props => [x, y];
}

class _FxEvent {
  const _FxEvent();
}

class _FxBloc extends Bloc<_FxEvent, _FxState> {
  _FxBloc() : super(const _FxState(0, 0));
}

void main() {
  late LoggingBlocObserver observer;
  late _FxBloc bloc;

  setUp(() {
    DebugLogger.instance.debugClearForTests();
    observer = LoggingBlocObserver();
    bloc = _FxBloc();
  });

  tearDown(() async {
    await bloc.close();
  });

  test('onEvent records a blocDispatch event', () {
    observer.onEvent(bloc, const _FxEvent());
    final ev = DebugLogger.instance.events.single;
    expect(ev.type, LogEventType.blocDispatch);
    expect(ev.name, contains('_FxBloc'));
    expect(ev.name, contains('_FxEvent'));
  });

  test('onTransition records propsChanged by index', () {
    observer.onTransition(
      bloc,
      const Transition<_FxEvent, _FxState>(
        currentState: _FxState(0, 0),
        event: _FxEvent(),
        nextState: _FxState(0, 1),
      ),
    );
    final ev = DebugLogger.instance.events.single;
    expect(ev.type, LogEventType.blocEmit);
    expect(ev.name, contains('_FxBloc'));
    expect(ev.context['propsChanged'], [1]);
  });

  test('onTransition records "structural" when props lengths differ', () {
    final next = _FxStateExt(0, 1, 99);
    observer.onTransition(
      bloc,
      Transition<_FxEvent, _FxState>(
        currentState: const _FxState(0, 0),
        event: const _FxEvent(),
        nextState: next,
      ),
    );
    final ev = DebugLogger.instance.events.single;
    expect(ev.context['propsChanged'], ['structural']);
  });

  test('onError records a blocError with error class name', () {
    observer.onError(bloc, ArgumentError('boom'), StackTrace.current);
    final ev = DebugLogger.instance.events.single;
    expect(ev.type, LogEventType.blocError);
    expect(ev.context['error'], contains('ArgumentError'));
  });
}

class _FxStateExt extends _FxState {
  const _FxStateExt(super.x, super.y, this.z);
  final int z;
  @override
  List<Object?> get props => [x, y, z];
}
