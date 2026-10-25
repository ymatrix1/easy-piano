import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ui/game/game_widgets.dart';
import 'custom_score.dart';

/// Score files among [files], in the order dropped.
List<XFile> supportedScoreFiles(List<XFile> files) => [
  for (final f in files)
    if (isSupportedScoreFile(f.name)) f,
];

/// Whether files can be dropped on this platform (desktop and web; phones use the
/// file picker).
bool get scoreDropSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

/// Accepts score files dropped on [child] and shows [ScoreDropOverlay] while a drag
/// hovers over the window (docs/specs/score-import-and-page-view.md 3.1).
class ScoreDropZone extends StatefulWidget {
  const ScoreDropZone({super.key, required this.child, required this.onFiles});

  final Widget child;
  final ValueChanged<List<XFile>> onFiles;

  @override
  State<ScoreDropZone> createState() => _ScoreDropZoneState();
}

class _ScoreDropZoneState extends State<ScoreDropZone> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: scoreDropSupported,
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: (details) {
        setState(() => _hovering = false);
        widget.onFiles(details.files);
      },
      child: Stack(
        children: [
          widget.child,
          ScoreDropOverlay(visible: _hovering),
        ],
      ),
    );
  }
}

/// The "Drop score file to import" panel shown during a drag.
class ScoreDropOverlay extends StatelessWidget {
  const ScoreDropOverlay({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: Colors.black54,
          child: Center(
            child: GamePanel(
              maxWidth: 420,
              child: GameText(
                AppLocalizations.of(context).scoreDropHint,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
