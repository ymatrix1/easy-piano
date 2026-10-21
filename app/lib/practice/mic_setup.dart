import 'dart:async';

import 'package:flutter/material.dart';

import '../input/mic/mic_input.dart';
import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';

/// Latency from visual cues to played onsets, in ms. Each cue takes the
/// first onset in [cue − 200, cue + period − 200), so latency up to
/// period − 200 ms (Bluetooth, slow reactions) still counts. Returns the
/// median when at least [minHits] cues were answered and agree within
/// ±[spread] ms of it; null otherwise. Pure for testing.
double? calibrationOffset(
  List<double> cues,
  List<double> onsets, {
  double period = 800,
  int minHits = 4,
  double spread = 150,
}) {
  final diffs = <double>[];
  for (final c in cues) {
    for (final o in onsets) {
      final d = o - c;
      if (d >= -200 && d < period - 200) {
        diffs.add(d);
        break;
      }
    }
  }
  if (diffs.length < minHits) return null;
  diffs.sort();
  final median = diffs[diffs.length ~/ 2];
  final agree = diffs.where((d) => (d - median).abs() <= spread).length;
  return agree >= minHits ? median : null;
}

/// Localized note name with octave, e.g. "C4" or "Dó4".
String micNoteName(AppLocalizations l, int pitch) {
  final names = l.micNoteNames.split(',');
  return '${names[pitch % 12]}${pitch ~/ 12 - 1}';
}

Future<T?> _showPanel<T>(BuildContext context, WidgetBuilder builder) =>
    showDialog<T>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (c) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Material(
            type: MaterialType.transparency,
            child: PopIn(from: 0.7, child: builder(c)),
          ),
        ),
      ),
    );

const _body = TextStyle(
  color: GameColors.text,
  fontSize: 16,
  fontWeight: FontWeight.w600,
  height: 1.35,
);

