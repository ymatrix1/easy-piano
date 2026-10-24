import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// True when the app runs in the frameless Windows window and must draw its
/// own title bar (see windows/runner/flutter_window.cpp).
bool get usesCustomTitleBar =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Method channel implemented by the Windows runner.
const windowChannel = MethodChannel('easy_piano/window');

/// Height of the custom title bar, in logical pixels.
const double kTitleBarHeight = 36;

/// Slim title bar that blends into the app background (no separate bar
/// colour), with drag area, logo, title and minimize / maximize / close.
class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({super.key, this.channel = windowChannel});

  /// Overridable for widget tests.
  final MethodChannel channel;

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> {
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
    final theme = Theme.of(context);
    final title = AppLocalizations.of(context).appTitle;

    return SizedBox(
      height: kTitleBarHeight,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => _call('startDrag'),
              onDoubleTap: () => _call('toggleMaximize'),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/brand/logo.png',
                      height: 18,
                      filterQuality: FilterQuality.medium,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _CaptionButton(
            key: const Key('window-minimize'),
            icon: Icons.remove,
            tooltip: 'Minimize',
            onPressed: () => _call('minimize'),
          ),
          _CaptionButton(
            key: const Key('window-maximize'),
            icon: _maximized ? Icons.filter_none : Icons.crop_square,
            tooltip: _maximized ? 'Restore' : 'Maximize',
            onPressed: () => _call('toggleMaximize'),
          ),
          _CaptionButton(
            key: const Key('window-close'),
            icon: Icons.close,
            tooltip: 'Close',
            hoverColor: const Color(0xFFE81123),
            onPressed: () => _call('close'),
          ),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.hoverColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? hoverColor;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hoverColor =
        widget.hoverColor ?? scheme.onSurface.withValues(alpha: 0.08);
    final foreground = _hover && widget.hoverColor != null
        ? Colors.white
        : scheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: kTitleBarHeight,
            color: _hover ? hoverColor : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 16, color: foreground),
          ),
        ),
      ),
    );
  }
}
