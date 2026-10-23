import 'package:easy_piano/content/content_repo.dart';
import 'package:easy_piano/input/midi_input.dart';
import 'package:easy_piano/l10n/app_localizations.dart';
import 'package:easy_piano/practice/practice_stage.dart';
import 'package:easy_piano/src/rust/api/practice.dart';
import 'package:easy_piano/src/rust/frb_generated.dart';
import 'package:easy_piano/ui/keyboard_painter.dart';
import 'package:easy_piano/ui/staff/staff_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rust is not loaded in `flutter test`: a stub API serves two targets
/// (C4, D4) at 120 bpm, so the demo lasts about 1.25 s after a 0.4 s lead.
class _FakeApi implements RustLibApi {
  @override
  SongInfo crateApiPracticeInspectSong({required String json}) =>
      const SongInfo(
        id: 't',
        title: 't',
        composer: 't',
        bpm: 120,
        beatsPerBar: 4,
        bars: 1,
      );

  @override
  PracticeSession crateApiPracticePracticeSessionCreate({
    required String songJson,
    required String mode,
    required String input,
    required String hand,
    required double tempo,
    required double passRatio,
    required int failedAttempts,
    required bool training,
  }) => _FakeSession();

  @override
  List<NoteView> crateApiPracticeCompanion({
    required String songJson,
    required String hand,
  }) => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSession implements PracticeSession {
  @override
  List<TargetView> targets() => [
    for (final (i, p) in [60, 62].indexed)
      TargetView(
        beat: i.toDouble(),
        beats: 1,
        bar: 0,
        pitches: Uint8List.fromList([p]),
        fingers: Uint8List(0),
        stemDowns: const [false],
        twoStems: const [false],
        state: 0,
      ),
  ];

  @override
  FrameView tick({required PlatformInt64 tUs}) => const FrameView(
    playheadBeat: 0,
    cursor: 0,
    hits: 0,
    misses: 0,
    wrong: 0,
    done: false,
    hintActive: false,
    streak: 0,
  );

  @override
  SectionEventView? takeSectionEvent() => null;

  @override
  List<FeedbackView> takeFeedback() => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Clock implements MidiInput {
  double ms = 1000;

  @override
  Stream<NoteEvent> get events => const Stream.empty();

  @override
  List<String> get deviceNames => const [];

  @override
  Future<bool> start() async => false;

  @override
  double now() => ms;
}

final _keyboard = find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is KeyboardPainter,
);

void main() {
  setUp(() => RustLib.initMock(api: _FakeApi()));
  tearDown(RustLib.dispose);

  Future<_Clock> pumpStage(
    WidgetTester tester, {
    bool preListen = true,
    bool showKeyboard = true,
    VoidCallback? onToggleKeyboard,
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clock = _Clock();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PracticeStage(
            stage: StageDef(type: 'wait', preListen: preListen),
            songJson: '{}',
            midi: clock,
            failedAttempts: 0,
            onFinished: (_) {},
            staves: Staves.treble,
            tempo: 1,
            onTempo: (_) {},
            onRestart: () {},
            onExit: () {},
            showKeyboard: showKeyboard,
            onToggleKeyboard: onToggleKeyboard,
          ),
        ),
      ),
    );
    await tester.pump();
    return clock;
  }

  testWidgets('keyboard is hidden during the demo and back after Skip', (
    tester,
  ) async {
    await pumpStage(tester);
    expect(find.text('Listen first…'), findsOneWidget);
    expect(_keyboard, findsNothing);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.text('Listen first…'), findsNothing);
    expect(_keyboard, findsOneWidget);
  });

  testWidgets('keyboard is back once the demo ends by itself', (tester) async {
    final clock = await pumpStage(tester);
    expect(_keyboard, findsNothing);

    clock.ms += 5000;
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Listen first…'), findsNothing);
    expect(_keyboard, findsOneWidget);
  });

  testWidgets('no demo: keyboard shows from the start', (tester) async {
    await pumpStage(tester, preListen: false);
    expect(_keyboard, findsOneWidget);
  });

  testWidgets('keyboard stays hidden when the level hides it', (tester) async {
    await pumpStage(tester, showKeyboard: false);
    expect(_keyboard, findsNothing);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(_keyboard, findsNothing);
  });

  testWidgets('pause during the demo keeps the keyboard hidden', (
    tester,
  ) async {
    await pumpStage(tester);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    // The pause buttons slide in: let their entrance timers and tweens run.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(_keyboard, findsNothing);
    // Skip is not offered while paused; resume returns to the demo.
    expect(find.text('Skip'), findsNothing);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('Skip'), findsOneWidget);
    expect(_keyboard, findsNothing);
  });

  testWidgets('keyboard toggle is disabled during the demo only', (
    tester,
  ) async {
    var toggles = 0;
    await pumpStage(tester, onToggleKeyboard: () => toggles++);
    await tester.tap(find.byTooltip('Hide keyboard'), warnIfMissed: false);
    await tester.pump();
    expect(toggles, 0);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.tap(find.byTooltip('Hide keyboard'));
    await tester.pump();
    expect(toggles, 1);
  });
}
