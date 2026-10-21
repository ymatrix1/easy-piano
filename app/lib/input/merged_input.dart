import 'dart:async';

import 'midi_input.dart';

/// MIDI and microphone at once: a student may have a MIDI keyboard plugged
/// in while the mic listens. Both streams pass through; a mic note-on is
/// dropped when MIDI sent the same pitch within [echoMs] (a digital piano
/// heard by the mic as well as over MIDI), so one key never counts twice.
class MergedInput implements MidiInput {
  MergedInput(this.midi, this.mic, {this.echoMs = 350});

  final MidiInput midi;
  final MidiInput mic;
  final double echoMs;

  final _lastMidiOn = <int, double>{};
  final _micOn = <int>{};

  @override
  late final Stream<NoteEvent> events = _merge();

  Stream<NoteEvent> _merge() {
    final out = StreamController<NoteEvent>.broadcast();
    StreamSubscription<NoteEvent>? a;
    StreamSubscription<NoteEvent>? b;
    out.onListen = () {
      a = midi.events.listen((e) {
        if (e.on) _lastMidiOn[e.pitch] = e.timestampMs;
        out.add(e);
      });
      b = mic.events.listen((e) {
        if (e.on) {
          final last = _lastMidiOn[e.pitch];
          if (last != null && (e.timestampMs - last).abs() < echoMs) return;
          _micOn.add(e.pitch);
        } else if (!_micOn.remove(e.pitch)) {
          return; // its note-on was a dropped echo
        }
        out.add(e);
      });
    };
    out.onCancel = () {
      a?.cancel();
      b?.cancel();
    };
    return out.stream;
  }

  @override
  List<String> get deviceNames => midi.deviceNames;

  @override
  Future<bool> start() => midi.start();

  /// Both sources use the `performance.now()` clock on web.
  @override
  double now() => midi.now();
}
