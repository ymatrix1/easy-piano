import 'package:easy_piano/content/content_repo.dart';
import 'package:easy_piano/home/home_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repo = ContentRepo.fromFiles(const {
    'courses.json': '{"courses": []}',
    'strings/en.json': '{}',
  });
  const gate = JourneyNode(
    id: 'gate',
    kind: 'star_gate',
    title: 't',
    levels: ['a', 'b', 'c'],
    songs: {},
    starsNeeded: 5,
  );
  const lesson = JourneyNode(
    id: 'l',
    kind: 'lesson',
    title: 't',
    levels: ['a', 'b'],
    songs: {},
  );

  test('star gate opens with stars from any two of its songs', () {
    final p = Progress(repo, {'a': 3, 'c': 2});
    expect(p.gateStars(gate), 5);
    expect(p.nodeDone(gate), isTrue);
    expect(p.nodeStars(gate), 3);
  });

  test('star gate stays closed below its stars', () {
    final p = Progress(repo, {'a': 3, 'b': 1});
    expect(p.nodeDone(gate), isFalse);
    expect(p.nodeStars(gate), 2);
  });

  test('lesson still needs every task played', () {
    expect(Progress(repo, {'a': 3}).nodeDone(lesson), isFalse);
    expect(Progress(repo, {'a': 3, 'b': 1}).nodeStars(lesson), 1);
  });
}
