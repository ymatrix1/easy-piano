import 'dart:async';

import 'package:flutter/material.dart';

import '../input/mic/mic_input.dart';
import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';

/// Median of (onset − cue) over cues that got an onset within ±[window] ms;
/// null when fewer than [minHits] cues were answered. Pure for testing.
double? calibrationOffset(
  List<double> cues,
  List<double> onsets, {
  double window = 350,
  int minHits = 4,
}) {
  final diffs = <double>[];
  for (final c in cues) {
    double? best;
    for (final o in onsets) {
      final d = o - c;
      if (d.abs() <= window && (best == null || d.abs() < best.abs())) best = d;
    }
    if (best != null) diffs.add(best);
  }
  if (diffs.length < minHits) return null;
  diffs.sort();
  return diffs[diffs.length ~/ 2];
}

/// Latency calibration: a circle lights up on a steady beat and the student
/// plays any key with it. The cue is visual, not a click, so the speakers
/// can't trigger the mic. Stores and returns the offset in ms, or null when
/// cancelled.
Future<double?> showMicCalibration(BuildContext context, MicInput mic) =>
    showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CalibrationDialog(mic: mic),
    );

class _CalibrationDialog extends StatefulWidget {
  const _CalibrationDialog({required this.mic});
  final MicInput mic;

  @override
  State<_CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<_CalibrationDialog> {
  static const _beats = 8;
  static const _skip = 2; // first beats let the student find the pulse
  static const _periodMs = 800;

  final _cues = <double>[];
  final _onsets = <double>[];
  StreamSubscription<dynamic>? _sub;
  Timer? _timer;
  int _beat = -1;
  bool _lit = false;
  bool _failed = false;
  double? _result;

  @override
  void initState() {
    super.initState();
    _sub = widget.mic.rawEvents.listen((e) {
      if (e.on) _onsets.add(e.timestampMs);
    });
    _run();
  }

  void _run() {
    _cues.clear();
    _onsets.clear();
    _beat = -1;
    _failed = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: _periodMs), (_) {
      if (!mounted) return;
      _beat++;
      if (_beat >= _beats) {
        _timer?.cancel();
        // Let the last onsets arrive (the detector reports ~0.1 s late).
        Future.delayed(const Duration(milliseconds: 400), _finish);
        setState(() => _lit = false);
        return;
      }
      setState(() => _lit = true);
      // The cue shows on the next frame (~1 frame after the timer).
      if (_beat >= _skip) _cues.add(widget.mic.now() + 16);
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _lit = false);
      });
    });
  }

  void _finish() {
    if (!mounted) return;
    final off = calibrationOffset(_cues, _onsets);
    setState(() {
      _failed = off == null;
      _result = off;
    });
    if (off != null) widget.mic.offsetMs = off;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final done = _result != null;
    return AlertDialog(
      backgroundColor: GameColors.panel,
      title: Text(
        l.micCalibrateTitle,
        style: const TextStyle(color: GameColors.text),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            done
                ? l.micCalibrateDone(_result!.round())
                : _failed
                ? l.micCalibrateRetry
                : l.micCalibrateBody,
            style: const TextStyle(color: GameColors.textDim),
          ),
          const SizedBox(height: 24),
          AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _lit ? GameColors.yellow : GameColors.panelHi,
              border: Border.all(color: GameColors.panelEdge, width: 3),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _beat < 0 || done
                ? ''
                : '${(_beat + 1).clamp(1, _beats)} / $_beats',
            style: const TextStyle(color: GameColors.textDim),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_result),
          child: Text(done ? l.continueButton : l.cancel),
        ),
        if (_failed)
          TextButton(
            onPressed: () => setState(_run),
            child: Text(l.micCalibrate),
          ),
      ],
    );
  }
}
