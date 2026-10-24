import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// True when the app runs in the frameless Windows window and must draw its
/// own caption buttons (see windows/runner/flutter_window.cpp).
bool get usesCustomTitleBar =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Method channel implemented by the Windows runner.
const windowChannel = MethodChannel('easy_piano/window');

/// Height of the caption-button strip, in logical pixels.
const double kCaptionHeight = 36;

/// Width of one caption button.
const double kCaptionButtonWidth = 46;

/// Total width taken by the caption buttons. Screens that reach the top-right
/// corner add this much end padding so their content stays clear of them.
const double kCaptionWidth = kCaptionButtonWidth * 3;

/// Minimize / maximize / close buttons pinned to the top-right corner.
///
/// Lives above the Navigator (via MaterialApp.builder) and therefore must not
/// use widgets that need an Overlay (e.g. Tooltip).
class WindowControls extends StatefulWidget {
  const WindowControls({super.key, this.channel = windowChannel});

  /// Overridable for widget tests.
  final MethodChannel channel;

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    _refreshMaximized();
  }

  Future<void> _refreshMaximized() async {
    try {
      final value = await widget.channel.invokeMethod<bool>('isMaximized');
      if (mounted) setState(() => _maximized = value ?? false);
    } on MissingPluginException {
      // Not running in the Windows runner (e.g. tests): keep defaults.
    }
  }

  Future<void> _call(String method) async {
    try {
      await widget.channel.invokeMethod<void>(method);
    } on MissingPluginException {
      return;
    }
    if (method == 'toggleMaximize') await _refreshMaximized();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kCaptionHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CaptionButton(
            key: const Key('window-minimize'),
            icon: Icons.remove,
            label: 'Minimize',
            onPressed: () => _call('minimize'),
          ),
          _CaptionButton(
            key: const Key('window-maximize'),
            icon: _maximized ? Icons.filter_none : Icons.crop_square,
            label: _maximized ? 'Restore' : 'Maximize',
            onPressed: () => _call('toggleMaximize'),
          ),
          _CaptionButton(
            key: const Key('window-close'),
            icon: Icons.close,
            label: 'Close',
            hoverColor: const Color(0xFFE81123),
            onPressed: () => _call('close'),
          ),
        ],
      ),
    );
  }
}

/// Makes [child] drag the window (and double-click to maximize). Only the
/// pan / double-tap gestures are claimed; taps still reach [child].
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({
    super.key,
    required this.child,
    this.channel = windowChannel,
  });

  final Widget child;
  final MethodChannel channel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => channel.invokeMethod<void>('startDrag'),
      onDoubleTap: () => channel.invokeMethod<void>('toggleMaximize'),
      child: child,
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.hoverColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? hoverColor;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isClose = widget.hoverColor != null;
    final background = _hover
        ? (widget.hoverColor ?? Colors.white.withValues(alpha: 0.08))
        : Colors.transparent;
    // The app is always dark: fixed light glyphs, not onSurface (which is dark here).
    final foreground = _hover && isClose ? Colors.white : Colors.white70;

    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: kCaptionButtonWidth,
            height: kCaptionHeight,
            color: background,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 16, color: foreground),
          ),
        ),
      ),
    );
  }
}
