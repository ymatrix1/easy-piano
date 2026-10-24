import 'midi_input_native.dart'
    if (dart.library.js_interop) 'midi_input_web.dart'
    as impl;
import 'note_event.dart';

export 'note_event.dart';

/// Platform MIDI input. Web uses Web MIDI, Android android.media.midi.
MidiInput createMidiInput() => impl.createMidiInput();
