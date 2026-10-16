import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'note_event.dart';

MidiInput createMidiInput() => _WebMidiInput();

class _WebMidiInput implements MidiInput {
  final _controller = StreamController<NoteEvent>.broadcast();
  final _names = <String>[];
  web.MIDIAccess? _access;

  @override
  Stream<NoteEvent> get events => _controller.stream;

  @override
  List<String> get deviceNames => List.unmodifiable(_names);

  @override
  double now() => web.window.performance.now();

  @override
  Future<bool> start() async {
    final nav = web.window.navigator;
    if (!nav.has('requestMIDIAccess')) return false;
    try {
      _access = await nav.requestMIDIAccess().toDart;
    } catch (_) {
      return false;
    }
    _bindInputs();
    _access!.onstatechange = ((web.Event _) => _bindInputs()).toJS;
    return true;
  }

  void _bindInputs() {
    _names.clear();
    final inputs = _access!.inputs;
    // MIDIInputMap is a JS maplike; iterate with its forEach(value, key).
    (inputs as JSObject).callMethod(
      'forEach'.toJS,
      // JS calls forEach callbacks with (value, key, map); declare all three
      // or the dart2js wrapper rejects the call and no handler is attached.
      ((web.MIDIInput input, JSAny? key, JSAny? map) {
        _names.add(input.name ?? 'MIDI input');
        input.onmidimessage = _onMessage.toJS;
      }).toJS,
    );
  }

  void _onMessage(web.MIDIMessageEvent e) {
    final data = e.data?.toDart;
    if (data == null || data.length < 3) return;
    final status = data[0] & 0xF0;
    final pitch = data[1];
    final velocity = data[2];
    if (status != 0x90 && status != 0x80) return;
    _controller.add(
      NoteEvent(
        pitch: pitch,
        velocity: velocity,
        on: status == 0x90 && velocity > 0,
        timestampMs: e.timeStamp,
      ),
    );
  }
}

extension on web.Navigator {
  bool has(String name) => (this as JSObject).has(name);
}
