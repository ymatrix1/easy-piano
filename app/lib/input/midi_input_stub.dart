import 'dart:async';

import 'note_event.dart';

MidiInput createMidiInput() => _UnsupportedMidiInput();

class _UnsupportedMidiInput implements MidiInput {
  final _watch = Stopwatch()..start();

  @override
  Stream<NoteEvent> get events => const Stream.empty();

  @override
  List<String> get deviceNames => const [];

  @override
  Future<bool> start() async => false;

  @override
  double now() => _watch.elapsedMicroseconds / 1000.0;
}
