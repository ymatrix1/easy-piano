import 'dart:convert';
import 'dart:math' as math;

import 'package:easy_piano/ui/staff/arpeggio_layout.dart';
import 'package:easy_piano/ui/staff/dynamics_layout.dart';
import 'package:easy_piano/ui/staff/song_rest_parser.dart';

/// Dynamics, hairpins, arpeggios and glissandi of one song, in beats.
class SongMarks {
  const SongMarks({
    required this.dynamics,
    required this.hairpins,
    this.arpeggios = const [],
    this.glissandi = const [],
  });

  static const empty = SongMarks(dynamics: [], hairpins: []);

  final List<StaffDynamic> dynamics;
  final List<StaffHairpin> hairpins;
  final List<StaffArpeggio> arpeggios;
  final List<StaffGlissando> glissandi;
}

/// Reads dynamic and hairpin directives from a song JSON string.
///
/// Directives sit in a hand string like notes do (zero length):
/// - `{dyn:"p"}` sets a dynamic at that beat (see [DynamicsLayout.glyphsFor]).
/// - `{cresc}` / `{dim}` open a hairpin at that beat.
/// - `{end}` closes the open hairpin.
/// - `{arp}`, `{arp:up}`, `{arp:down}` put an arpeggio on the chord at that beat.
/// - `{gliss}` starts a glissando that ends at the next note of the same hand
///   (rests do not end it).
///
/// An open hairpin also closes at the next dynamic, the next hairpin, or the
/// end of the song. Unknown dynamic text is ignored here; lint is responsible
/// for rejecting it in content.
abstract final class SongMarksParser {
  static final _dynDirective = RegExp(r'^\{dyn:"([^"]*)"\}$');
  static final _arpDirective = RegExp(r'^\{arp(?::(up|down))?\}$');

  static SongMarks parse(String songJson) {
    if (songJson.isEmpty) return SongMarks.empty;
    try {
      final decoded = jsonDecode(songJson);
      if (decoded is! Map<String, dynamic>) return SongMarks.empty;
      final rawBars = decoded['bars'];
      if (rawBars is! List) return SongMarks.empty;

      final timeSig = decoded['time'] as String? ?? '4/4';
      final parts = timeSig.split('/');
      final num = double.tryParse(parts[0]) ?? 4.0;
      final den = parts.length > 1 ? (double.tryParse(parts[1]) ?? 4.0) : 4.0;

      final events = <_Event>[];
      final index = <String, int>{};
      final arpeggios = <StaffArpeggio>[];
      final glissandi = <StaffGlissando>[];
      // Open `{gliss}` per hand (key: left hand?). Closed by the next note.
      final pendingGliss = <bool, double>{};
      void add(_Event e) {
        // RH and LH often repeat the same directive at the same beat. Keep one
        // event, on the treble staff when either hand carries it.
        final key = '${e.beat}|${e.kind}|${e.mark}|${e.hairpin}';
        final at = index[key];
        if (at == null) {
          index[key] = events.length;
          events.add(e);
        } else if (events[at].leftHand && !e.leftHand) {
          events[at] = e;
        }
      }

      for (var b = 0; b < rawBars.length; b++) {
        final barMap = rawBars[b];
        if (barMap is! Map) continue;
        final barStart = b * num;

        for (final entry in barMap.entries) {
          final handKey = entry.key.toString();
          if (handKey != 'RH' &&
              handKey != 'LH' &&
              handKey != 'RH2' &&
              handKey != 'LH2') {
            continue;
          }
          final isLh = handKey.startsWith('LH');
          var t = 0.0;
          for (final rawTok in SongRestParser.tokenize(
            entry.value.toString(),
          )) {
            final tok = rawTok.trim();
            if (tok.isEmpty) continue;
            final beat = barStart + t;
            if (tok.startsWith('{')) {
              final arp = _arpDirective.firstMatch(tok);
              if (arp != null) {
                arpeggios.add(
                  StaffArpeggio(
                    beat,
                    direction: switch (arp.group(1)) {
                      'up' => ArpeggioDirection.up,
                      'down' => ArpeggioDirection.down,
                      _ => ArpeggioDirection.plain,
                    },
                    leftHand: isLh,
                  ),
                );
              } else if (tok == '{gliss}') {
                pendingGliss[isLh] = beat;
              } else {
                final e = _directive(tok, beat);
                if (e != null) add(e.withHand(isLh));
              }
              continue;
            }
            final colonIdx = tok.indexOf(':');
            if (colonIdx == -1) continue;
            final isRest = tok.substring(0, colonIdx) == 'r';
            final glissStart = pendingGliss[isLh];
            if (!isRest && glissStart != null && beat > glissStart) {
              glissandi.add(
                StaffGlissando(
                  startBeat: glissStart,
                  endBeat: beat,
                  leftHand: isLh,
                ),
              );
              pendingGliss.remove(isLh);
            }
            var tail = tok.substring(colonIdx + 1);
            final parenIdx = tail.indexOf('(');
            if (parenIdx != -1) tail = tail.substring(0, parenIdx);
            final atIdx = tail.indexOf('@');
            if (atIdx != -1) tail = tail.substring(0, atIdx);
            t += SongRestParser.parseDurBeats(tail, den);
          }
        }
      }

      final built = _build(events, totalBeats: rawBars.length * num);
      return SongMarks(
        dynamics: built.dynamics,
        hairpins: built.hairpins,
        arpeggios: arpeggios,
        glissandi: glissandi,
      );
    } catch (_) {
      // Malformed song: draw no marks rather than break the score.
      return SongMarks.empty;
    }
  }

