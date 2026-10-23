import 'dart:async';

import 'package:flutter/services.dart';

import 'native_bridge.dart';
import 'note_event.dart';

MidiInput createMidiInput() => _NativeMidiInput();

/// android.media.midi (USB and BLE) through [nativeMidiEvents]. Where the
/// platform side is missing (iOS, desktop) [start] returns false.
class _NativeMidiInput implements MidiInput {
  final _controller = StreamController<NoteEvent>.broadcast();
  List<String> _names = const [];
  StreamSubscription<dynamic>? _sub;

  @override
  Stream<NoteEvent> get events => _controller.stream;

  @override
  List<String> get deviceNames => _names;

  @override
  double now() => nativeClock.now();

  @override
  Future<bool> start() async {
    if (_sub != null) return true;
    try {
      if (await nativeInput.invokeMethod<bool>('midiAvailable') != true) {
        return false;
      }
    } on MissingPluginException {
      return false;
    }
    if (!await nativeClock.sync()) return false;
    _sub = nativeMidiEvents.receiveBroadcastStream().listen(
      _onEvent,
      onError: (_) {},
    );
    // The platform lists attached devices right after the listen; give it a
    // moment so the caller sees their names.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return true;
  }

  void _onEvent(dynamic e) {
    final msg = e as List<dynamic>;
    if (msg.first == 'd') {
      _names = [for (final n in msg.skip(1)) n as String];
    } else {
      _controller.add(
        NoteEvent(
          pitch: msg[1] as int,
          velocity: msg[2] as int,
          on: msg[3] == 1,
          timestampMs: (msg[4] as num).toDouble(),
        ),
      );
    }
  }
}
