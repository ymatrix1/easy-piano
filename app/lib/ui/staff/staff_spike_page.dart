import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'staff_note.dart';
import 'staff_painter.dart';

/// Phase 0 spike: Bravura grand staff scrolling at the tempo, with frame stats.
class StaffSpikePage extends StatefulWidget {
  const StaffSpikePage({super.key});

  @override
  State<StaffSpikePage> createState() => _StaffSpikePageState();
}

class _StaffSpikePageState extends State<StaffSpikePage>
    with SingleTickerProviderStateMixin {
  static const _bpm = 100.0;

  final _notes = odeToJoyDemo();
  final _beat = ValueNotifier<double>(0);
  final _frameMs = <double>[]; // vsync-to-vsync intervals
  final _rasterMs = <double>[];
  late final Ticker _ticker;
  Duration? _last;
  String _stats = 'measuring…';

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      // Spike only: real play-along takes time from the audio clock (rule 7).
      final total = _notes.last.beat + 4;
      _beat.value = (elapsed.inMicroseconds / 6e7 * _bpm) % total;
      if (_last != null) {
        _push(_frameMs, (elapsed - _last!).inMicroseconds / 1000);
      }
      _last = elapsed;
    })..start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _push(List<double> list, double v) {
    list.add(v);
    if (list.length > 600) list.removeAt(0);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _push(_rasterMs, t.rasterDuration.inMicroseconds / 1000);
    }
    if (!mounted || _frameMs.length < 30) return;
    setState(() => _stats = _summary());
  }

  static double _pct(List<double> v, double q) {
    final s = [...v]..sort();
    return s[math.min(s.length - 1, (q * s.length).floor())];
  }

  String _summary() {
    final avg = _frameMs.reduce((a, b) => a + b) / _frameMs.length;
    final dropped = _frameMs.where((f) => f > 1000 / 60 * 1.5).length;
    final raster = _rasterMs.isEmpty
        ? 'n/a'
        : '${_pct(_rasterMs, .95).toStringAsFixed(2)} ms';
    return 'fps≈${(1000 / avg).toStringAsFixed(1)}  frame p95=${_pct(_frameMs, .95).toStringAsFixed(1)} ms  '
        'janky=${(100 * dropped / _frameMs.length).toStringAsFixed(1)}%  raster p95=$raster  '
        'notes=${_notes.length}';
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _ticker.dispose();
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Staff spike · Bravura')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _stats,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: StaffPainter(
                  notes: _notes,
                  playheadBeat: _beat,
                  inkColor: scheme.onSurface,
                  playheadColor: scheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
