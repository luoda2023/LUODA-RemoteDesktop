import 'dart:async';

import 'package:flutter/foundation.dart';

typedef EventCallback<Data> = Future<dynamic> Function(Data data);

abstract class BaseEvent<EventType, Data> {
  EventType type;
  Data data;

  /// Constructor.
  BaseEvent(this.type, this.data);

  /// Consume this event.
  @visibleForTesting
  Future<dynamic> consume() async {
    final cb = findCallback(type);
    if (cb == null) {
      return null;
    } else {
      return cb(data);
    }
  }

  EventCallback<Data>? findCallback(EventType type);
}

abstract class BaseEventLoop<EventType, Data> {
  final List<BaseEvent<EventType, Data>> _evts = [];
  Timer? _timer;

  List<BaseEvent<EventType, Data>> get evts => _evts;

  Future<void> onReady() async {}

  /// An Event is about to be consumed.
  Future<void> onPreConsume(BaseEvent<EventType, Data> evt) async {}
  /// An Event was consumed.
  Future<void> onPostConsume(BaseEvent<EventType, Data> evt) async {}
  /// Events are all handled and cleared.
  Future<void> onEventsClear() async {}
  /// Events start to consume.
  Future<void> onEventsStartConsuming() async {}

  /// Process pending events on a short delay, then auto-stop when the
  /// queue drains — no permanent periodic timer.
  void _scheduleConsume() {
    if (_timer != null) return;
    _timer = Timer(Duration(milliseconds: 100), _handleTimer);
  }

  void _handleTimer() {
    _timer = null;
    _consumeEvents();
  }

  Future<void> _consumeEvents() async {
    if (_evts.isEmpty) return;
    await onEventsStartConsuming();
    while (_evts.isNotEmpty) {
      final evt = _evts.first;
      _evts.remove(evt);
      await onPreConsume(evt);
      await evt.consume();
      await onPostConsume(evt);
    }
    await onEventsClear();
  }

  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
  }

  void pushEvent(BaseEvent<EventType, Data> evt) {
    _evts.add(evt);
    _scheduleConsume();
  }

  void clear() {
    _evts.clear();
  }
}