  static _Event? _directive(String tok, double beat) {
    final dyn = _dynDirective.firstMatch(tok);
    if (dyn != null) {
      final mark = dyn.group(1)!;
      if (DynamicsLayout.glyphsFor(mark) == null) return null;
      return _Event(beat, _Kind.dynamic, mark: mark);
    }
    return switch (tok) {
      '{cresc}' => _Event(beat, _Kind.open, hairpin: HairpinKind.crescendo),
      '{dim}' => _Event(beat, _Kind.open, hairpin: HairpinKind.diminuendo),
      '{end}' => _Event(beat, _Kind.end),
      _ => null,
    };
  }

  static SongMarks _build(List<_Event> events, {required double totalBeats}) {
    events.sort((a, b) => a.beat.compareTo(b.beat));
    final dynamics = <StaffDynamic>[];
    final hairpins = <StaffHairpin>[];

    HairpinKind? openKind;
    var openAt = 0.0;
    var openLeftHand = false;

    void closeAt(double beat) {
      if (openKind == null) return;
      final end = math.min(beat, totalBeats);
      // A zero-length hairpin (closed on the beat it opened) draws nothing.
      if (end > openAt) {
        hairpins.add(
          StaffHairpin(
            startBeat: openAt,
            endBeat: end,
            kind: openKind!,
            leftHand: openLeftHand,
          ),
        );
      }
      openKind = null;
    }

    for (final e in events) {
      switch (e.kind) {
        case _Kind.dynamic:
          closeAt(e.beat);
          dynamics.add(StaffDynamic(e.beat, e.mark!, leftHand: e.leftHand));
        case _Kind.open:
          closeAt(e.beat);
          openKind = e.hairpin;
          openAt = e.beat;
          openLeftHand = e.leftHand;
        case _Kind.end:
          closeAt(e.beat);
      }
    }
    closeAt(totalBeats);
    return SongMarks(dynamics: dynamics, hairpins: hairpins);
  }
}

enum _Kind { dynamic, open, end }

class _Event {
  const _Event(
    this.beat,
    this.kind, {
    this.mark,
    this.hairpin,
    this.leftHand = false,
  });

  final double beat;
  final _Kind kind;
  final String? mark;
  final HairpinKind? hairpin;
  final bool leftHand;

  _Event withHand(bool lh) =>
      _Event(beat, kind, mark: mark, hairpin: hairpin, leftHand: lh);
}
