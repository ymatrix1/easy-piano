import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'game_theme.dart';
import 'sfx.dart';

/// Display text: heavy, uppercase, tight, with a hard drop shadow.
class GameText extends StatelessWidget {
  const GameText(
    this.text, {
    super.key,
    this.size = 24,
    this.color = GameColors.text,
    this.align = TextAlign.center,
    this.upper = true,
    this.shadow = true,
    this.maxLines,
  });

  final String text;
  final double size;
  final Color color;
  final TextAlign align;
  final bool upper;
  final bool shadow;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final t = Text(
      upper ? text.toUpperCase() : text,
      textAlign: align,
      textHeightBehavior: const TextHeightBehavior(
        leadingDistribution: TextLeadingDistribution.even,
      ),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: displayFont,
        fontSize: size * 0.9, // Audiowide runs wide
        fontWeight: FontWeight.w400,
        letterSpacing: size >= 20 ? 0.4 : 0.8,
        height: 1.1,
        color: color,
        shadows: shadow
            ? [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  offset: Offset(0, size >= 20 ? 3 : 2),
                ),
              ]
            : null,
      ),
    );
    // Audiowide reserves accent room above capitals, so all-caps text sits
    // low in its box; nudge it up to centre the caps optically.
    return upper
        ? Transform.translate(offset: Offset(0, -size * 0.07), child: t)
        : t;
  }
}

