import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ui/game/game_theme.dart';
import '../ui/game/game_widgets.dart';
import 'custom_score.dart';
import 'custom_score_controller.dart';
import 'game_dialog.dart';

/// The imported scores on this device: search, practice, import and delete
/// (docs/specs/score-import-and-page-view.md 3.1).
class SongLibraryPage extends StatefulWidget {
  const SongLibraryPage({
    super.key,
    required this.controller,
    required this.onPlay,
    required this.onImport,
  });

  final CustomScoreController controller;
  final ValueChanged<CustomScore> onPlay;

  /// Opens the file picker; the host shows the result.
  final VoidCallback onImport;

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
    final ok = await showGameDialog<bool>(
      context,
      maxWidth: 400,
      builder: (ctx) => _DeleteCard(
        title: score.title,
        onCancel: () => Navigator.of(ctx).pop(false),
        onDelete: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (ok == true) await widget.controller.remove(score.id);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: GameColors.bgDeep,
      body: MenuBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                children: [
                  _Header(
                    title: l.songLibrary,
                    importLabel: l.importScore,
                    onBack: () => Navigator.of(context).maybePop(),
                    onImport: widget.onImport,
                  ),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) => _body(context, l),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      l.scoreRightsNotice,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: GameColors.textDim,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l) {
    final c = widget.controller;
    if (!c.loaded) {
      return const Center(
        child: CircularProgressIndicator(color: GameColors.cyan),
      );
    }
    if (c.scores.isEmpty) {
      return _Empty(
        message: l.songLibraryEmpty,
        importLabel: l.importScore,
        onImport: widget.onImport,
      );
    }
    final shown = searchScores(c.scores, _query.text);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: GameColors.text),
            cursorColor: GameColors.cyan,
            decoration: InputDecoration(
              hintText: l.songLibrarySearch,
              hintStyle: const TextStyle(color: GameColors.textDim),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: GameColors.textDim,
              ),
              filled: true,
              fillColor: GameColors.panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: GameColors.panelEdge),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: GameColors.panelEdge),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: GameColors.cyan, width: 2),
              ),
            ),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? _Message(l.songLibraryNoMatch(_query.text.trim()))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ScoreRow(
                    key: ValueKey(shown[i].id),
                    score: shown[i],
                    onPlay: () => widget.onPlay(shown[i]),
                    onDelete: () => _confirmDelete(shown[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.importLabel,
    required this.onBack,
    required this.onImport,
  });

  final String title;
  final String importLabel;
  final VoidCallback onBack;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          GameRoundButton(
            icon: Icons.arrow_back_rounded,
            onTap: onBack,
            size: 46,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          const SizedBox(width: 12),
          Expanded(
            // Long titles (Portuguese, German) shrink instead of ending in "...".
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: GameText(title, size: 22, align: TextAlign.start),
            ),
          ),
          const SizedBox(width: 8),
          GameRoundButton(
            icon: Icons.upload_file_rounded,
            onTap: onImport,
            tone: GameTone.gold,
            size: 46,
            tooltip: importLabel,
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    super.key,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: GameColors.textDim,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GameButton(
            label: l.scorePractice,
            onTap: onPlay,
            minWidth: 96,
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

class _DeleteCard extends StatelessWidget {
  const _DeleteCard({
    required this.title,
    required this.onCancel,
    required this.onDelete,
  });

  final String title;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: GameColors.text,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l.scoreDeleteConfirm,
          textAlign: TextAlign.center,
          style: const TextStyle(color: GameColors.textDim, fontSize: 15),
        ),
        const SizedBox(height: 18),
        Center(
          child: GameButton(
            label: l.scoreDelete,
            icon: Icons.delete_outline_rounded,
            tone: GameTone.red,
            onTap: onDelete,
          ),
        ),
        TextButton(
          onPressed: onCancel,
          child: Text(
            l.cancel,
            style: const TextStyle(
              color: GameColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.message,
    required this.importLabel,
    required this.onImport,
  });

  final String message;
  final String importLabel;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.library_music_rounded,
              size: 56,
              color: GameColors.textDim,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: GameColors.textDim, fontSize: 16),
            ),
            const SizedBox(height: 20),
            GameButton(
              label: importLabel,
              icon: Icons.upload_file_rounded,
              onTap: onImport,
            ),
          ],
        ),
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
