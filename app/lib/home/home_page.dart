import 'package:flutter/material.dart';

import '../content/content_repo.dart';
import '../input/midi_input.dart';
import '../practice/level_page.dart';
import '../ui/staff/staff_spike_page.dart';

/// Course map v0: the journey of each course as a list of nodes.
/// Progress lives in memory until the progress store lands (Phase 2).
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repo,
    required this.midi,
    required this.spikes,
  });

  final ContentRepo repo;
  final MidiInput midi;

  /// Opens the Phase 0 MIDI spike page.
  final WidgetBuilder spikes;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _stars = <String, int>{}; // node id → stars

  IconData _icon(String kind) => switch (kind) {
    'song' => Icons.music_note,
    'boss' || 'mini_boss' => Icons.emoji_events_outlined,
    'star_gate' => Icons.star_border,
    _ => Icons.school_outlined,
  };

  Future<void> _open(JourneyNode node) async {
    final level = widget.repo.levels[node.levels.first];
    if (level == null) return;
    final stars = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) =>
            LevelPage(repo: widget.repo, level: level, midi: widget.midi),
      ),
    );
    if (stars != null && stars > (_stars[node.id] ?? 0)) {
      setState(() => _stars[node.id] = stars);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Easy Piano'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => Navigator.of(context).push(
              MaterialPageRoute(
                builder: v == 'midi'
                    ? widget.spikes
                    : (_) => const StaffSpikePage(),
              ),
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'midi', child: Text('MIDI spike')),
              PopupMenuItem(value: 'staff', child: Text('Staff spike')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final course in repo.courses) ...[
            Text(
              repo.t(course.title),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(repo.t(course.description)),
            ),
            for (final (i, node) in course.nodes.indexed)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(_icon(node.kind))),
                  title: Text('${i + 1}. ${repo.t(node.title)}'),
                  subtitle: Text(node.kind.replaceAll('_', ' ')),
                  trailing: Text(
                    '★' * (_stars[node.id] ?? 0),
                    style: TextStyle(
                      color: Colors.amber.shade700,
                      fontSize: 18,
                    ),
                  ),
                  onTap: () => _open(node),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
