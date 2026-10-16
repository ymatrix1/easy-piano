import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'game_theme.dart';

/// Display text. Playful skin: heavy, dark outline and hard drop shadow.
/// Classic skin: semibold with a soft shadow.
class GameText extends StatelessWidget {
  const GameText(
    this.text, {
    super.key,
    this.size = 24,
    this.color = Colors.white,
    this.stroke,
    this.align = TextAlign.center,
  });

  final String text;
  final double size;
  final Color color;

  /// Outline width (playful only); defaults to about 1/8 of the font size.
  final double? stroke;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    if (!skin.textStroke) {
      return Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          letterSpacing: size > 20 ? 0.3 : 0.6,
          height: 1.15,
          color: color,
          shadows: const [
            Shadow(color: Colors.black45, offset: Offset(0, 1), blurRadius: 3),
          ],
        ),
      );
    }
    final w = stroke ?? (size / 8).clamp(2.0, 5.0);
    final base = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.5,
      height: 1.1,
    );
    return Stack(
      children: [
        Text(
          text,
          textAlign: align,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = w * 2
              ..strokeJoin = StrokeJoin.round
              ..color = skin.outline,
            shadows: [
              Shadow(color: Colors.black38, offset: Offset(0, w * 0.9)),
            ],
          ),
        ),
        Text(
          text,
          textAlign: align,
          style: base.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Press feedback shared by the buttons: the face sinks onto its lip and
/// shrinks, then springs back (elastic in the playful skin).
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.builder});

  final VoidCallback? onTap;
  final Widget Function(double press) builder;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 320),
  );
  bool _hover = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final playful = GameSkin.of(context).playful;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _c.forward() : null,
        onTapUp: enabled ? (_) => _c.reverse() : null,
        onTapCancel: enabled ? _c.reverse : null,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.status == AnimationStatus.reverse
                ? (playful ? Curves.elasticIn : Curves.easeIn).transform(
                    _c.value,
                  )
                : _c.value;
            // Hover lifts the classic buttons slightly.
            final lift = enabled && _hover && !playful ? 0.08 : 0.0;
            return Opacity(
              opacity: enabled || playful ? 1 : 0.6,
              child: widget.builder(t - lift),
            );
          },
        ),
      ),
    );
  }
}

BoxDecoration _faceDecoration(
  GameSkin skin,
  ToneColors c,
  BorderRadius radius, {
  BoxShape shape = BoxShape.rectangle,
}) {
  return BoxDecoration(
    shape: shape,
    borderRadius: shape == BoxShape.circle ? null : radius,
    border: Border.all(color: skin.outline, width: skin.outlineWidth),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(c.face, Colors.white, skin.playful ? 0.35 : 0.12)!,
        c.face,
      ],
    ),
  );
}

