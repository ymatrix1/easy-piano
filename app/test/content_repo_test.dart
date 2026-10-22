import 'dart:io';

import 'package:easy_piano/content/content_repo.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the real content/ folder the same way the app loads its assets.
Map<String, String> _contentFiles() {
  final root = Directory('../content').absolute;
  return {
    for (final f in root.listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.json') && !f.path.contains('schema'))
        f.uri.pathSegments.skip(root.uri.pathSegments.length - 1).join('/'): f
            .readAsStringSync(),
  };
}

void main() {
  final files = _contentFiles();

  test('loads Piano Basics with five nodes, levels and songs', () {
    final repo = ContentRepo.fromFiles(files);
    final pb = repo.courses.first;
    expect(pb.id, 'piano-basics');
    expect(pb.nodes, hasLength(5));
    for (final node in pb.nodes) {
      for (final l in node.levels) {
        expect(repo.levels[l], isNotNull, reason: l);
      }
    }
    final ode = repo.levels['pb-05-ode-to-joy']!;
    expect(ode.stages.map((s) => s.type), ['wait', 'play_along', 'play_along']);
    expect(ode.stages[1].tempo, 0.7);
    expect(repo.songJson['ode-to-joy'], contains('Beethoven'));
  });

  test('sections and planned modules load', () {
    final repo = ContentRepo.fromFiles(files);
    expect(repo.sections.map((s) => s.id), ['basic', 'main', 'methods']);
    final planned = repo.courses.where((c) => c.planned).toList();
    for (final id in [
      'essentials-1',
      'essentials-2',
      'essentials-3',
      'mikrokosmos-1',
    ]) {
      final course = repo.courses.firstWhere((c) => c.id == id);
      expect(course.planned, isFalse);
      for (final node in course.nodes) {
        for (final l in node.levels) {
          expect(repo.levels[l], isNotNull, reason: l);
        }
      }
    }
    expect(planned.every((c) => c.nodes.isEmpty), isTrue);
    expect(repo.courses.first.planned, isFalse);
  });

  test('pubspec bundles every content folder', () {
    // Flutter assets are not recursive: a folder missing here 404s on web.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final root = Directory('../content').absolute;
    for (final d in root.listSync(recursive: true).whereType<Directory>()) {
      final rel = d.uri.pathSegments
          .skip(root.uri.pathSegments.length - 1)
          .where((s) => s.isNotEmpty)
          .join('/');
      // schema: editor help; skill-specs: content pipeline only (D17).
      if (rel.startsWith('schema') || rel.startsWith('skill-specs')) continue;
      if (d.listSync().whereType<File>().isEmpty) continue;
      expect(pubspec, contains('- assets/content/$rel/'), reason: rel);
    }
  });

  test('strings resolve in locale with English fallback', () {
    final pt = ContentRepo.fromFiles(files, locale: 'pt-BR');
    expect(pt.t('str:course.pb.title'), 'Piano Básico');
    final missing = ContentRepo.fromFiles(files, locale: 'xx');
    expect(missing.t('str:course.pb.title'), 'Piano Basics');
    expect(missing.t('str:no.such.key'), 'no.such.key');
  });

  test('level ui, keyboard and stage repeats default are parsed', () {
    final repo = ContentRepo.fromFiles(files);
    final pb1 = repo.levels['pb-01-find-c']!;
    expect(pb1.ui, 'treble');
    expect(pb1.keyboard, isTrue);
    final drill = repo.levels['pb-02-c-d-e']!.stages.firstWhere(
      (s) => s.type == 'wait',
    );
    expect(drill.repeats, 1); // reference has no repeats; field defaults to 1
  });

  test('scene captions come out in order', () {
    final repo = ContentRepo.fromFiles(files);
    expect(sceneCaptions(repo.scenes['pb-find-c']!), [
      'str:scene.findc.1',
      'str:scene.findc.2',
    ]);
  });
}
