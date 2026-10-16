import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'content/content_repo.dart';
import 'home/home_page.dart';
import 'input/midi_input.dart';
import 'src/rust/api/notation.dart' as core;
import 'src/rust/frb_generated.dart';
import 'ui/key_geometry.dart';
import 'ui/keyboard_painter.dart';
import 'ui/staff/staff_spike_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final locale =
      WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'pt'
      ? 'pt-BR'
      : 'en';
  final repo = await ContentRepo.load(locale: locale);
  runApp(EasyPianoApp(repo: repo));
}

class EasyPianoApp extends StatelessWidget {
  EasyPianoApp({super.key, required this.repo});

  final ContentRepo repo;

  /// One MIDI connection shared by every screen.
  final MidiInput midi = createMidiInput();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Easy Piano',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C4CF1),
        useMaterial3: true,
      ),
      home: HomePage(
        repo: repo,
        midi: midi,
        spikes: (_) => const MidiSpikePage(),
      ),
    );
  }
}

/// Phase 0 spike: MIDI or touch → colored key, with input-to-frame latency stats.
class MidiSpikePage extends StatefulWidget {
  const MidiSpikePage({super.key});

  @override
  State<MidiSpikePage> createState() => _MidiSpikePageState();
}

class _MidiSpikePageState extends State<MidiSpikePage> {
  static const _low = 48; // C3
  static const _high = 84; // C6

  final _input = createMidiInput();
  final _pressed = ValueNotifier<Set<int>>({});
  final _latencies = <double>[];
  StreamSubscription<NoteEvent>? _sub;
  String _status = 'Press "Connect MIDI" or tap the keys.';

  Future<void> _connect() async {
    final ok = await _input.start();
    setState(() {
      _status = ok
          ? 'MIDI devices: ${_input.deviceNames.isEmpty ? "none yet (plug one in)" : _input.deviceNames.join(", ")}'
          : 'Web MIDI unavailable or denied (Safari has none). Use touch.';
    });
    _sub ??= _input.events.listen(_onNote);
  }

  void _onNote(NoteEvent e) {
    final next = {..._pressed.value};
    e.on ? next.add(e.pitch) : next.remove(e.pitch);
    _pressed.value = next;
    if (!e.on) return;
    // Time from the device event to the start of the frame that paints it.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final ms = _input.now() - e.timestampMs;
      setState(() {
        _latencies.add(ms);
        if (_latencies.length > 200) _latencies.removeAt(0);
      });
    });
  }

  // Pitch held by each pointer, so release frees the key that was pressed
  // even if the finger slid elsewhere.
  final _pointerPitch = <int, int>{};

  void _touchDown(int pointer, Offset p, Size size) {
    final g = KeyGeometry(lowPitch: _low, highPitch: _high, size: size);
    final pitch = g.pitchAt(p);
    if (pitch == null) return;
    _pointerPitch[pointer] = pitch;
    _onNote(
      NoteEvent(
        pitch: pitch,
        velocity: 90,
        on: true,
        timestampMs: _input.now(),
      ),
    );
  }

  void _touchUp(int pointer) {
    final pitch = _pointerPitch.remove(pointer);
    if (pitch == null) return;
    _onNote(
      NoteEvent(
        pitch: pitch,
        velocity: 0,
        on: false,
        timestampMs: _input.now(),
      ),
    );
  }

  String _stats() {
    if (_latencies.isEmpty) return 'No samples yet';
    final s = [..._latencies]..sort();
    double pct(double q) => s[math.min(s.length - 1, (q * s.length).floor())];
    return 'n=${s.length}  p50=${pct(.5).toStringAsFixed(1)} ms  '
        'p95=${pct(.95).toStringAsFixed(1)} ms  max=${s.last.toStringAsFixed(1)} ms';
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Easy Piano · MIDI spike'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const StaffSpikePage())),
            icon: const Icon(Icons.music_note),
            label: const Text('Staff spike'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _connect,
                  icon: const Icon(Icons.piano),
                  label: const Text('Connect MIDI'),
                ),
                Text(_status),
              ],
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: _pressed,
              builder: (context, keys, _) => Text(
                'Rust core: C4 = ${core.parsePitch(token: "C4")} · '
                'pressed: ${(keys.toList()..sort()).map((k) => core.pitchName(midi: k)).join(" ")}',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Input → frame latency: ${_stats()}',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 180,
              child: LayoutBuilder(
                builder: (context, c) {
                  final size = Size(c.maxWidth, c.maxHeight);
                  return Listener(
                    onPointerDown: (e) =>
                        _touchDown(e.pointer, e.localPosition, size),
                    onPointerUp: (e) => _touchUp(e.pointer),
                    onPointerCancel: (e) => _touchUp(e.pointer),
                    child: CustomPaint(
                      size: size,
                      painter: KeyboardPainter(
                        lowPitch: _low,
                        highPitch: _high,
                        pressed: _pressed,
                        pressedColor: scheme.primary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
