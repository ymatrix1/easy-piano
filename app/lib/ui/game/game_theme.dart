import 'package:flutter/material.dart';

/// Menu palette: deep night-violet arena, electric cyan, signal yellow
/// (ours; see docs/specs/visual-style.md).
abstract final class GameColors {
  static const bgDeep = Color(0xFF080726);
  static const bgMid = Color(0xFF15104F);
  static const bgGlow = Color(0xFF4422C9);
  static const panel = Color(0xFF1A1458);
  static const panelHi = Color(0xFF261D78);
  static const panelEdge = Color(0xFF4A3CC0);
  static const cyan = Color(0xFF2EE6FF);
  static const yellow = Color(0xFFFFD21F);
  static const yellowDark = Color(0xFFE09A00);
  static const gold = Color(0xFFFFC83A);
  static const goldLight = Color(0xFFFFEA9A);
  static const goldDark = Color(0xFFB86E00);
  static const ink = Color(0xFF140F3A); // text on yellow / green
  static const text = Color(0xFFFFFFFF);
  static const textDim = Color(0xFFB8B3F0);
  static const success = Color(0xFF3CE07A);
  static const danger = Color(0xFFFF4D6D);
}

/// Role of a button or card.
enum GameTone {
  /// Primary call to action (signal yellow).
  gold(Color(0xFFFFE15A), Color(0xFFFFB800), GameColors.ink),
  green(Color(0xFF5CF08F), Color(0xFF18B055), GameColors.ink),
  blue(Color(0xFF4FA8FF), Color(0xFF1D4FD6), Colors.white),
  purple(Color(0xFFB277FF), Color(0xFF5B23C9), Colors.white),
  red(Color(0xFFFF6B83), Color(0xFFC81E45), Colors.white),
  grey(Color(0xFF4A4770), Color(0xFF2A2850), Color(0xFF9C99C8)),

  /// Dark glass, for secondary actions.
  wood(Color(0xFF2E2690), Color(0xFF1A1458), Colors.white);

  const GameTone(this.top, this.bottom, this.label);
  final Color top;
  final Color bottom;
  final Color label;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [top, bottom],
  );
}

/// The signature shape: rectangle with the top-right and bottom-left corners
/// cut at 45°.
ShapeBorder chamfer(double cut, {BorderSide side = BorderSide.none}) =>
    BeveledRectangleBorder(
      side: side,
      borderRadius: BorderRadius.only(
        topRight: Radius.circular(cut),
        bottomLeft: Radius.circular(cut),
      ),
    );

/// True when the platform asks for reduced motion.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;
