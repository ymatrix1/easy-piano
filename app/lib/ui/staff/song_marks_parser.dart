import 'dart:convert';
import 'dart:math' as math;

import 'package:easy_piano/ui/staff/dynamics_layout.dart';
import 'package:easy_piano/ui/staff/repeat_layout.dart';
import 'package:easy_piano/ui/staff/song_rest_parser.dart';

/// Dynamics, hairpins, repeat barlines, voltas and navigation marks of one
/// song, in beats.
class SongMarks {
  const SongMarks({
    required this.dynamics,
    required this.hairpins,
    this.repeatBarlines = const [],
    this.voltas = const [],
    this.navigation = const [],
  });

  static const empty = SongMarks(dynamics: [], hairpins: []);

  final List<StaffDynamic> dynamics;
  final List<StaffHairpin> hairpins;

  /// Repeat signs (`|:`, `:|`, `:|:`) at bar lines.
  final List<StaffRepeatBarline> repeatBarlines;

  /// First and second endings.
  final List<StaffVolta> voltas;

  /// Segno, coda and jump marks above the staff.
  final List<StaffNavigation> navigation;
}

/// Reads dynamic, hairpin, repeat and navigation directives from a song JSON
/// string.
///
/// Directives sit in a hand string like notes do (zero length):
/// - `{dyn:"p"}` sets a dynamic at that beat (see [DynamicsLayout.glyphsFor]).
/// - `{cresc}` / `{dim}` open a hairpin at that beat.
/// - `{end}` closes the open hairpin.
/// - `{repeat_start}` / `{repeat_end}` put a repeat sign on the bar line at
///   that beat (`|:` / `:|`; both on one bar line draw `:|:`).
/// - `{volta: [1]}` / `{volta: [2]}` open a first or second ending on that bar
///   line. `{volta_end}` closes it on a bar line without a repeat sign.
/// - `{segno}`, `{coda}`, `{dc_al_fine}`, `{ds_al_coda}` put a navigation mark
///   above the staff at that beat.
///
/// An open hairpin also closes at the next dynamic, the next hairpin, or the
/// end of the song. A volta closes at the next `{repeat_end}` (its right end
/// then has a hook), at the next volta, at `{volta_end}`, or at the end of the
/// song (open end). Repeat and volta directives off a bar line are ignored.
///
/// Unknown dynamic text is ignored here; lint is responsible for rejecting it
/// in content.
abstract final class SongMarksParser {
  static final _dynDirective = RegExp(r'^\{dyn:"([^"]*)"\}$');
  static final _voltaDirective = RegExp(r'^\{volta:\s*\[\s*([12])\s*\]\s*\}$');

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
              final e = _directive(tok, beat, num);
              if (e != null) add(e.withHand(isLh));
              continue;
            }
            final colonIdx = tok.indexOf(':');
            if (colonIdx == -1) continue;
            var tail = tok.substring(colonIdx + 1);
            final parenIdx = tail.indexOf('(');
            if (parenIdx != -1) tail = tail.substring(0, parenIdx);
            final atIdx = tail.indexOf('@');
            if (atIdx != -1) tail = tail.substring(0, atIdx);
            t += SongRestParser.parseDurBeats(tail, den);
          }
        }
      }

      final totalBeats = rawBars.length * num;
      final structure = _buildStructure(events, totalBeats: totalBeats);
      return _build(
        events,
        totalBeats: totalBeats,
        repeatBarlines: structure.repeatBarlines,
        voltas: structure.voltas,
        navigation: structure.navigation,
      );
    } catch (_) {
      // Malformed song: draw no marks rather than break the score.
      return SongMarks.empty;
    }
  }

  static _Event? _directive(String tok, double beat, double num) {
    final dyn = _dynDirective.firstMatch(tok);
    if (dyn != null) {
      final mark = dyn.group(1)!;
      if (DynamicsLayout.glyphsFor(mark) == null) return null;
      return _Event(beat, _Kind.dynamic, mark: mark);
    }
    final volta = _voltaDirective.firstMatch(tok);
    if (volta != null) {
      if (!_onBarLine(beat, num)) return null;
      return _Event(beat, _Kind.voltaStart, mark: volta.group(1)!);
    }
    final nav = _navigationKinds[tok];
    if (nav != null) {
      return _Event(beat, _Kind.navigation, mark: nav.name);
    }
    final structural = switch (tok) {
      '{repeat_start}' => _Kind.repeatStart,
      '{repeat_end}' => _Kind.repeatEnd,
      '{volta_end}' => _Kind.voltaEnd,
      _ => null,
    };
    if (structural != null) {
      if (!_onBarLine(beat, num)) return null;
      return _Event(beat, structural);
    }
    return switch (tok) {
      '{cresc}' => _Event(beat, _Kind.open, hairpin: HairpinKind.crescendo),
      '{dim}' => _Event(beat, _Kind.open, hairpin: HairpinKind.diminuendo),
      '{end}' => _Event(beat, _Kind.end),
      _ => null,
    };
  }

  static const _navigationKinds = {
    '{segno}': NavigationKind.segno,
    '{coda}': NavigationKind.coda,
    '{dc_al_fine}': NavigationKind.dcAlFine,
    '{ds_al_coda}': NavigationKind.dsAlCoda,
  };

  /// True when [beat] falls on the start of a bar (or the end of the last
  /// bar). [num] is the bar length in beats.
  static bool _onBarLine(double beat, double num) {
    if (num <= 0) return false;
    final k = beat / num;
    return (k - k.roundToDouble()).abs() < 1e-6;
  }

  /// Repeat signs, voltas and navigation marks, from the structural events.
  static ({
    List<StaffRepeatBarline> repeatBarlines,
    List<StaffVolta> voltas,
    List<StaffNavigation> navigation,
  })
  _buildStructure(List<_Event> events, {required double totalBeats}) {
    // Same-beat order: a repeat end and a volta end close the ending before a
    // new volta or a repeat start opens at that bar line.
    const priority = {
      _Kind.repeatEnd: 0,
      _Kind.voltaEnd: 1,
      _Kind.voltaStart: 2,
      _Kind.repeatStart: 3,
      _Kind.navigation: 4,
    };
    final ordered =
        [
          for (final e in events)
            if (priority.containsKey(e.kind)) e,
        ]..sort((a, b) {
          final c = a.beat.compareTo(b.beat);
          return c != 0 ? c : priority[a.kind]!.compareTo(priority[b.kind]!);
        });

    // Repeat signs by bar line: the start and end flags of each beat.
    final repeats = <int, ({double beat, bool start, bool end})>{};
    void mark(double beat, {bool start = false, bool end = false}) {
      final key = (beat * 1000).round();
      final prev = repeats[key];
      repeats[key] = (
        beat: prev?.beat ?? beat,
        start: (prev?.start ?? false) || start,
        end: (prev?.end ?? false) || end,
      );
    }

    final voltas = <StaffVolta>[];
    final navigation = <StaffNavigation>[];
    int? openNumber;
    var openAt = 0.0;
    void closeVolta(double at, {required bool closedEnd}) {
      if (openNumber == null) return;
      if (at - openAt > 1e-6) {
        voltas.add(
          StaffVolta(
            startBeat: openAt,
            endBeat: at,
            number: openNumber!,
            closedEnd: closedEnd,
          ),
        );
      }
      openNumber = null;
    }

    for (final e in ordered) {
      switch (e.kind) {
        case _Kind.repeatStart:
          mark(e.beat, start: true);
        case _Kind.repeatEnd:
          mark(e.beat, end: true);
          closeVolta(e.beat, closedEnd: true);
        case _Kind.voltaEnd:
          closeVolta(e.beat, closedEnd: false);
        case _Kind.voltaStart:
          closeVolta(e.beat, closedEnd: false);
          openNumber = int.parse(e.mark!);
          openAt = e.beat;
        case _Kind.navigation:
          navigation.add(
            StaffNavigation(e.beat, NavigationKind.values.byName(e.mark!)),
          );
        case _Kind.dynamic || _Kind.open || _Kind.end:
          break;
      }
    }
    closeVolta(totalBeats, closedEnd: false);

    final repeatBarlines = [
      for (final r in repeats.values)
        StaffRepeatBarline(r.beat, start: r.start, end: r.end),
    ]..sort((a, b) => a.beat.compareTo(b.beat));
    return (
      repeatBarlines: repeatBarlines,
      voltas: voltas,
      navigation: navigation,
    );
  }

  static SongMarks _build(
    List<_Event> events, {
    required double totalBeats,
    required List<StaffRepeatBarline> repeatBarlines,
    required List<StaffVolta> voltas,
    required List<StaffNavigation> navigation,
  }) {
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
        case _Kind.repeatStart ||
            _Kind.repeatEnd ||
            _Kind.voltaStart ||
            _Kind.voltaEnd ||
            _Kind.navigation:
          break;
      }
    }
    closeAt(totalBeats);
    return SongMarks(
      dynamics: dynamics,
      hairpins: hairpins,
      repeatBarlines: repeatBarlines,
      voltas: voltas,
      navigation: navigation,
    );
  }
}

enum _Kind {
  dynamic,
  open,
  end,
  repeatStart,
  repeatEnd,
  voltaStart,
  voltaEnd,
  navigation,
}

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
