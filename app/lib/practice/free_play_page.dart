import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/piano_synth.dart';
import '../input/midi_input.dart';
import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import '../ui/key_geometry.dart';
import '../ui/keyboard_painter.dart';

/// Free play: no goals, just a keyboard. MIDI or touch (with glissando) plays
/// the piano voice, shows the note names being held and lets the player move
/// the visible range by octaves. See docs/specs/visual-style.md (Practice tab).
class FreePlayPage extends StatefulWidget {
  const FreePlayPage({super.key, required this.midi});

  final MidiInput midi;

  @override
  State<FreePlayPage> createState() => _FreePlayPageState();
}

class _FreePlayPageState extends State<FreePlayPage> {
  static const _lowest = 24; // C1
  static const _highest = 108; // C8

  final _pressed = ValueNotifier<Set<int>>({});
  // Pitch held by each pointer, so a slide moves the note and release frees it.
  final _pointerPitch = <int, int>{};
  StreamSubscription<NoteEvent>? _sub;
  int _low = 48; // C3
  String? _midiLabel;

  @override
  void initState() {
    super.initState();
    pianoSynth.load();
    _sub = widget.midi.events.listen((e) => _note(e.pitch, e.on));
    _connectMidi(quiet: true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    pianoSynth.stopAll();
    _pressed.dispose();
    super.dispose();
  }

  /// Keys on screen, C to C: two octaves on phones, up to four on desktop.
  int _span(double width) => width >= 900 ? 48 : (width >= 480 ? 36 : 24);

  Future<void> _connectMidi({bool quiet = false}) async {
    final ok = await widget.midi.start();
    if (!mounted) return;
    final names = widget.midi.deviceNames;
    setState(
      () => _midiLabel = ok && names.isNotEmpty ? names.join(', ') : null,
    );
    if (!quiet && _midiLabel == null) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? l.midiNotFound : l.midiUnavailable)),
      );
    }
  }

  void _note(int pitch, bool on) {
    on ? pianoSynth.noteOn(pitch) : pianoSynth.noteOff(pitch);
    final next = {..._pressed.value};
    on ? next.add(pitch) : next.remove(pitch);
    _pressed.value = next;
  }

  void _touchDown(int pointer, Offset p, KeyGeometry g) {
    final pitch = g.pitchAt(p);
    if (pitch == null) return;
    _pointerPitch[pointer] = pitch;
    _note(pitch, true);
  }

  void _touchMove(int pointer, Offset p, KeyGeometry g) {
    final held = _pointerPitch[pointer];
    if (held == null) return;
    final pitch = g.pitchAt(p);
    if (pitch == null || pitch == held) return;
    _note(held, false);
    _pointerPitch[pointer] = pitch;
    _note(pitch, true);
  }

  void _touchUp(int pointer) {
    final pitch = _pointerPitch.remove(pointer);
    if (pitch != null) _note(pitch, false);
  }

  void _shift(int octaves, int span) {
    // Release anything held so no note is left hanging on a key that moves.
    for (final p in {..._pressed.value}) {
      _note(p, false);
    }
    _pointerPitch.clear();
    setState(
      () => _low = (_low + 12 * octaves).clamp(_lowest, _highest - span),
    );
  }

  String _name(AppLocalizations l, int pitch) {
    final names = l.noteNames.split(',');
    return '${names[pitch % 12]}${pitch ~/ 12 - 1}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: GameColors.bgDeep,
      body: MenuBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final span = _span(c.maxWidth);
              final low = _low.clamp(_lowest, _highest - span);
              final high = low + span;
              final keyH = (c.maxHeight * 0.34).clamp(150.0, 280.0);
              return Column(
                children: [
                  _header(l, span),
                  Expanded(child: Center(child: _readout(l))),
                  _octaveBar(l, low, span),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                    child: SizedBox(
                      height: keyH,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LayoutBuilder(
                          builder: (context, k) {
                            final size = Size(k.maxWidth, k.maxHeight);
                            final g = KeyGeometry(
                              lowPitch: low,
                              highPitch: high,
                              size: size,
                            );
                            return Listener(
                              onPointerDown: (e) =>
                                  _touchDown(e.pointer, e.localPosition, g),
                              onPointerMove: (e) =>
                                  _touchMove(e.pointer, e.localPosition, g),
                              onPointerUp: (e) => _touchUp(e.pointer),
                              onPointerCancel: (e) => _touchUp(e.pointer),
                              child: CustomPaint(
                                size: size,
                                painter: KeyboardPainter(
                                  lowPitch: low,
                                  highPitch: high,
                                  pressed: _pressed,
                                  pressedColor: GameColors.cyan,
                                  labelMiddleC: true,
                                  middleCLabel: l.middleCLabel,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l, int span) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          GameRoundButton(
            icon: Icons.close_rounded,
            onTap: () => Navigator.of(context).pop(),
            tone: GameTone.red,
            size: 48,
            tooltip: l.exit,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GameText(l.freePlay, size: 24, align: TextAlign.left),
          ),
          _MidiChip(label: _midiLabel, onTap: _connectMidi),
          const SizedBox(width: 10),
          GameRoundButton(
            icon: pianoSynth.enabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            onTap: () =>
                setState(() => pianoSynth.enabled = !pianoSynth.enabled),
            tone: pianoSynth.enabled ? GameTone.blue : GameTone.grey,
            size: 48,
            tooltip: pianoSynth.enabled ? l.mutePianoSound : l.playPianoSound,
          ),
        ],
      ),
    );
  }

  /// Big names of the held keys, or a hint until the first key.
  Widget _readout(AppLocalizations l) {
    return ValueListenableBuilder<Set<int>>(
      valueListenable: _pressed,
      builder: (context, keys, _) {
        final sorted = keys.toList()..sort();
        final text = sorted.isEmpty
            ? null
            : sorted.map((p) => _name(l, p)).join('  ');
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            child: text == null
                ? Text(
                    l.freePlayHint,
                    key: const ValueKey('hint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: GameColors.textDim,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : FittedBox(
                    key: ValueKey(text),
                    fit: BoxFit.scaleDown,
                    child: GameText(
                      text,
                      upper: false,
                      size: sorted.length > 1 ? 44 : 72,
                      color: GameColors.cyan,
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _octaveBar(AppLocalizations l, int low, int span) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GameRoundButton(
          icon: Icons.chevron_left_rounded,
          onTap: low > _lowest ? () => _shift(-1, span) : null,
          size: 44,
          tooltip: l.octaveDown,
        ),
        const SizedBox(width: 14),
        Text(
          '${_name(l, low)} – ${_name(l, low + span)}',
          style: const TextStyle(
            color: GameColors.textDim,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 14),
        GameRoundButton(
          icon: Icons.chevron_right_rounded,
          onTap: low + span < _highest ? () => _shift(1, span) : null,
          size: 44,
          tooltip: l.octaveUp,
        ),
      ],
    );
  }
}

/// MIDI status: connected device name, or a button to connect.
class _MidiChip extends StatelessWidget {
  const _MidiChip({required this.label, required this.onTap});

  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final connected = label != null;
    final text = label ?? AppLocalizations.of(context).connectMidi;
    return Pressable(
      onTap: onTap,
      semanticLabel: text,
      burstColor: GameColors.cyan,
      builder: (p, hover) => Container(
        constraints: const BoxConstraints(maxWidth: 190, minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: ShapeDecoration(
          shape: chamfer(
            10,
            side: BorderSide(
              color: connected ? GameColors.success : GameColors.panelEdge,
            ),
          ),
          color: GameColors.panel.withValues(alpha: hover ? 1 : 0.85),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              connected ? Icons.usb_rounded : Icons.usb_off_rounded,
              size: 20,
              color: connected ? GameColors.success : GameColors.textDim,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
