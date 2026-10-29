import 'package:flutter/material.dart';

import '../ui/game/game_widgets.dart';

/// A dialog in the game look: a [GamePanel] on the dimmed screen, scrollable when the
/// window is short (phone in landscape) and never wider than the window.
Future<T?> showGameDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 460,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: SingleChildScrollView(
          child: GamePanel(
            maxWidth: maxWidth,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: builder(dialogContext),
          ),
        ),
      ),
    ),
  );
}
