import 'package:flutter/material.dart';

import '../content/content_repo.dart';
import '../input/midi_input.dart';
import '../src/rust/api/practice.dart';
import 'practice_stage.dart';

/// Runs a level's stages in order: scenes (captions until the Phase 2 player),
/// then playable stages graded by the core, with a result card after each.
class LevelPage extends StatefulWidget {
  const LevelPage({
    super.key,
    required this.repo,
    required this.level,
    required this.midi,
  });

  final ContentRepo repo;
  final LevelDef level;
  final MidiInput midi;

  @override
  State<LevelPage> createState() => _LevelPageState();
}

class _LevelPageState extends State<LevelPage> {
  int _index = 0;
  int _attempt = 0; // failed attempts on the current stage
  int _run = 0; // bumps to restart a stage widget
  ResultView? _result;
  final _bestStars = <int, int>{};

  StageDef get _stage => widget.level.stages[_index];
  bool get _last => _index == widget.level.stages.length - 1;

  void _next() => setState(() {
    if (_last) {
      Navigator.of(context)
          .pop(_bestStars.values.fold<int>(3, (a, b) => b < a ? b : a));
      return;
    }
    _index++;
    _attempt = 0;
    _result = null;
    _run++;
  });

  void _retry() => setState(() {
    if (_result != null && !_result!.passed) _attempt++;
    _result = null;
    _run++;
  });

  void _finished(ResultView r) => setState(() {
    _result = r;
    if (r.passed) {
      final best = _bestStars[_index] ?? 0;
      if (r.stars > best) _bestStars[_index] = r.stars;
    }
  });

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6C4CF1),
        scaffoldBackgroundColor: StagePalette.bgTop,
        appBarTheme: const AppBarTheme(
          backgroundColor: StagePalette.bgTop,
          foregroundColor: StagePalette.ink,
        ),
      ),
      child: _scaffold(context, repo),
    );
  }

  Widget _scaffold(BuildContext context, ContentRepo repo) {
    return Scaffold(
      appBar: AppBar(
        title: Text(repo.t(widget.level.title)),
        actions: [
          Center(
            child: Text(
              'Stage ${_index + 1} / ${widget.level.stages.length}  ',
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              final ok = await widget.midi.start();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? 'MIDI: ${widget.midi.deviceNames.isEmpty ? "no device yet" : widget.midi.deviceNames.join(", ")}'
                        : 'Web MIDI unavailable; use the on-screen keys',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.piano),
            label: const Text('Connect MIDI'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _stageBody(repo)),
          if (_result != null)
            Positioned.fill(child: _resultCard(context, _result!)),
        ],
      ),
    );
  }

  Widget _stageBody(ContentRepo repo) {
    final s = _stage;
    if (s.type == 'animation') {
      final scene = repo.scenes[s.scene];
      final lines = scene == null ? const <String>[] : sceneCaptions(scene);
      return _InfoStage(
        icon: Icons.movie_filter_outlined,
        title: 'Lesson scene',
        lines: [
          for (final l in lines) repo.t(l),
          '(Animated scene arrives with the Phase 2 scene player.)',
        ],
        onContinue: _next,
      );
    }
    if (!s.isPlayable || repo.songJson[s.score] == null) {
      return _InfoStage(
        icon: Icons.quiz_outlined,
        title: s.type,
        lines: const ['Not available yet.'],
        onContinue: _next,
      );
    }
    return PracticeStage(
      key: ValueKey('$_index-$_run'),
      stage: s,
      songJson: repo.songJson[s.score]!,
      midi: widget.midi,
      failedAttempts: _attempt,
      onFinished: _finished,
    );
  }

  Widget _resultCard(BuildContext context, ResultView r) {
    final text = Theme.of(context).textTheme;
    final timing = r.meanAbsTimingMs;
    return ColoredBox(
      color: Colors.black38,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  r.passed ? 'Great job!' : 'Almost there',
                  style: text.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '★' * r.stars + '☆' * (3 - r.stars),
                  style: text.displaySmall?.copyWith(
                    color: Colors.amber.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hit ${(r.hitRatio * 100).round()}% · wrong notes ${r.wrong}'
                  '${timing == null ? '' : ' · timing ±${timing.round()} ms'}',
                ),
                if (!r.passed)
                  Text('Need ${(r.threshold * 100).round()}% in each section'),
                if (r.suggestPractice)
                  const Text('Tip: try again at a slower tempo.'),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: _retry,
                      child: const Text('Retry'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: r.passed ? _next : null,
                      child: Text(_last ? 'Finish' : 'Next'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoStage extends StatelessWidget {
  const _InfoStage({
    required this.icon,
    required this.title,
    required this.lines,
    required this.onContinue,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(l, textAlign: TextAlign.center),
              ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onContinue, child: const Text('Continue')),
          ],
        ),
      ),
    );
  }
}
