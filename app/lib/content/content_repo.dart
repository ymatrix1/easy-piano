import 'dart:convert';

import 'package:flutter/services.dart';

/// One stage of a level (docs/specs/content-format.md).
class StageDef {
  const StageDef({
    required this.type,
    this.score,
    this.scene,
    this.tempo = 1.0,
    this.pass = 0.7,
    this.hand = 'RH',
    this.preListen = false,
    this.repeats = 1,
  });

  factory StageDef.fromJson(Map<String, dynamic> j) => StageDef(
    type: j['type'] as String,
    score: j['score'] as String?,
    scene: j['scene'] as String?,
    tempo: (j['tempo'] as num?)?.toDouble() ?? 1.0,
    pass: (j['pass'] as num?)?.toDouble() ?? 0.7,
    hand: j['hand'] as String? ?? 'RH',
    preListen: j['pre_listen'] as bool? ?? false,
    repeats: j['repeats'] as int? ?? 1,
  );

  final String type;
  final String? score;
  final String? scene;
  final double tempo;
  final double pass;
  final String hand;
  final bool preListen;

  /// Wait stages repeat this many times in a row (counter shown in the top bar).
  final int repeats;

  bool get isPlayable =>
      type == 'wait' || type == 'play_along' || type == 'one_note';
}

class LevelDef {
  const LevelDef({
    required this.id,
    required this.title,
    required this.stages,
    this.ui = 'both',
    this.keyboard = true,
  });

  factory LevelDef.fromJson(Map<String, dynamic> j) => LevelDef(
    id: j['id'] as String,
    title: j['title'] as String,
    stages: [
      for (final s in j['stages'] as List)
        StageDef.fromJson(s as Map<String, dynamic>),
    ],
    ui: j['ui'] as String? ?? 'both',
    keyboard: j['keyboard'] as bool? ?? true,
  );

  final String id;
  final String title;
  final List<StageDef> stages;

  /// Staff layout: `treble` / `bass` single staff (beginner), `both` grand staff.
  final String ui;

  /// Whether the on-screen keyboard shows by default.
  final bool keyboard;
}

class JourneyNode {
  const JourneyNode({
    required this.id,
    required this.kind,
    required this.title,
    required this.levels,
    required this.songs,
  });

  factory JourneyNode.fromJson(Map<String, dynamic> j) => JourneyNode(
    id: j['id'] as String,
    kind: j['kind'] as String,
    title: j['title'] as String,
    levels: [for (final l in j['levels'] as List) l as String],
    songs: {
      for (final e in ((j['songs'] as Map?) ?? {}).entries)
        e.key as String: e.value as String,
    },
  );

  final String id;
  final String kind;
  final String title;
  final List<String> levels;

  /// Taste → song id slots (D12).
  final Map<String, String> songs;
}

/// A module (course). Planned modules are listed, locked, without a journey.
class CourseDef {
  const CourseDef({
    required this.id,
    required this.title,
    required this.description,
    required this.nodes,
    this.section = '',
    this.planned = false,
  });

  final String id;
  final String title;
  final String description;

  /// Journey nodes, shown as submodules; each holds levels (tasks).
  final List<JourneyNode> nodes;
  final String section;
  final bool planned;
}

/// A named group of modules (e.g. Basics).
class SectionDef {
  const SectionDef({required this.id, required this.title});

  final String id;
  final String title;
}

/// Scene caption lines in order (the scene player itself is Phase 2).
List<String> sceneCaptions(Map<String, dynamic> scene) => [
  for (final t in scene['tracks'] as List)
    if ((t as Map)['caption'] is String) t['caption'] as String,
];

/// All lesson content, loaded from the assets synced by tools/sync_content.py.
class ContentRepo {
  ContentRepo({
    required this.courses,
    this.sections = const [],
    required this.levels,
    required this.songJson,
    required this.scenes,
    required this.strings,
    required this.fallback,
  });

  final List<CourseDef> courses;
  final List<SectionDef> sections;
  final Map<String, LevelDef> levels;
  final Map<String, String> songJson;
  final Map<String, Map<String, dynamic>> scenes;

  /// Strings in the user's locale, and English as fallback.
  final Map<String, String> strings;
  final Map<String, String> fallback;

  /// Resolves `str:key` (or a bare key) in the user's locale, then English.
  String t(String ref) {
    final key = ref.startsWith('str:') ? ref.substring(4) : ref;
    return strings[key] ?? fallback[key] ?? key;
  }

  static Map<String, String> _stringMap(String text) =>
      (jsonDecode(text) as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      );

  /// Builds the repo from a file map (path relative to content/ → text). Pure; used by tests.
  static ContentRepo fromFiles(
    Map<String, String> files, {
    String locale = 'en',
  }) {
    Map<String, dynamic> json(String path) =>
        jsonDecode(files[path]!) as Map<String, dynamic>;
    final levels = <String, LevelDef>{};
    final songs = <String, String>{};
    final scenes = <String, Map<String, dynamic>>{};
    for (final path in files.keys) {
      if (path.contains('/levels/')) {
        final l = LevelDef.fromJson(json(path));
        levels[l.id] = l;
      } else if (path.startsWith('songs/')) {
        songs[path.substring(6, path.length - 5)] = files[path]!;
      } else if (path.startsWith('scenes/')) {
        scenes[path.substring(7, path.length - 5)] = json(path);
      }
    }
    final index = json('courses.json');
    final sections = [
      for (final s in (index['sections'] as List?) ?? const [])
        SectionDef(id: s['id'] as String, title: s['title'] as String),
    ];
    final courses = [
      for (final c in index['courses'] as List)
        CourseDef(
          id: c['id'] as String,
          title: c['title'] as String,
          description: c['description'] as String,
          section: c['section'] as String? ?? '',
          planned: c['status'] == 'planned',
          nodes: c['journey'] == null
              ? const []
              : [
                  for (final n in json(c['journey'] as String)['nodes'] as List)
                    JourneyNode.fromJson(n as Map<String, dynamic>),
                ],
        ),
    ];
    final en = _stringMap(files['strings/en.json']!);
    final local = files['strings/$locale.json'];
    return ContentRepo(
      courses: courses,
      sections: sections,
      levels: levels,
      songJson: songs,
      scenes: scenes,
      strings: local == null ? en : _stringMap(local),
      fallback: en,
    );
  }

  static Future<ContentRepo> load({String locale = 'en'}) async {
    const base = 'assets/content';
    final index = jsonDecode(
      await rootBundle.loadString('$base/index.json'),
    ) as Map<String, dynamic>;
    final files = <String, String>{};
    for (final f in index['files'] as List) {
      files[f as String] = await rootBundle.loadString('$base/$f');
    }
    return fromFiles(files, locale: locale);
  }
}
