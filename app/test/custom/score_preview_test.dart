import 'dart:convert';

import 'package:easy_piano/custom/custom_score.dart';
import 'package:easy_piano/custom/score_preview.dart';
import 'package:easy_piano/custom/score_staff_strip.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/ui/game/game_widgets.dart';
import 'package:easy_piano/ui/staff/staff_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _songJson({Map<String, String>? bar, double bpm = 100}) => jsonEncode({
  'id': 'ode',
  'title': 'Ode',
  'composer': 'Beethoven',
  'bpm': bpm,
  'time': '3/4',
  'key': 'G',
  'bars': [
    bar ?? {'RH': 'G4:4 A4:4 B4:4', 'LH': 'G2:2 D3:4'},
  ],
});

CustomScore _score({String title = 'Ode to Joy', Map<String, String>? bar}) =>
    CustomScore(
      id: 'ode',
      title: title,
      composer: 'Beethoven',
      fileName: 'ode.mid',
      bars: 1,
      timeSignature: '3/4',
      songJson: _songJson(bar: bar),
      importedAt: DateTime.utc(2026),
    );

const _notes = [
  StaffNote(67, 0, 1),
  StaffNote(69, 1, 1),
  StaffNote(71, 2, 1),
  StaffNote(43, 0, 2, leftHand: true),
];

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: home,
);

Widget _opener(CustomScore score, List<StaffNote> notes, VoidCallback onPlay) =>
    _app(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showScorePreview(context, score, notes: notes, onPlay: onPlay),
            child: const Text('open'),
          ),
        ),
      ),
    );

Finder textCI(String s) => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? '').toLowerCase() == s.toLowerCase(),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('preview shows title, composer, key, tempo, meter and hands', (
    tester,
  ) async {
    await tester.pumpWidget(_opener(_score(), _notes, () {}));
    await _open(tester);

    expect(find.text('Ode to Joy'), findsOneWidget);
    expect(find.text('Beethoven'), findsOneWidget);
    expect(find.text('Key G'), findsOneWidget);
    expect(find.text('100 BPM'), findsOneWidget);
    expect(find.text('Time 3/4'), findsOneWidget);
    expect(find.text('1 bars'), findsOneWidget);
    expect(find.text('Both hands'), findsOneWidget);
    expect(find.textContaining('Estimated level: '), findsOneWidget);
  });

  testWidgets('preview draws a staff of the first bars when it has notes', (
    tester,
  ) async {
    await tester.pumpWidget(_opener(_score(), _notes, () {}));
    await _open(tester);
    expect(find.byType(ScoreStaffStrip), findsOneWidget);

    await tester.tap(textCI('Close'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(_opener(_score(), const [], () {}));
    await _open(tester);
    expect(find.byType(ScoreStaffStrip), findsNothing);
  });

  testWidgets('preview says one hand when the score has one', (tester) async {
    await tester.pumpWidget(
      _opener(_score(bar: {'RH': 'G4:4 A4:4 B4:4'}), _notes, () {}),
    );
    await _open(tester);
    expect(find.text('Right hand only'), findsOneWidget);
  });

  testWidgets('preview reminds the player the file stays on the device', (
    tester,
  ) async {
    await tester.pumpWidget(_opener(_score(), _notes, () {}));
    await _open(tester);
    expect(find.textContaining('never uploaded'), findsOneWidget);
    expect(find.textContaining('right to use'), findsOneWidget);
  });

  testWidgets('Practice starts the score and closes the preview', (
    tester,
  ) async {
    var played = false;
    await tester.pumpWidget(_opener(_score(), _notes, () => played = true));
    await _open(tester);

    await tester.tap(textCI('Practice'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(played, isTrue);
    expect(find.text('Beethoven'), findsNothing);
  });

  testWidgets('Close leaves without playing', (tester) async {
    var played = false;
    await tester.pumpWidget(_opener(_score(), _notes, () => played = true));
    await _open(tester);

    await tester.tap(textCI('Close'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(played, isFalse);
    expect(find.text('Beethoven'), findsNothing);
  });

  testWidgets('preview is a game panel, not a stock dialog', (tester) async {
    await tester.pumpWidget(_opener(_score(), _notes, () {}));
    await _open(tester);
    expect(find.byType(GamePanel), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SimpleDialog), findsNothing);
  });

  for (final size in const [Size(375, 667), Size(1280, 800), Size(667, 375)]) {
    testWidgets('a very long title fits without overflow at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final title = List.filled(12, 'Variations on a theme').join(' ');
      await tester.pumpWidget(_opener(_score(title: title), _notes, () {}));
      await _open(tester);

      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.byType(GamePanel));
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(size.width));
      expect(textCI('Practice'), findsOneWidget);
    });
  }
}
