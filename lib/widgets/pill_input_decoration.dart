import 'package:flutter/material.dart';

import '../theme/mono_tokens.dart';

const pillInputRadius = BorderRadius.all(Radius.circular(100));

InputDecorationThemeData searchFieldTheme(Color text, Color muted, Color error, {bool multiline = false}) {
  final outline = OutlineInputBorder(
    borderRadius: multiline ? BorderRadius.circular(18) : pillInputRadius,
    borderSide: pillOutlineFor(text),
  );
  OutlineInputBorder line(Color color, double width) => outline.copyWith(
    borderSide: BorderSide(color: color, width: width),
  );
  final label = navigationPillTypography.copyWith(color: muted);
  return InputDecorationThemeData(
    filled: false,
    isDense: true,
    border: outline,
    enabledBorder: outline,
    focusedBorder: line(text.withValues(alpha: .75), 2),
    disabledBorder: line(text.withValues(alpha: .09), 1),
    errorBorder: line(error, 1),
    focusedErrorBorder: line(error, 2),
    contentPadding: EdgeInsets.symmetric(horizontal: multiline ? 16 : 12, vertical: multiline ? 12 : 8),
    constraints: const BoxConstraints(minHeight: 42),
    hintStyle: label,
    labelStyle: label,
    floatingLabelStyle: label.copyWith(color: text),
  );
}

InputDecoration pillInputDecoration(BuildContext context, {String? hintText, Widget? prefixIcon, Widget? suffixIcon}) {
  final colors = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
  ).applyDefaults(searchFieldTheme(colors.onSurface, colors.onSurfaceVariant, colors.error));
}
