import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/utils/event_loop.dart';

void main() {
  test('event loop processes queued events in order', () async {
    final processed = <String>[];
    final loop = _TestEventLoop();

    loop.postConsumeCallback = (data) => processed.add(data);

    loop.pushEvent(_TestEvent('a'));
    loop.pushEvent(_TestEvent('b'));
    loop.pushEvent(_TestEvent('c'));

    // Events are auto-scheduled on push; wait for the 100ms timer to fire.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(processed, ['a', 'b', 'c']);
    await loop.close();
  });

  test('event loop handles empty queue without consuming', () async {
    final loop = _TestEventLoop();
    var consumed = false;
    loop.startConsumingCallback = () => consumed = true;

    // No events pushed — no timer should be scheduled.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(consumed, isFalse);
    await loop.close();
  });
}

enum _TestEventType { foo }

class _TestEvent extends BaseEvent<_TestEventType, String> {
  _TestEvent(String data) : super(_TestEventType.foo, data);

  @override
  EventCallback<String>? findCallback(_TestEventType type) {
    return (data) async => null;
  }
}

class _TestEventLoop extends BaseEventLoop<_TestEventType, String> {
  void Function()? startConsumingCallback;
  void Function(String)? postConsumeCallback;

  @override
  Future<void> onEventsStartConsuming() async {
    startConsumingCallback?.call();
  }

  @override
  Future<void> onPostConsume(BaseEvent<_TestEventType, String> evt) async {
    postConsumeCallback?.call(evt.data);
  }
}
