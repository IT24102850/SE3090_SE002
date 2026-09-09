import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// A spaced-caps label stacked over a filled, rounded text field — the input
/// pattern the whole app uses.
///
/// A [TextFormField] rather than a plain [TextField] so callers can drop it
/// into a [Form] and get validation for free; everything else is styling that
/// would otherwise be copy-pasted at every field.
class NeonInputField extends StatefulWidget {
  const NeonInputField({
    super.key,
    this.label,
    this.hintText,
    this.icon,
    this.controller,
    this.initialValue,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onFieldSubmitted,
    this.onChanged,
    this.obscurable = false,
    this.autofillHints,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
    this.clearable = false,
    this.suffix,
    this.helperText,
  });

  /// Rendered uppercase — passing "Email" and "EMAIL" look the same. Omit for
  /// a bare field with no label above it.
  final String? label;

  final String? hintText;
  final IconData? icon;
  final TextEditingController? controller;
  final String? initialValue;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;
  final void Function(String)? onChanged;

  /// Password behaviour: masks the input and adds an eye toggle.
  final bool obscurable;

  final Iterable<String>? autofillHints;
  final int? maxLines;
  final int? minLines;
  final bool enabled;

  /// Read-only fields still look enabled — used for pickers that open a sheet
  /// on tap rather than accepting typed input.
  final bool readOnly;
  final VoidCallback? onTap;

  /// Shows an X that empties the field once it has content.
  final bool clearable;

  /// Custom trailing widget. Ignored when [obscurable] or [clearable] applies.
  final Widget? suffix;

  final String? helperText;

  @override
  State<NeonInputField> createState() => _NeonInputFieldState();
}

class _NeonInputFieldState extends State<NeonInputField> {
  late bool _obscured = widget.obscurable;

  /// Only created when the caller didn't supply one, so a caller-owned
  /// controller is never disposed out from under them.
  TextEditingController? _ownController;

  TextEditingController? get _controller => widget.controller ?? _ownController;

  @override
  void initState() {
    super.initState();
    if (widget.clearable && widget.controller == null) {
      _ownController = TextEditingController(text: widget.initialValue);
    }
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  OutlineInputBorder _border(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: BorderSide(color: color, width: width),
      );

  Widget? _buildSuffix() {
    if (widget.obscurable) {
      return IconButton(
        onPressed: () => setState(() => _obscured = !_obscured),
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: AppColors.iconSecondary,
          size: 20,
        ),
        tooltip: _obscured ? 'Show password' : 'Hide password',
      );
    }
    if (widget.clearable) {
      final controller = _controller;
      if (controller == null) return widget.suffix;
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => value.text.isEmpty
            ? (widget.suffix ?? const SizedBox.shrink())
            : IconButton(
                onPressed: () {
                  controller.clear();
                  widget.onChanged?.call('');
                },
                icon: const Icon(Icons.close_rounded, color: AppColors.iconSecondary, size: 20),
                tooltip: 'Clear',
              ),
      );
    }
    return widget.suffix;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!.toUpperCase(), style: AppTextStyles.label),
          const SizedBox(height: 10),
        ],
        TextFormField(
          controller: _controller,
          initialValue: _controller == null ? widget.initialValue : null,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          validator: widget.validator,
          onFieldSubmitted: widget.onFieldSubmitted,
          onChanged: widget.onChanged,
          obscureText: _obscured,
          autofillHints: widget.autofillHints,
          maxLines: _obscured ? 1 : widget.maxLines,
          minLines: widget.minLines,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
          cursorColor: AppColors.cyan,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.inputFill,
            hintText: widget.hintText,
            hintStyle: AppTextStyles.body.copyWith(color: AppColors.textMuted),
            helperText: widget.helperText,
            helperStyle: AppTextStyles.caption,
            prefixIcon: widget.icon == null
                ? null
                : Icon(widget.icon, color: AppColors.iconSecondary, size: 20),
            suffixIcon: _buildSuffix(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            enabledBorder: _border(AppColors.inputBorder),
            disabledBorder: _border(AppColors.hairline),
            focusedBorder: _border(AppColors.cyan, width: 1.6),
            errorBorder: _border(AppColors.danger),
            focusedErrorBorder: _border(AppColors.danger, width: 1.6),
            errorStyle: AppTextStyles.caption.copyWith(color: AppColors.danger),
          ),
        ),
      ],
    );
  }
}
