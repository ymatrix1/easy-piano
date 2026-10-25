import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import 'custom_score.dart';
import 'custom_score_controller.dart';

/// The imported scores on this device: search, practice and delete
/// (docs/specs/score-import-and-page-view.md 3.1).
class SongLibraryPage extends StatefulWidget {
  const SongLibraryPage({
    super.key,
    required this.controller,
    required this.onPlay,
  });

  final CustomScoreController controller;
  final ValueChanged<CustomScore> onPlay;

  @override
  State<SongLibraryPage> createState() => _SongLibraryPageState();
}

class _SongLibraryPageState extends State<SongLibraryPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(CustomScore score) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(score.title),
        content: Text(l.scoreDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.scoreDelete),
          ),
        ],
      ),
    );
    if (ok == true) await widget.controller.remove(score.id);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: GameColors.bgDeep,
      appBar: AppBar(
        backgroundColor: GameColors.panel,
        foregroundColor: GameColors.text,
        title: Text(l.songLibrary),
      ),
      body: MenuBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final c = widget.controller;
              if (!c.loaded) {
                return const Center(child: CircularProgressIndicator());
              }
              if (c.scores.isEmpty) {
                return _Message(l.songLibraryEmpty);
              }
              final shown = searchScores(c.scores, _query.text);
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: TextField(
                          controller: _query,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(color: GameColors.text),
                          decoration: InputDecoration(
                            hintText: l.songLibrarySearch,
                            hintStyle: const TextStyle(
                              color: GameColors.textDim,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: GameColors.textDim,
                            ),
                            filled: true,
                            fillColor: GameColors.panel,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: shown.isEmpty
                            ? _Message(l.songLibraryNoMatch(_query.text))
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  24,
                                ),
                                itemCount: shown.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, i) => _ScoreRow(
                                  score: shown[i],
                                  onPlay: () => widget.onPlay(shown[i]),
                                  onDelete: () => _confirmDelete(shown[i]),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.score,
    required this.onPlay,
    required this.onDelete,
  });

  final CustomScore score;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return GamePanel(
      maxWidth: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  score.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GameColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  score.composer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GameColors.textDim,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${l.scoreBars(score.bars)}  ·  ${l.scoreTimeSignature(score.timeSignature)}',
                  style: const TextStyle(
                    color: GameColors.textDim,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          GameButton(
            label: l.scorePractice,
            onTap: onPlay,
            minWidth: 110,
            height: 40,
            fontSize: 14,
          ),
          IconButton(
            tooltip: l.scoreDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: GameColors.text,
            ),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: GameColors.textDim, fontSize: 16),
        ),
      ),
    );
  }
}