/// Beveled button with a label.
class GameButton extends StatelessWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onTap,
    this.tone = GameTone.gold,
    this.icon,
    this.fontSize = 20,
    this.minWidth = 150,
  });

  final String label;
  final VoidCallback? onTap;
  final GameTone tone;
  final IconData? icon;
  final double fontSize;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    final c = skin.tone(onTap == null ? GameTone.grey : tone);
    final radius = BorderRadius.circular(skin.radius);
    final lip = skin.lip;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: _Pressable(
        onTap: onTap,
        builder: (p) => Transform.scale(
          scale: 1 - (skin.playful ? 0.06 : 0.03) * p,
          child: Padding(
            padding: EdgeInsets.only(top: lip * p.clamp(0.0, 1.0)),
            child: Container(
              constraints: BoxConstraints(minWidth: minWidth),
              decoration: BoxDecoration(
                borderRadius: radius,
                color: c.lip,
                border: skin.playful
                    ? Border.all(color: skin.outline, width: skin.outlineWidth)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: skin.playful ? 8 : 12,
                    offset: Offset(0, skin.playful ? 6 : 4),
                  ),
                ],
              ),
              padding: EdgeInsets.only(bottom: lip * (1 - p.clamp(0.0, 1.0))),
              child: DecoratedBox(
                decoration: _faceDecoration(skin, c, radius),
                child: _Gloss(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: skin.playful ? 10 : 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          _SkinIcon(icon!, size: fontSize * 1.15),
                          const SizedBox(width: 8),
                        ],
                        GameText(
                          skin.playful ? label : label.toUpperCase(),
                          size: skin.playful ? fontSize : fontSize * 0.8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon-only version of [GameButton].
class GameRoundButton extends StatelessWidget {
  const GameRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tone = GameTone.blue,
    this.size = 56,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final GameTone tone;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    final c = skin.tone(onTap == null ? GameTone.grey : tone);
    final lip = skin.lip;
    final button = Semantics(
      button: true,
      enabled: onTap != null,
      label: tooltip,
      child: _Pressable(
        onTap: onTap,
        builder: (p) => SizedBox(
          width: size,
          height: size + lip,
          child: Transform.scale(
            scale: 1 - (skin.playful ? 0.08 : 0.04) * p,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: size,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.lip,
                      border: Border.all(
                        color: skin.outline,
                        width: skin.outlineWidth,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 4,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: lip * p.clamp(-1.0, 1.0),
                  height: size,
                  child: DecoratedBox(
                    decoration: _faceDecoration(
                      skin,
                      c,
                      BorderRadius.zero,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Stack(
                        children: [
                          // Soft elliptical highlight on the upper half.
                          Positioned(
                            top: size * 0.07,
                            left: size * 0.2,
                            right: size * 0.2,
                            height: size * 0.34,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.all(
                                  Radius.elliptical(size * 0.3, size * 0.17),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(
                                      alpha: skin.playful ? 0.45 : 0.14,
                                    ),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Center(
                            child: _SkinIcon(
                              icon,
                              size: size * (skin.playful ? 0.5 : 0.46),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Top shine over a button face (playful skin only).
class _Gloss extends StatelessWidget {
  const _Gloss({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!GameSkin.of(context).playful) return child;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 6,
          right: 6,
          top: 3,
          height: 10,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Icon; outlined with a drop shadow in the playful skin.
class _SkinIcon extends StatelessWidget {
  const _SkinIcon(this.icon, {required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    if (!skin.playful) {
      return Icon(
        icon,
        size: size,
        color: Colors.white,
        shadows: const [Shadow(color: Colors.black38, blurRadius: 3)],
      );
    }
    final o = (size / 14).clamp(1.5, 3.0);
    return SizedBox(
      width: size + o * 2,
      height: size + o * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final d in const [
            Offset(-1, 0),
            Offset(1, 0),
            Offset(0, -1),
            Offset(0, 1),
            Offset(-0.7, -0.7),
            Offset(0.7, 0.7),
            Offset(-0.7, 0.7),
            Offset(0.7, -0.7),
            Offset(0, 1.8),
          ])
            Transform.translate(
              offset: d * o,
              child: Icon(icon, size: size, color: skin.outline),
            ),
          Icon(icon, size: size, color: Colors.white),
        ],
      ),
    );
  }
}

/// Card for dialogs and info. Playful: parchment in a wood frame. Classic:
/// dark glass card with a thin brass edge.
class GamePanel extends StatelessWidget {
  const GamePanel({
    super.key,
    required this.child,
    this.title,
    this.maxWidth = 560,
  });

  final Widget child;
  final String? title;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    final Widget panel;
    if (skin.playful) {
      panel = Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: skin.outline,
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(23),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [skin.panelFrame, skin.tone(GameTone.wood).lip],
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: skin.panelFill,
              border: Border.all(color: skin.outline, width: 2.5),
            ),
            padding: EdgeInsets.fromLTRB(24, title == null ? 22 : 40, 24, 22),
            child: child,
          ),
        ),
      );
    } else {
      panel = Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: skin.panelFill,
          border: Border.all(color: skin.panelFrame),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(28, title == null ? 24 : 40, 28, 24),
        child: child,
      );
    }
    if (title == null) return panel;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(padding: const EdgeInsets.only(top: 22), child: panel),
        GameRibbon(title!),
      ],
    );
  }
}

/// Title plaque. Playful: banner with folded tails. Classic: slim plaque
/// with a brass border.
class GameRibbon extends StatelessWidget {
  const GameRibbon(
    this.text, {
    super.key,
    this.tone = GameTone.red,
    this.fontSize = 26,
  });

  final String text;
  final GameTone tone;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    if (!skin.playful) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
        decoration: BoxDecoration(
          color: skin.bgTop,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: skin.accent, width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: GameText(text, size: fontSize * 0.8, color: skin.accentLight),
      );
    }
    return CustomPaint(
      painter: _RibbonPainter(skin.tone(tone), skin.outline),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 10),
        child: GameText(text, size: fontSize),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.c, this.outlineColor);

  final ToneColors c;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final outline = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    final tailPaint = Paint()..color = c.lip;
    for (final s in [-1.0, 1.0]) {
      final x0 = s < 0 ? 18.0 : w - 18.0;
      final x1 = s < 0 ? -8.0 : w + 8.0;
      final tail = Path()
        ..moveTo(x0, h * 0.25)
        ..lineTo(x1, h * 0.35)
        ..lineTo(x1 + s * -10, h * 0.72)
        ..lineTo(x1, h * 1.1)
        ..lineTo(x0, h * 1.0)
        ..close();
      canvas.drawPath(tail, tailPaint);
      canvas.drawPath(tail, outline);
    }
    final band = RRect.fromRectAndRadius(
      Rect.fromLTWH(10, 0, w - 20, h * 0.92),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(c.face, Colors.white, 0.25)!, c.face, c.lip],
          stops: const [0, 0.6, 1],
        ).createShader(band.outerRect),
    );
    canvas.drawRRect(band, outline);
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.c != c;
}

/// Mixin for one-shot entrance animations that start after a delay.
mixin _Entrance<T extends StatefulWidget> on State<T>, TickerProvider {
  late final AnimationController entrance = AnimationController(
    vsync: this,
    duration: entranceDuration,
  );
  bool _started = false;

  Duration get entranceDuration;
  Duration get entranceDelay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      entrance.value = 1;
    } else {
      Future.delayed(entranceDelay, () {
        if (mounted) entrance.forward();
      });
    }
  }

  @override
  void dispose() {
    entrance.dispose();
    super.dispose();
  }
}

/// Entrance: scales up (overshoot in the playful skin) and fades in.
class PopIn extends StatefulWidget {
  const PopIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.from = 0.4,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double from;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn>
    with SingleTickerProviderStateMixin, _Entrance {
  @override
  Duration get entranceDuration => widget.duration;
  @override
  Duration get entranceDelay => widget.delay;

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    // Classic: subtle zoom, no bounce.
    final from = skin.playful ? widget.from : math.max(widget.from, 0.92);
    return AnimatedBuilder(
      animation: entrance,
      child: widget.child,
      builder: (context, child) {
        final t = skin.enterCurve.transform(entrance.value);
        return Opacity(
          opacity: Curves.easeOut.transform(entrance.value),
          child: Transform.scale(scale: from + (1 - from) * t, child: child),
        );
      },
    );
  }
}

/// Entrance: slides in from [offset] (logical pixels) and fades in.
class SlideIn extends StatefulWidget {
  const SlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 40),
  });

  final Widget child;
  final Duration delay;
  final Offset offset;

  @override
  State<SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<SlideIn>
    with SingleTickerProviderStateMixin, _Entrance {
  @override
  Duration get entranceDuration => const Duration(milliseconds: 420);
  @override
  Duration get entranceDelay => widget.delay;

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    final offset = skin.playful ? widget.offset : widget.offset * 0.5;
    return AnimatedBuilder(
      animation: entrance,
      child: widget.child,
      builder: (context, child) {
        final t = skin.enterCurve.transform(entrance.value);
        return Opacity(
          opacity: entrance.value,
          child: Transform.translate(offset: offset * (1 - t), child: child),
        );
      },
    );
  }
}

/// Endless gentle float (playful) or soft glow pulse (classic) to mark the
/// next thing to do.
class Bob extends StatefulWidget {
  const Bob({super.key, required this.child, this.amplitude = 6});

  final Widget child;
  final double amplitude;

  @override
  State<Bob> createState() => _BobState();
}

class _BobState extends State<Bob> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final s = math.sin(_c.value * 2 * math.pi);
        if (skin.playful) {
          return Transform.translate(
            offset: Offset(0, s * widget.amplitude),
            child: child,
          );
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: skin.accent.withValues(alpha: 0.25 + 0.2 * s),
                blurRadius: 18 + 8 * s,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// Number that counts up from 0 to [value].
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    this.format,
    this.size = 22,
    this.delay = Duration.zero,
  });

  final double value;
  final String Function(double v)? format;
  final double size;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final fmt = format ?? (v) => v.round().toString();
    if (reduceMotion(context)) return GameText(fmt(value), size: size);
    return _Delayed(
      delay: delay,
      builder: (go) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: go ? value : 0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => GameText(fmt(v), size: size),
      ),
    );
  }
}

