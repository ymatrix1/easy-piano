import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'custom_score.dart';
import 'custom_score_controller.dart';
import 'import_results_dialog.dart';
import 'score_info.dart';
import 'score_preview.dart';
import 'score_preview_notes.dart';
import '../ui/staff/staff_note.dart';

/// Staff notes for the preview of [score]; empty when the core cannot lay them out,
/// so the preview still opens without its staff.
typedef PreviewNotes = List<StaffNote> Function(CustomScore score);

List<StaffNote> corePreviewNotes(CustomScore score) {
  try {
    final info = ScoreInfo.fromSongJson(score.songJson);
    final beatsPerBar = double.parse(info.timeSignature.split('/').first);
    final bars = info.bars < previewBars ? info.bars : previewBars;
    return previewNotesOf(
      score.songJson,
      maxBeats: bars * beatsPerBar,
      bars: bars,
    );
  } catch (_) {
    return const [];
  }
}

Future<List<XFile>> pickScoreFiles() => openFiles(
  acceptedTypeGroups: const [
    XTypeGroup(label: 'scores', extensions: scoreFileExtensions),
  ],
);

/// File picker or drop, then import, then what the player sees: the preview of one
/// new score, or a summary of what happened to each file.
class ScoreImportFlow {
  ScoreImportFlow({
    required this.controller,
    required this.onPlay,
    required this.onOpenLibrary,
    this.previewNotes = corePreviewNotes,
    this.pickFiles = pickScoreFiles,
  });

  final CustomScoreController controller;
  final ValueChanged<CustomScore> onPlay;
  final VoidCallback onOpenLibrary;
  final PreviewNotes previewNotes;
  final Future<List<XFile>> Function() pickFiles;

  Future<void> pickAndImport(BuildContext context) async {
    final files = await pickFiles();
    if (files.isEmpty || !context.mounted) return;
    await importFiles(context, files);
  }

  Future<void> importFiles(BuildContext context, List<XFile> files) async {
    if (files.isEmpty) return;
    final outcome = await controller.importFiles(files);
    if (!context.mounted) return;
    if (needsImportSummary(outcome)) {
      final open = await showImportResults(context, outcome);
      if (open) onOpenLibrary();
      return;
    }
    final score = outcome.imported.single;
    await showScorePreview(
      context,
      score,
      notes: previewNotes(score),
      onPlay: () => onPlay(score),
    );
  }
}
