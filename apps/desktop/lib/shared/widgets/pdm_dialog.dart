import 'package:flutter/material.dart';
import 'package:pdm/shared/theme/app_tokens.dart';

/// The app's custom dialog shell, matching the New download design:
/// a dark rounded panel with a title and an X button on top, content
/// in the middle, and action buttons at the bottom right. Every dialog
/// in the app uses this instead of the stock [AlertDialog], so the
/// dialogs share one look and the New download dialog drops in later
/// on the same shell.
class PdmDialog extends StatelessWidget {
  const PdmDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 480,
  });

  /// The title at the top left.
  final String title;

  /// The dialog body.
  final Widget child;

  /// Buttons at the bottom right, usually [PdmDialogButton]s.
  final List<Widget> actions;

  /// Fixed panel width; the New download design is a wide dialog.
  final double width;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: AppTextSize.lg.textStyle(
                      weight: AppFontWeight.semibold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// An action button for [PdmDialog]: a 36px pill. The primary button
/// is blue with an uppercase label (the New download DOWNLOAD button);
/// the secondary button is a dark pill with its label as given.
class PdmDialogButton extends StatelessWidget {
  const PdmDialogButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
  }) : _primary = true;

  const PdmDialogButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
  }) : _primary = false;

  final String label;
  final VoidCallback? onPressed;
  final bool _primary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        backgroundColor: _primary
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
        foregroundColor: _primary
            ? colorScheme.onPrimary
            : colorScheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        textStyle: AppTextSize.sm.textStyle(
          weight: AppFontWeight.semibold,
        ),
      ),
      onPressed: onPressed,
      child: Text(_primary ? label.toUpperCase() : label),
    );
  }
}