class _Delayed extends StatefulWidget {
  const _Delayed({required this.delay, required this.builder});

  final Duration delay;
  final Widget Function(bool go) builder;

  @override
  State<_Delayed> createState() => _DelayedState();
}

class _DelayedState extends State<_Delayed> {
  bool _go = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _go = true);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(_go);
}

/// A five-point star path inside [rect].
Path starPath(Rect rect, {double inner = 0.48}) {
  final c = rect.center;
  final r = rect.shortestSide / 2;
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final rr = i.isEven ? r : r * inner;
    final a = -math.pi / 2 + i * math.pi / 5;
    final p = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

/// Star filled from the left by [fill] (0–1), drawn in the skin's style.
class GameStar extends StatelessWidget {
  const GameStar({super.key, required this.fill, this.size = 64});

  final double fill;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _StarPainter(fill, GameSkin.of(context)),
  );
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.fill, this.skin);

  final double fill;
  final GameSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(size.width * 0.06);
    final playful = skin.playful;
    final path = starPath(rect, inner: playful ? 0.48 : 0.42);
    final stroke = size.width * (playful ? 0.07 : 0.025);
    if (playful) {
      canvas.drawPath(
        path.shift(Offset(0, stroke * 0.9)),
        Paint()..color = Colors.black38,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = playful ? const Color(0x55000000) : const Color(0x22FFFFFF),
    );
    if (fill > 0) {
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(0, 0, size.width * fill.clamp(0.0, 1.0), size.height),
      );
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [skin.accentLight, skin.accent, skin.accentDark],
            stops: const [0, 0.55, 1],
          ).createShader(rect),
      );
      if (playful) {
        canvas.drawPath(
          starPath(
            rect.deflate(rect.width * 0.22),
            inner: 0.5,
          ).shift(Offset(-rect.width * 0.04, -rect.height * 0.06)),
          Paint()..color = Colors.white.withValues(alpha: 0.28),
        );
      }
      canvas.restore();
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = playful
            ? skin.outline
            : (fill > 0 ? skin.accentLight : const Color(0x55FFFFFF))
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.fill != fill || old.skin != skin;
}

