import 'midi_input_stub.dart' if (dart.library.js_interop) 'midi_input_web.dart'
    as impl;
import 'note_event.dart';

export 'note_event.dart';

/// Platform MIDI input. Web uses Web MIDI; native platforms come in Phase 2.
MidiInput createMidiInput() => impl.createMidiInput();
