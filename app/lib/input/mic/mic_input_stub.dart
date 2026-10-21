import 'dart:async';

import '../note_event.dart';
import 'mic_input.dart';

MicInput createMicInput() => _UnsupportedMicInput();

/// Native platforms get mic capture with the native audio engine (Phase 3).
class _UnsupportedMicInput implements MicInput {
  final _watch = Stopwatch()..start();

  @override
  MicError? get error => MicError.unsupported;

  @override
  Stream<NoteEvent> get events => const Stream.empty();

  @override
  Stream<NoteEvent> get rawEvents => const Stream.empty();

  @override
  List<String> get deviceNames => const [];

  @override
  Future<bool> start() async => false;

  @override
  void stop() {}

  @override
  bool get running => false;

  @override
  double? offsetMs;

  @override
  bool preferred = false;

  @override
  Future<List<MicDevice>> devices() async => const [];

  @override
  String? get deviceId => null;

  @override
  Future<void> selectDevice(String? id) async {}

  @override
  double get level => 0;

  @override
  Set<int> expected = const {};

  @override
  double now() => _watch.elapsedMicroseconds / 1000.0;
}