/// Three stars that appear one after another, with a burst on each filled
/// star. Playful: the middle star sits higher and bigger, stars tilt.
class StarRow extends StatelessWidget {
  const StarRow({
    super.key,
    required this.stars,
    this.size = 64,
    this.delay = Duration.zero,
  });

  /// Continuous star value 0–3 (e.g. 2.5 = two and a half stars).
  final double stars;
  final double size;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final playful = GameSkin.of(context).playful;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: playful && i == 1 ? size * 0.25 : 0,
            ),
            child: _StarSlot(
              fill: (stars - i).clamp(0.0, 1.0),
              size: playful && i == 1 ? size * 1.2 : size,
              delay: delay + Duration(milliseconds: 220 * i),
              tilt: playful ? (i - 1) * 0.18 : 0,
            ),
          ),
      ],
    );
  }
}

class _StarSlot extends StatefulWidget {
  const _StarSlot({
    required this.fill,
    required this.size,
    required this.delay,
    required this.tilt,
  });

  final double fill;
  final double size;
  final Duration delay;
  final double tilt;

  @override
  State<_StarSlot> createState() => _StarSlotState();
}

class _StarSlotState extends State<_StarSlot>
    with SingleTickerProviderStateMixin, _Entrance {
  @override
  Duration get entranceDuration => const Duration(milliseconds: 900);
  @override
  Duration get entranceDelay => widget.delay;

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final playful = GameSkin.of(context).playful;
    return SizedBox(
      width: s * 1.25,
      height: s * 1.25,
      child: AnimatedBuilder(
        animation: entrance,
        builder: (context, _) {
          final v = (entrance.value / 0.7).clamp(0.0, 1.0);
          final pop = playful
              ? Curves.elasticOut.transform(v)
              : 0.7 + 0.3 * Curves.easeOutCubic.transform(v);
          final burst = ((entrance.value - 0.15) / 0.85).clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: widget.tilt,
                child: GameStar(fill: 0, size: s),
              ),
              if (widget.fill > 0 && burst > 0 && burst < 1)
                CustomPaint(
                  size: Size.square(s * 1.25),
                  painter: _SparklePainter(burst, GameSkin.of(context)),
                ),
              if (widget.fill > 0)
                Opacity(
                  opacity: playful ? 1 : v,
                  child: Transform.rotate(
                    angle: widget.tilt + (playful ? (1 - pop) * 0.8 : 0),
                    child: Transform.scale(
                      scale: pop,
                      child: GameStar(fill: widget.fill, size: s),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.t, this.skin);

  final double t;
  final GameSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final alpha = 1 - t;
    if (!skin.playful) {
      // Classic: one soft expanding ring of light.
      canvas.drawCircle(
        c,
        size.width * (0.3 + 0.25 * Curves.easeOut.transform(t)),
        Paint()
          ..color = skin.accentLight.withValues(alpha: alpha * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      return;
    }
    final r = size.width * (0.3 + 0.45 * Curves.easeOut.transform(t));
    for (var i = 0; i < 10; i++) {
      final a = i * math.pi / 5 + 0.3;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      final dot = size.width * 0.05 * (1 - t * 0.6) * (i.isEven ? 1 : 0.7);
      canvas.drawPath(
        starPath(Rect.fromCircle(center: p, radius: dot * 1.6), inner: 0.4),
        Paint()
          ..color = (i.isEven ? skin.accentLight : Colors.white).withValues(
            alpha: alpha,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}

/// Pill showing a counter with a star icon (e.g. total stars).
class StarCounter extends StatelessWidget {
  const StarCounter({super.key, required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 6, right: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: skin.chipFill,
        border: Border.all(
          color: skin.playful ? skin.outline : skin.panelFrame,
          width: skin.playful ? 3 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GameStar(fill: 1, size: skin.playful ? 40 : 26),
          const SizedBox(width: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => GameText('${v.round()}', size: 20),
          ),
        ],
      ),
    );
  }
}

/// Menu backdrop. Playful: sky with drifting clouds and hills. Classic: deep
/// blue with a soft spotlight and slowly drifting specks of light.
class MenuBackground extends StatefulWidget {
  const MenuBackground({super.key, required this.child});

  final Widget child;

  @override
  State<MenuBackground> createState() => _MenuBackgroundState();
}

class _MenuBackgroundState extends State<MenuBackground>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = GameSkin.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: skin.playful
                  ? _SkyPainter(_c, skin)
                  : _StagePainter(_c, skin),
            ),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter(this.anim, this.skin) : super(repaint: anim);

  final Animation<double> anim;
  final GameSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [skin.bgTop, skin.bgBottom],
        ).createShader(rect),
    );
    // Spotlight from the top.
    final spot = Offset(size.width * 0.5, -size.height * 0.1);
    final r = size.longestSide * 0.8;
    canvas.drawCircle(
      spot,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            skin.accent.withValues(alpha: 0.12),
            skin.accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: spot, radius: r)),
    );
    // Drifting specks (deterministic).
    final rnd = math.Random(7);
    for (var i = 0; i < 40; i++) {
      final x = rnd.nextDouble();
      final y0 = rnd.nextDouble();
      final speed = 0.3 + rnd.nextDouble();
      final y = (y0 - anim.value * speed) % 1.0;
      final a = 0.05 + 0.12 * rnd.nextDouble();
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        0.8 + rnd.nextDouble() * 1.6,
        Paint()..color = skin.accentLight.withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(_StagePainter old) => old.skin != skin;
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.anim, this.skin) : super(repaint: anim);

  final Animation<double> anim;
  final GameSkin skin;

  static const _grass = Color(0xFF7BD148);
  static const _grassDark = Color(0xFF4E9A2A);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [skin.bgTop, skin.bgBottom],
        ).createShader(rect),
    );
    final sun = Offset(size.width * 0.85, size.height * 0.08);
    final sr = size.shortestSide * 0.35;
    canvas.drawCircle(
      sun,
      sr,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: sun, radius: sr)),
    );
    const clouds = [
      (0.10, 0.12, 1.0, 1.0),
      (0.55, 0.22, 0.7, 1.6),
      (0.30, 0.40, 0.55, 2.2),
      (0.80, 0.50, 0.85, 1.3),
      (0.05, 0.65, 0.6, 1.9),
    ];
    for (final (x, y, scale, speed) in clouds) {
      final w = 180.0 * scale;
      final span = size.width + w * 2;
      final cx = ((x * span + anim.value * span * speed) % span) - w;
      _cloud(canvas, Offset(cx, y * size.height), scale);
    }
    final h = size.height;
    _hill(canvas, size, h * 0.86, 0.9, _grassDark);
    _hill(canvas, size, h * 0.91, 1.4, _grass);
  }

  static const _puffs = [
    (0.0, 10.0, 28.0),
    (34.0, -6.0, 38.0),
    (76.0, 4.0, 32.0),
    (106.0, 14.0, 22.0),
  ];

  void _cloud(Canvas canvas, Offset o, double s) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.92);
    final shade = Paint()..color = const Color(0x33215A8F);
    for (final (dx, dy, r) in _puffs) {
      canvas.drawCircle(o + Offset(dx, dy + 8) * s, r * s, shade);
    }
    for (final (dx, dy, r) in _puffs) {
      canvas.drawCircle(o + Offset(dx, dy) * s, r * s, paint);
    }
  }

  void _hill(Canvas canvas, Size size, double y, double freq, Color color) {
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= size.width; x += 8) {
      path.lineTo(
        x,
        y + math.sin(x / size.width * math.pi * 2 * freq + freq) * 18,
      );
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = skin.outline.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.skin != skin;
}

/// Result backdrop: radial glow; the playful skin adds turning light rays.
class ResultBackground extends StatefulWidget {
  const ResultBackground({super.key, required this.child});

  final Widget child;

  @override
  State<ResultBackground> createState() => _ResultBackgroundState();
}

class _ResultBackgroundState extends State<ResultBackground>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _RaysPainter(_c, GameSkin.of(context))),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _RaysPainter extends CustomPainter {
  _RaysPainter(this.anim, this.skin) : super(repaint: anim);

  final Animation<double> anim;
  final GameSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final glow = skin.playful
        ? const Color(0xFF6A4FD8)
        : Color.lerp(skin.resultTop, skin.accent, 0.18)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.1,
          colors: [glow, skin.resultTop, skin.resultBottom],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
    if (!skin.playful) return;
    final c = Offset(size.width / 2, size.height * 0.35);
    final r = size.longestSide;
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    const n = 14;
    for (var i = 0; i < n; i++) {
      final a = anim.value * 2 * math.pi + i * 2 * math.pi / n;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r)
        ..lineTo(c.dx + math.cos(a + 0.18) * r, c.dy + math.sin(a + 0.18) * r)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.skin != skin;
}