/// Press, hover and click feedback shared by every tappable surface:
/// - hover: smooth lift ([lift] px) and the builder's `hover` flag (glow),
///   plus a soft hover tick;
/// - press: shrink and sink, springy release;
/// - click: a spark burst at the pointer and a [sound];
/// - disabled: [onDisabledTap] (e.g. a locked buzz).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.builder,
    this.semanticLabel,
    this.sound = SfxKind.tap,
    this.lift = 0,
    this.burst = true,
    this.burstColor = GameColors.yellow,
    this.onDisabledTap,
  });

  final VoidCallback? onTap;
  final Widget Function(double press, bool hover) builder;
  final String? semanticLabel;
  final SfxKind? sound;
  final double lift;
  final bool burst;
  final Color burstColor;
  final VoidCallback? onDisabledTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with TickerProviderStateMixin {
  late final _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final _hoverT = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  late final _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  Offset _burstAt = Offset.zero;
  bool _hover = false;

  @override
  void dispose() {
    _press.dispose();
    _hoverT.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _enter() {
    if (widget.onTap == null) return;
    setState(() => _hover = true);
    _hoverT.forward();
    Sfx.play(SfxKind.hover);
  }

  void _exit() {
    setState(() => _hover = false);
    _hoverT.reverse();
  }

  void _tap() {
    final s = widget.sound;
    if (s != null) Sfx.play(s);
    if (widget.burst && !reduceMotion(context)) _burst.forward(from: 0);
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => _enter(),
        onExit: (_) => _exit(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            _burstAt = d.localPosition;
            if (enabled) _press.forward();
          },
          onTapUp: enabled ? (_) => _press.reverse() : null,
          onTapCancel: enabled ? _press.reverse : null,
          onTap: enabled
              ? _tap
              : widget.onDisabledTap == null
              ? null
              : () {
                  Sfx.play(SfxKind.locked);
                  widget.onDisabledTap!();
                },
          child: AnimatedBuilder(
            animation: Listenable.merge([_press, _hoverT]),
            builder: (context, _) {
              final t = _press.status == AnimationStatus.reverse
                  ? Curves.easeOutBack.transform(_press.value)
                  : _press.value;
              final h = Curves.easeOut.transform(_hoverT.value);
              Widget child = widget.builder(t, enabled && _hover);
              if (widget.lift > 0) {
                child = Transform.translate(
                  offset: Offset(0, -widget.lift * h * (1 - t)),
                  child: child,
                );
              }
              return Stack(
                clipBehavior: Clip.none,
                fit: StackFit.passthrough,
                children: [
                  child,
                  if (widget.burst)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _burst,
                          builder: (context, _) => _burst.isAnimating
                              ? CustomPaint(
                                  painter: _BurstPainter(
                                    _burst.value,
                                    _burstAt,
                                    widget.burstColor,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Click feedback: expanding ring plus eight sparks flying out.
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.at, this.color);

  final double t;
  final Offset at;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final e = Curves.easeOutCubic.transform(t);
    final fade = (1 - t).clamp(0.0, 1.0);
    canvas.drawCircle(
      at,
      6 + 40 * e,
      Paint()
        ..color = color.withValues(alpha: 0.55 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * fade + 0.5,
    );
    final spark = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5 * fade + 0.5;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + 0.3;
      final d = Offset(math.cos(a), math.sin(a));
      final r0 = 10 + 30 * e;
      final r1 = r0 + 10 * fade;
      spark.color = (i.isEven ? color : Colors.white).withValues(alpha: fade);
      canvas.drawLine(at + d * r0, at + d * r1, spark);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// Periodic diagonal shine sweeping across [child] (idle attention cue).
class ShineSweep extends StatefulWidget {
  const ShineSweep({
    super.key,
    required this.child,
    this.shape,
    this.period = const Duration(milliseconds: 3600),
    this.opacity = 0.35,
  });

  final Widget child;

  /// Clip for the shine (defaults to the child's box).
  final ShapeBorder? shape;
  final Duration period;
  final double opacity;

  @override
  State<ShineSweep> createState() => _ShineSweepState();
}

class _ShineSweepState extends State<ShineSweep>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.period);

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
      fit: StackFit.passthrough, // keep the child's constraints (e.g. stretch)
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipPath(
              clipper: ShapeBorderClipper(
                shape: widget.shape ?? const RoundedRectangleBorder(),
              ),
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  // Sweep during the first 30% of the period, rest idle.
                  final s = (_c.value / 0.3).clamp(0.0, 1.0);
                  if (s <= 0 || s >= 1) return const SizedBox.shrink();
                  return FractionalTranslation(
                    translation: Offset(-1.2 + 2.4 * s, 0),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.skewX(-0.5),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: widget.opacity),
                              Colors.white.withValues(alpha: 0),
                            ],
                            stops: const [0.35, 0.5, 0.65],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Chamfered call-to-action button with a darker base edge and gloss band.
class GameButton extends StatelessWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onTap,
    this.tone = GameTone.gold,
    this.icon,
    this.trailingIcon,
    this.fontSize = 18,
    this.minWidth = 150,
    this.height = 50,
  });

  final String label;
  final VoidCallback? onTap;
  final GameTone tone;
  final IconData? icon;
  final IconData? trailingIcon;
  final double fontSize;
  final double minWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = onTap == null ? GameTone.grey : tone;
    final cut = height * 0.28;
    final cta = tone == GameTone.gold && onTap != null;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      sound: cta ? SfxKind.confirm : SfxKind.tap,
      lift: 3,
      builder: (p, hover) => Transform.translate(
        offset: Offset(0, 2 * p),
        child: Transform.scale(
          scale: 1 - 0.04 * p,
          child: Container(
            height: height,
            constraints: BoxConstraints(minWidth: minWidth),
            decoration: ShapeDecoration(
              shape: chamfer(cut),
              color: Color.lerp(t.bottom, Colors.black, 0.45),
              shadows: [
                BoxShadow(
                  color: (hover ? t.top : Colors.black).withValues(
                    alpha: hover ? 0.45 : 0.4,
                  ),
                  blurRadius: hover ? 18 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: EdgeInsets.only(bottom: 4 * (1 - p)),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: chamfer(cut),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    hover ? Color.lerp(t.top, Colors.white, 0.15)! : t.top,
                    t.bottom,
                  ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (cta)
                    Positioned.fill(
                      child: ShineSweep(
                        shape: chamfer(cut),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  Positioned.fill(child: _Sheen(cut)),
                  Align(
                    widthFactor: 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, color: t.label, size: fontSize * 1.25),
                            const SizedBox(width: 8),
                          ],
                          GameText(
                            label,
                            size: fontSize,
                            color: t.label,
                            shadow: t.label == Colors.white,
                          ),
                          if (trailingIcon != null) ...[
                            const SizedBox(width: 10),
                            Icon(
                              trailingIcon,
                              color: t.label,
                              size: fontSize * 1.2,
                            ),
                          ],
                        ],
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
}

/// Soft sheen over the upper half of a chamfered face (shared by buttons).
class _Sheen extends StatelessWidget {
  const _Sheen(this.cut);

  final double cut;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ClipPath(
      clipper: ShapeBorderClipper(shape: chamfer(cut)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.24),
              Colors.white.withValues(alpha: 0.06),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 0.5],
          ),
        ),
      ),
    ),
  );
}

/// Square chamfered icon button (pause, retry, close).
class GameRoundButton extends StatelessWidget {
  const GameRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tone = GameTone.wood,
    this.size = 52,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final GameTone tone;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = onTap == null ? GameTone.grey : tone;
    final cut = size * 0.24;
    final button = Pressable(
      onTap: onTap,
      semanticLabel: tooltip,
      lift: 2,
      builder: (p, hover) => Transform.translate(
        offset: Offset(0, 2 * p),
        child: Transform.scale(
          scale: 1 - 0.06 * p,
          child: Container(
            width: size,
            height: size,
            decoration: ShapeDecoration(
              shape: chamfer(cut),
              color: Color.lerp(t.bottom, Colors.black, 0.45),
              shadows: [
                BoxShadow(
                  color: (hover ? t.top : Colors.black).withValues(alpha: 0.4),
                  blurRadius: hover ? 16 : 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: EdgeInsets.only(bottom: 4 * (1 - p)),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: chamfer(cut),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    hover ? Color.lerp(t.top, Colors.white, 0.15)! : t.top,
                    t.bottom,
                  ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(child: _Sheen(cut)),
                  Icon(
                    icon,
                    size: size * 0.5,
                    color: t.label,
                    shadows: t.label == Colors.white
                        ? const [Shadow(color: Colors.black45, blurRadius: 3)]
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Dark glass panel with a chamfered frame and a top highlight line.
class GamePanel extends StatelessWidget {
  const GamePanel({
    super.key,
    required this.child,
    this.title,
    this.maxWidth = 560,
    this.padding = const EdgeInsets.fromLTRB(26, 22, 26, 24),
  });

  final Widget child;
  final String? title;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: ShapeDecoration(
        shape: chamfer(
          18,
          side: const BorderSide(color: GameColors.panelEdge, width: 1.5),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            GameColors.panelHi.withValues(alpha: 0.96),
            GameColors.panel.withValues(alpha: 0.96),
          ],
        ),
        shadows: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      padding: padding.copyWith(top: padding.top + (title == null ? 0 : 20)),
      child: child,
    );
    if (title == null) return panel;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(padding: const EdgeInsets.only(top: 20), child: panel),
        GameRibbon(title!, tone: GameTone.purple, fontSize: 20),
      ],
    );
  }
}

/// Skewed banner for titles.
class GameRibbon extends StatelessWidget {
  const GameRibbon(
    this.text, {
    super.key,
    this.tone = GameTone.purple,
    this.fontSize = 26,
  });

  final String text;
  final GameTone tone;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.skewX(-0.18),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: fontSize * 1.2,
          vertical: fontSize * 0.35,
        ),
        decoration: BoxDecoration(
          gradient: tone.gradient,
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
            bottom: BorderSide(
              color: Color.lerp(tone.bottom, Colors.black, 0.5)!,
              width: 3,
            ),
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(0.18),
          child: GameText(
            text,
            size: fontSize,
            color: tone.label,
            shadow: tone.label == Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Thin chamfered progress bar.
class GameProgressBar extends StatelessWidget {
  const GameProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.color = GameColors.yellow,
  });

  final double value;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Container(
                width: c.maxWidth * v,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 2),
                  gradient: LinearGradient(
                    colors: [Color.lerp(color, Colors.white, 0.3)!, color],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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

/// Entrance: scales up with a light overshoot and fades in.
class PopIn extends StatefulWidget {
  const PopIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 460),
    this.from = 0.85,
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
    return AnimatedBuilder(
      animation: entrance,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(entrance.value);
        return Opacity(
          opacity: Curves.easeOut.transform(entrance.value),
          child: Transform.scale(
            scale: widget.from + (1 - widget.from) * t,
            child: child,
          ),
        );
      },
    );
  }
}

/// Entrance: slides in from [offset] and fades in.
class SlideIn extends StatefulWidget {
  const SlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 24),
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
    return AnimatedBuilder(
      animation: entrance,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(entrance.value);
        return Opacity(
          opacity: entrance.value,
          child: Transform.translate(
            offset: widget.offset * (1 - t),
            child: child,
          ),
        );
      },
    );
  }
}

/// Endless glow pulse that marks the next thing to do.
class Bob extends StatefulWidget {
  const Bob({
    super.key,
    required this.child,
    this.color = GameColors.yellow,
    this.amplitude = 0,
  });

  final Widget child;
  final Color color;

  /// Optional vertical float in pixels.
  final double amplitude;

  @override
  State<Bob> createState() => _BobState();
}

class _BobState extends State<Bob> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
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
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final s = math.sin(_c.value * 2 * math.pi);
        return Transform.translate(
          offset: Offset(0, s * widget.amplitude),
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.28 + 0.18 * s),
                  blurRadius: 20 + 8 * s,
                ),
              ],
            ),
            child: child,
          ),
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
    this.color = GameColors.text,
  });

  final double value;
  final String Function(double v)? format;
  final double size;
  final Duration delay;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fmt = format ?? (v) => v.round().toString();
    if (reduceMotion(context)) {
      return GameText(fmt(value), size: size, color: color);
    }
    return _Delayed(
      delay: delay,
      builder: (go) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: go ? value : 0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => GameText(fmt(v), size: size, color: color),
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
Path starPath(Rect rect, {double inner = 0.46}) {
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

/// Gold star filled from the left by [fill] (0–1); empty part is a dark
/// socket.
class GameStar extends StatelessWidget {
  const GameStar({super.key, required this.fill, this.size = 64});

  final double fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Rounded flat star (Material star_rounded), filled from the left.
    final glow = size >= 28
        ? [
            Shadow(
              color: GameColors.gold.withValues(alpha: 0.6),
              blurRadius: size * 0.25,
            ),
          ]
        : null;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Icon(Icons.star_rounded, size: size, color: const Color(0x8C0A0830)),
          // Glow drawn unclipped (a ClipRect would cut the blur into a
          // square) and only for full stars.
          if (glow != null && fill >= 1)
            Icon(
              Icons.star_rounded,
              size: size,
              color: Colors.transparent,
              shadows: glow,
            ),
          if (fill > 0)
            ClipRect(
              clipper: _FillClipper(fill.clamp(0.0, 1.0)),
              child: Icon(
                Icons.star_rounded,
                size: size,
                color: GameColors.gold,
              ),
            ),
        ],
      ),
    );
  }
}

