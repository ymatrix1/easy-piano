import 'package:flutter/services.dart';

/// Channels to the platform side (Android: `MidiBridge.kt`, `MicBridge.kt`).
/// Platforms without it (iOS, desktop, tests) answer with
/// [MissingPluginException], which callers treat as "unsupported".
const nativeInput = MethodChannel('dev.easypiano/input');
const nativeMidiEvents = EventChannel('dev.easypiano/midi/events');
const nativeMicEvents = EventChannel('dev.easypiano/mic/events');

/// The platform's monotonic clock (System.nanoTime on Android) in ms. MIDI
/// and mic events are stamped on it, so [now] must read the same clock
/// synchronously: one call to the platform fixes the offset, a [Stopwatch]
/// carries it from there.
class NativeClock {
  final _watch = Stopwatch()..start();
  double _base = 0;
  bool _synced = false;

  /// Reads the platform clock; false when there is no platform side.
  Future<bool> sync() async {
    if (_synced) return true;
    try {
      final before = _watch.elapsedMicroseconds / 1000.0;
      final native = await nativeInput.invokeMethod<double>('clockMs');
      final after = _watch.elapsedMicroseconds / 1000.0;
      if (native == null) return false;
      // The platform read happened about halfway through the round trip.
      _base = native - (before + after) / 2;
      _synced = true;
      return true;
    } on MissingPluginException {
      return false;
    }
  }

  double now() => _base + _watch.elapsedMicroseconds / 1000.0;
}

/// Shared by MIDI and mic so both stamp events on one clock.
final nativeClock = NativeClock();
