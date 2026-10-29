import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../practice/generated/practice_service.dart';

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
    this.starsNeeded,
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
    starsNeeded: (j['stars_needed'] as num?)?.toInt(),
  );

  final String id;
  final String kind;
  final String title;
  final List<String> levels;

  /// Taste → song id slots (D12).
  final Map<String, String> songs;

  /// `star_gate` only: stars to earn across its levels (pick any songs).
  final int? starsNeeded;
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
    required Map<String, Map<String, String>> stringsByLocale,
    this.locale = 'en',
    this.practice = const {},
    this.melodyManifest,
  }) : _byLocale = stringsByLocale;

  final List<CourseDef> courses;
  final List<SectionDef> sections;
  final Map<String, LevelDef> levels;
  final Map<String, String> songJson;
  final Map<String, Map<String, dynamic>> scenes;

  /// Practice mode per `course/node` (`practice.json`, docs/specs/practice-mode.md).
  final Map<String, PracticeNodeDef> practice;

  /// Melody model release manifest (`melody-model-v1.json`), or null.
  final String? melodyManifest;

  /// Content strings per locale tag (`en`, `pt-BR`, ...), from `strings/<tag>.json`.
  final Map<String, Map<String, String>> _byLocale;

  /// Locale tags that have a strings file.
  Iterable<String> get locales => _byLocale.keys;

  /// All content strings by locale tag; a derived repo (imported scores) keeps them.
  Map<String, Map<String, String>> get stringsByLocale => _byLocale;

  /// Active content locale tag. See docs/specs/i18n.md.
  String locale;

  /// Strings in the active locale, and English as fallback.
  Map<String, String> get strings => _byLocale[locale] ?? fallback;
  Map<String, String> get fallback => _byLocale['en'] ?? const {};

  /// Resolves `str:key` (or a bare key) in the active locale, then its base
  /// language (`pt` for `pt-BR`), then English, then the key itself.
  String t(String ref) {
    final key = ref.startsWith('str:') ? ref.substring(4) : ref;
    final base = locale.split('-').first;
    return _byLocale[locale]?[key] ??
        _byLocale[base]?[key] ??
        fallback[key] ??
        key;
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
    final byLocale = <String, Map<String, String>>{
      for (final path in files.keys)
        if (path.startsWith('strings/') && path.endsWith('.json'))
          path.substring(8, path.length - 5): _stringMap(files[path]!),
    };
    return ContentRepo(
      courses: courses,
      sections: sections,
      levels: levels,
      songJson: songs,
      scenes: scenes,
      stringsByLocale: byLocale,
      locale: locale,
      practice: files['practice.json'] == null
          ? const {}
          : PracticeNodeDef.parsePack(files['practice.json']!),
      melodyManifest: files['melody-model-v1.json'],
    );
  }

  static Future<ContentRepo> load({String locale = 'en'}) async {
    const base = 'assets/content';
    // One request for all content (written by tools/sync_content.py); falls
    // back to per-file loads, in parallel, for an older asset sync.
    try {
      final bundle = jsonDecode(
        await rootBundle.loadString('$base/bundle.json', cache: false),
      ) as Map<String, dynamic>;
      return fromFiles(bundle.cast<String, String>(), locale: locale);
    } on FlutterError {
      // No bundle.json in the assets.
    }
    final index = jsonDecode(
      await rootBundle.loadString('$base/index.json'),
    ) as Map<String, dynamic>;
    final paths = [for (final f in index['files'] as List) f as String];
    final texts = await Future.wait(
      paths.map((f) => rootBundle.loadString('$base/$f')),
    );
    return fromFiles(Map.fromIterables(paths, texts), locale: locale);
  }
}