class _FillClipper extends CustomClipper<Rect> {
  _FillClipper(this.fill);

  final double fill;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fill, size.height);

  @override
  bool shouldReclip(_FillClipper old) => old.fill != fill;
}

/// Three stars that appear one after another, each filled star with a
/// flash ring.
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == 1 ? size * 0.2 : 0),
            child: _StarSlot(
              index: i,
              fill: (stars - i).clamp(0.0, 1.0),
              size: i == 1 ? size * 1.15 : size,
              delay: delay + Duration(milliseconds: 220 * i),
            ),
          ),
      ],
    );
  }
}

class _StarSlot extends StatefulWidget {
  const _StarSlot({
    required this.index,
    required this.fill,
    required this.size,
    required this.delay,
  });

  final int index;
  final double fill;
  final double size;
  final Duration delay;

  @override
  State<_StarSlot> createState() => _StarSlotState();
}

class _StarSlotState extends State<_StarSlot>
    with SingleTickerProviderStateMixin, _Entrance {
  @override
  Duration get entranceDuration => const Duration(milliseconds: 800);
  @override
  Duration get entranceDelay => widget.delay;

  @override
  void initState() {
    super.initState();
    // Chime as each earned star lands.
    entrance.addStatusListener((st) {
      if (st == AnimationStatus.forward && widget.fill > 0) {
        Sfx.star(widget.index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.25,
      height: s * 1.25,
      child: AnimatedBuilder(
        animation: entrance,
        builder: (context, _) {
          final v = (entrance.value / 0.6).clamp(0.0, 1.0);
          final pop = Curves.easeOutBack.transform(v);
          final flash = ((entrance.value - 0.2) / 0.8).clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              GameStar(fill: 0, size: s),
              if (widget.fill > 0 && flash > 0 && flash < 1)
                CustomPaint(
                  size: Size.square(s * 1.25),
                  painter: _FlashPainter(flash),
                ),
              if (widget.fill > 0)
                Opacity(
                  opacity: v,
                  child: Transform.scale(
                    scale: 0.4 + 0.6 * pop,
                    child: GameStar(fill: widget.fill, size: s),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FlashPainter extends CustomPainter {
  _FlashPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final e = Curves.easeOut.transform(t);
    canvas.drawCircle(
      c,
      size.width * (0.25 + 0.3 * e),
      Paint()
        ..color = GameColors.goldLight.withValues(alpha: (1 - t) * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - t) + 0.5,
    );
    // Four-point glint.
    final g = size.width * 0.5 * e;
    final glint = Paint()
      ..color = Colors.white.withValues(alpha: (1 - t) * 0.9)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c - Offset(g, 0), c + Offset(g, 0), glint);
    canvas.drawLine(c - Offset(0, g), c + Offset(0, g), glint);
  }

  @override
  bool shouldRepaint(_FlashPainter old) => old.t != t;
}

/// Currency-style pill (icon + animated number).
class StarCounter extends StatelessWidget {
  const StarCounter({super.key, required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    // Pulses when the value changes.
    return TweenAnimationBuilder<double>(
      key: ValueKey(value),
      tween: Tween(begin: value == 0 ? 1 : 1.25, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, k, child) => Transform.scale(scale: k, child: child),
      child: _pill(),
    );
  }

  Widget _pill() {
    return Container(
      height: 38,
      padding: const EdgeInsets.only(left: 6, right: 14),
      decoration: ShapeDecoration(
        shape: chamfer(
          10,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        color: Colors.black.withValues(alpha: 0.35),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GameStar(fill: 1, size: 26),
          const SizedBox(width: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => GameText('${v.round()}', size: 18),
          ),
        ],
      ),
    );
  }
}

/// Arena backdrop: violet glow over deep night, diagonal light beams and
/// slowly rising specks.
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
    duration: const Duration(seconds: 40),
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
            child: CustomPaint(painter: _ArenaPainter(_c, rays: false)),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

/// Result backdrop: arena with slowly turning light rays.
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
    duration: const Duration(seconds: 40),
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
            child: CustomPaint(painter: _ArenaPainter(_c, rays: true)),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _ArenaPainter extends CustomPainter {
  _ArenaPainter(this.anim, {required this.rays}) : super(repaint: anim);

  final Animation<double> anim;
  final bool rays;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GameColors.bgMid, GameColors.bgDeep],
        ).createShader(rect),
    );
    // Big violet glow.
    final glowC = Offset(size.width * 0.5, size.height * (rays ? 0.32 : 0.0));
    final glowR = size.longestSide * 0.75;
    canvas.drawCircle(
      glowC,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            GameColors.bgGlow.withValues(alpha: 0.85),
            GameColors.bgGlow.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: glowC, radius: glowR)),
    );
    if (rays) {
      final r = size.longestSide;
      final paint = Paint()..color = Colors.white.withValues(alpha: 0.045);
      const n = 16;
      for (var i = 0; i < n; i++) {
        final a = anim.value * 2 * math.pi + i * 2 * math.pi / n;
        canvas.drawPath(
          Path()
            ..moveTo(glowC.dx, glowC.dy)
            ..lineTo(glowC.dx + math.cos(a) * r, glowC.dy + math.sin(a) * r)
            ..lineTo(
              glowC.dx + math.cos(a + 0.16) * r,
              glowC.dy + math.sin(a + 0.16) * r,
            )
            ..close(),
          paint,
        );
      }
    } else {
      // Diagonal light beams.
      for (final (x, w, a) in const [
        (0.15, 0.10, 0.05),
        (0.42, 0.05, 0.04),
        (0.78, 0.14, 0.035),
      ]) {
        final x0 = size.width * x;
        final bw = size.width * w;
        canvas.drawPath(
          Path()
            ..moveTo(x0, 0)
            ..lineTo(x0 + bw, 0)
            ..lineTo(x0 + bw - size.height * 0.6, size.height)
            ..lineTo(x0 - size.height * 0.6, size.height)
            ..close(),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                GameColors.cyan.withValues(alpha: a),
                GameColors.cyan.withValues(alpha: 0),
              ],
            ).createShader(rect),
        );
      }
    }
    // Rising specks (deterministic).
    final rnd = math.Random(11);
    for (var i = 0; i < 46; i++) {
      final x = rnd.nextDouble();
      final y0 = rnd.nextDouble();
      final speed = 0.4 + rnd.nextDouble();
      final y = (y0 - anim.value * speed) % 1.0;
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        0.7 + rnd.nextDouble() * 1.5,
        Paint()
          ..color = (i % 3 == 0 ? GameColors.cyan : Colors.white).withValues(
            alpha: 0.06 + 0.16 * rnd.nextDouble(),
          ),
      );
    }
    // Bottom vignette.
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.7, size.width, size.height * 0.3),
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: 0.35),
              ],
            ).createShader(
              Rect.fromLTWH(
                0,
                size.height * 0.7,
                size.width,
                size.height * 0.3,
              ),
            ),
    );
  }

  @override
  bool shouldRepaint(_ArenaPainter old) => old.rays != rays;
}