/// Explains what listening means before the browser's permission prompt.
Future<bool> showMicExplain(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final ok = await _showPanel<bool>(
    context,
    (c) => GamePanel(
      title: l.micExplainTitle,
      maxWidth: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic_rounded, color: GameColors.cyan, size: 48),
          const SizedBox(height: 12),
          Text(l.micExplainBody, textAlign: TextAlign.center, style: _body),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              GameButton(
                label: l.cancel.toUpperCase(),
                onTap: () => Navigator.of(c).pop(false),
                tone: GameTone.wood,
                minWidth: 120,
              ),
              GameButton(
                label: l.micAllow.toUpperCase(),
                icon: Icons.mic_rounded,
                onTap: () => Navigator.of(c).pop(true),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// Outcome of the setup panel.
enum MicSetupResult { listen, off }

/// Microphone setup: pick the input, see the level and the note heard, and
/// calibrate latency. A circle lights up on a steady beat and the student
/// plays any key with it; the cue is visual so the speakers can't trigger
/// the mic. Returns null when cancelled.
Future<MicSetupResult?> showMicSetup(
  BuildContext context,
  MicInput mic, {
  required bool active,
}) => _showPanel<MicSetupResult>(
  context,
  (_) => _MicSetupPanel(mic: mic, active: active),
);

class _MicSetupPanel extends StatefulWidget {
  const _MicSetupPanel({required this.mic, required this.active});
  final MicInput mic;
  final bool active;

  @override
  State<_MicSetupPanel> createState() => _MicSetupPanelState();
}

enum _Cal { idle, running, failed, done }

class _MicSetupPanelState extends State<_MicSetupPanel> {
  static const _beats = 8;
  static const _skip = 2; // first beats let the student find the pulse
  static const _periodMs = 800;

  final _cues = <double>[];
  final _onsets = <double>[];
  StreamSubscription<dynamic>? _sub;
  Timer? _beatTimer;
  Timer? _meterTimer;
  List<MicDevice> _devices = const [];
  int _beat = -1;
  bool _lit = false;
  int? _heard;
  DateTime? _lastHit;
  _Cal _cal = _Cal.idle;

  MicInput get _mic => widget.mic;

  @override
  void initState() {
    super.initState();
    if (_mic.offsetMs != null) _cal = _Cal.done;
    _listen();
    _loadDevices();
    _meterTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  void _listen() {
    _sub?.cancel();
    _sub = _mic.rawEvents.listen((e) {
      if (!e.on) return;
      _onsets.add(e.timestampMs);
      _heard = e.pitch;
      _lastHit = DateTime.now();
    });
  }

  Future<void> _loadDevices() async {
    final d = await _mic.devices();
    if (mounted) setState(() => _devices = d);
  }

  Future<void> _pickDevice(String? id) async {
    await _mic.selectDevice(id);
    _listen();
    // Latency is stored per device: a new input needs its own calibration.
    if (mounted) {
      setState(() {
        _heard = null;
        _cal = _mic.offsetMs != null ? _Cal.done : _Cal.idle;
      });
    }
  }

  void _calibrate() {
    _cues.clear();
    _onsets.clear();
    _beat = -1;
    _cal = _Cal.running;
    _beatTimer?.cancel();
    _beatTimer = Timer.periodic(const Duration(milliseconds: _periodMs), (_) {
      if (!mounted) return;
      _beat++;
      if (_beat >= _beats) {
        _beatTimer?.cancel();
        // Let the last onsets arrive (the detector reports ~0.1 s late).
        Future.delayed(const Duration(milliseconds: 400), _finish);
        setState(() => _lit = false);
        return;
      }
      setState(() => _lit = true);
      // The cue shows on the next frame (~1 frame after the timer).
      if (_beat >= _skip) _cues.add(_mic.now() + 16);
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _lit = false);
      });
    });
    setState(() {});
  }

  void _finish() {
    if (!mounted) return;
    final off = calibrationOffset(_cues, [..._onsets]..sort());
    if (off != null) _mic.offsetMs = off;
    setState(() => _cal = off == null ? _Cal.failed : _Cal.done);
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    _meterTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Widget _deviceRow(AppLocalizations l) {
    final ids = {for (final d in _devices) d.id};
    final current = ids.contains(_mic.deviceId) ? _mic.deviceId : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: ShapeDecoration(
        shape: chamfer(
          10,
          side: const BorderSide(color: GameColors.panelEdge, width: 1.5),
        ),
        color: GameColors.bgDeep.withValues(alpha: 0.6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: current,
          isExpanded: true,
          dropdownColor: GameColors.panelHi,
          iconEnabledColor: GameColors.cyan,
          style: _body,
          // Explicit text so the closed/disabled field (during calibration)
          // stays light instead of Material's dark disabled colour.
          selectedItemBuilder: (_) => [
            for (final label in [
              l.micDefaultDevice,
              for (final d in _devices) d.label,
            ])
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: _body.copyWith(
                    color: _cal == _Cal.running
                        ? GameColors.textDim
                        : GameColors.text,
                  ),
                ),
              ),
          ],
          disabledHint: Text(
            _devices
                    .where((d) => d.id == current)
                    .map((d) => d.label)
                    .firstOrNull ??
                l.micDefaultDevice,
            overflow: TextOverflow.ellipsis,
            style: _body.copyWith(color: GameColors.textDim),
          ),
          iconDisabledColor: GameColors.textDim,
          items: [
            DropdownMenuItem(value: null, child: Text(l.micDefaultDevice)),
            for (final d in _devices)
              DropdownMenuItem(
                value: d.id,
                child: Text(d.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _cal == _Cal.running ? null : _pickDevice,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final running = _cal == _Cal.running;
    final status = switch (_cal) {
      _Cal.idle => l.micCalibrateBody,
      _Cal.running => l.micCalibrateBody,
      _Cal.failed => l.micCalibrateRetry,
      _Cal.done => l.micCalibrateDone((_mic.offsetMs ?? 0).round()),
    };
    return GamePanel(
      title: l.micInput,
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _deviceRow(l),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.graphic_eq_rounded, color: GameColors.cyan),
              const SizedBox(width: 10),
              Expanded(
                child: GameProgressBar(
                  value: _mic.level,
                  height: 10,
                  color: GameColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _heard == null
                ? l.micTestHint
                : l.micHeard(micNoteName(l, _heard!)),
            textAlign: TextAlign.center,
            style: _body.copyWith(
              color: _heard == null ? GameColors.textDim : GameColors.cyan,
            ),
          ),
          const SizedBox(height: 18),
          GameText(l.micCalibrateTitle, size: 16, upper: true),
          const SizedBox(height: 8),
          Text(
            status,
            textAlign: TextAlign.center,
            style: _body.copyWith(
              color: _cal == _Cal.failed
                  ? GameColors.danger
                  : _cal == _Cal.done
                  ? GameColors.success
                  : GameColors.textDim,
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 60),
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _lit ? GameColors.yellow : GameColors.panelHi,
                // Green ring for a moment after each note heard, so the
                // student sees the mic is getting their taps.
                border: Border.all(
                  color:
                      _lastHit != null &&
                          DateTime.now().difference(_lastHit!).inMilliseconds <
                              250
                      ? GameColors.success
                      : GameColors.panelEdge,
                  width: 4,
                ),
                boxShadow: _lit
                    ? [
                        BoxShadow(
                          color: GameColors.yellow.withValues(alpha: 0.6),
                          blurRadius: 24,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: running && _beat >= 0
                  ? GameText(
                      '${(_beat + 1).clamp(1, _beats)}',
                      size: 22,
                      color: _lit ? GameColors.ink : GameColors.text,
                      shadow: false,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          GameButton(
            label: l.micCalibrate.toUpperCase(),
            icon: Icons.tune_rounded,
            onTap: running ? null : _calibrate,
            tone: GameTone.purple,
            fontSize: 15,
            minWidth: 0,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: widget.active
                    ? GameButton(
                        label: l.micTurnOff.toUpperCase(),
                        icon: Icons.mic_off_rounded,
                        onTap: running
                            ? null
                            : () =>
                                  Navigator.of(context).pop(MicSetupResult.off),
                        tone: GameTone.red,
                        fontSize: 15,
                        minWidth: 0,
                      )
                    : GameButton(
                        label: l.cancel.toUpperCase(),
                        onTap: running
                            ? null
                            : () => Navigator.of(context).pop(),
                        tone: GameTone.wood,
                        fontSize: 15,
                        minWidth: 0,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GameButton(
                  label: l.continueButton.toUpperCase(),
                  // Calibration is optional: onsets are timed to the sample,
                  // so the default offset (0) is close enough to start.
                  onTap: running
                      ? null
                      : () => Navigator.of(context).pop(MicSetupResult.listen),
                  tone: GameTone.green,
                  fontSize: 15,
                  minWidth: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
