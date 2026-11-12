import 'package:flutter/material.dart';
import 'package:pdm/shared/theme/app_tokens.dart';
import 'package:pdm/shared/widgets/pdm_dialog.dart';

/// A small dialog with one text field. Returns the typed text, or
/// null when cancelled. [validate] returns an error message for an
/// invalid value, or null when it is valid; the OK button stays
/// disabled while the value is invalid or empty.
Future<String?> showTextInputDialog({
  required BuildContext context,
  required String title,
  required String label,
  required String initialValue,
  String? Function(String value)? validate,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      validate: validate,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    this.validate,
  });

  final String title;
  final String label;
  final String initialValue;
  final String? Function(String value)? validate;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _error = widget.validate?.call(_controller.text);
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    setState(() {
      _error = widget.validate?.call(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => _controller.text.isNotEmpty && _error == null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PdmDialog(
      title: widget.title,
      actions: [
        PdmDialogButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        PdmDialogButton.primary(
          label: 'OK',
          onPressed: _valid
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            style: AppTextSize.xs.textStyle(),
            decoration: InputDecoration(
              labelText: widget.label,
              labelStyle: AppTextSize.xs.textStyle(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s3,
                vertical: AppSpacing.s2,
              ),
            ),
            onSubmitted: (_) {
              if (_valid) Navigator.of(context).pop(_controller.text);
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s2),
              child: Text(
                _error!,
                style: AppTextSize.xs.textStyle(color: colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
