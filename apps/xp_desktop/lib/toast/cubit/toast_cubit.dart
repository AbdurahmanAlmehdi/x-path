import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

/// A short message about something that just happened, with an [action]
/// such as Undo.
class Toast extends Equatable {
  /// Creates a toast; [action] and [onAction] come together.
  const new({
    required this.id,
    required this.message,
    this.action,
    this.onAction,
    this.owner,
  }) : assert(
         (action == null) == (onAction == null),
         'An action needs its label and what it does.',
       );

  /// Tells it apart from the others shown.
  final int id;
  final String message;

  /// The label of what [onAction] does.
  final String? action;
  final void Function()? onAction;

  /// What shows the toast, such as the page whose change it undoes: the
  /// toast goes with it (`ToastCubit.dismissOf`).
  final Object? owner;

  static const _short = Duration(seconds: 4);
  static const _long = Duration(seconds: 6);

  /// How long it stays: longer when it offers an action.
  Duration get duration => action == null ? _short : _long;

  @override
  List<Object?> get props => [id, message, action];
}

/// The toasts shown, oldest first.
class ToastState extends Equatable {
  const new([this.toasts = const []]);

  final List<Toast> toasts;

  @override
  List<Object?> get props => [toasts];
}

/// Shows toasts, bottom right, each for its [Toast.duration]: at most
/// [limit] at once, the oldest going first.
class ToastCubit extends Cubit<ToastState> {
  new() : super(const ToastState());

  /// The most toasts shown at once.
  static const limit = 3;

  final _timers = <int, Timer>{};
  var _next = 0;

  /// Shows [message], with [action] and [onAction] when it offers one, for
  /// [owner] when given; its id.
  int show(
    String message, {
    String? action,
    void Function()? onAction,
    Object? owner,
  }) {
    final toast = Toast(
      id: _next++,
      message: message,
      action: action,
      onAction: onAction,
      owner: owner,
    );
    final shown = [...state.toasts, toast];
    final over = max(0, shown.length - limit);
    for (final old in shown.take(over)) {
      _timers.remove(old.id)?.cancel();
    }
    emit(ToastState(shown.skip(over).toList()));
    _timers[toast.id] = Timer(toast.duration, () => dismiss(toast.id));
    return toast.id;
  }

  /// Takes the toast [id] away.
  void dismiss(int id) {
    _timers.remove(id)?.cancel();
    if (isClosed) return;
    emit(
      ToastState([
        for (final t in state.toasts)
          if (t.id != id) t,
      ]),
    );
  }

  /// Takes away the toasts of [owner], whose actions would no longer
  /// reach it.
  void dismissOf(Object owner) {
    for (final toast in state.toasts) {
      if (identical(toast.owner, owner)) dismiss(toast.id);
    }
  }

  /// Does what the toast [id] offers, and takes it away.
  void act(int id) {
    final toast = state.toasts.where((t) => t.id == id).firstOrNull;
    dismiss(id);
    toast?.onAction?.call();
  }

  @override
  Future<void> close() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    return super.close();
  }
}
