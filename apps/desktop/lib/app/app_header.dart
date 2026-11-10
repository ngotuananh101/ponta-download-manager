import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:pdm/core/services/window_api.dart';
import 'package:pdm/shared/theme/app_tokens.dart';

const double kAppHeaderHeight = 36;
const double kWindowCaptionButtonWidth = 46;

/// The app's own title bar, drawn in Flutter.
///
/// The window carries no native decoration (the Linux runner creates it
/// undecorated; on other platforms `main` hides the title bar), so this
/// is the only title bar: brand on the left, a drag area in the middle,
/// and the window controls on the right. Ported from dev-stack's
/// AppHeader, with Material icons instead of lucide.
class AppHeader extends StatefulWidget {
  const AppHeader({super.key});

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  bool _isMaximized = false;
  ListenerId? _windowListenerId;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    // The window may not be discoverable yet when this builds on
    // Windows, so the listener is attached once it exists.
    // `whenCurrentWindow` runs the callback immediately when the
    // window is already there. In a widget test there is no window,
    // so the callback simply never runs and the header stays in its
    // restored state.
    whenCurrentWindow((window) {
      if (_disposed) return;
      final isMaximized = window.isMaximized;
      _windowListenerId = window.addListener(_onWindowEvent);
      if (mounted && isMaximized != _isMaximized) {
        setState(() => _isMaximized = isMaximized);
      } else {
        _isMaximized = isMaximized;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    final listenerId = _windowListenerId;
    if (listenerId != null) {
      currentWindow()?.removeListener(listenerId);
    }
    super.dispose();
  }

  // nativeapi reports a restore for both "no longer maximized" and
  // "no longer minimized", so the new state is read back from the
  // window rather than inferred from the event alone.
  void _onWindowEvent(WindowEvent event) {
    switch (event) {
      case WindowMaximizedEvent():
      case WindowRestoredEvent():
        final isMaximized = currentWindow()?.isMaximized ?? false;
        if (mounted && isMaximized != _isMaximized) {
          setState(() => _isMaximized = isMaximized);
        }
      default:
        break;
    }
  }

  void _handleMinimize() {
    currentWindow()?.minimize();
  }

  void _handleMaximizeToggle() {
    final window = currentWindow();
    if (window == null) return;
    if (_isMaximized) {
      window.unmaximize();
    } else {
      window.maximize();
    }
  }

  void _handleClose() {
    // `close()` asks the window's close listeners first, which is
    // where WindowService decides between hiding to the tray and
    // quitting.
    currentWindow()?.close();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: kAppHeaderHeight,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          _buildBrand(colorScheme),
          Expanded(
            child: DragToMoveArea(
              child: SizedBox(
                height: kAppHeaderHeight,
                width: double.infinity,
              ),
            ),
          ),
          _buildWindowControls(),
        ],
      ),
    );
  }

  Widget _buildBrand(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.s3,
        right: AppSpacing.s2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/icon.png',
            width: 16,
            height: 16,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.download,
              size: 16,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Text(
            'Ponta Download Manager',
            overflow: TextOverflow.ellipsis,
            style: AppTextSize.xs.textStyle(
              weight: AppFontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowControlButton(
          icon: Icons.remove,
          tooltip: 'Minimize',
          onTap: _handleMinimize,
        ),
        _WindowControlButton(
          icon: _isMaximized ? Icons.copy : Icons.crop_square,
          tooltip: _isMaximized ? 'Restore' : 'Maximize',
          iconSize: _isMaximized ? 12 : 13,
          onTap: _handleMaximizeToggle,
        ),
        _WindowControlButton(
          icon: Icons.close,
          tooltip: 'Close',
          isClose: true,
          onTap: _handleClose,
        ),
      ],
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isClose;
  final double iconSize;

  const _WindowControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
    this.iconSize = 14,
  });

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = _isHovering
        ? (widget.isClose
            ? colorScheme.error
            : colorScheme.surfaceContainerHighest)
        : Colors.transparent;
    final iconColor = _isHovering
        ? (widget.isClose ? colorScheme.onError : colorScheme.onSurface)
        : colorScheme.onSurfaceVariant;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: bgColor,
          child: InkWell(
            onTap: widget.onTap,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: SizedBox(
              width: kWindowCaptionButtonWidth,
              height: kAppHeaderHeight,
              child: Center(
                child: Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
