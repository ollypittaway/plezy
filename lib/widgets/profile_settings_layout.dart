import 'package:flutter/material.dart';

/// Use the profile page's flat rows for the settings in this subtree.
class ProfileSettingsLayout extends InheritedWidget {
  const ProfileSettingsLayout({super.key, required super.child});

  static const maxWidth = 960.0;
  static const outerInset = 8.0;
  static const contentInset = 12.0;
  static const rowPadding = EdgeInsets.symmetric(horizontal: contentInset);

  static bool applies(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProfileSettingsLayout>() != null;

  @override
  bool updateShouldNotify(ProfileSettingsLayout oldWidget) => false;
}

class SettingsColumns extends StatelessWidget {
  const SettingsColumns({super.key, required this.label, required this.detail, this.compactGap = 8});
  final Widget label;
  final Widget detail;
  final double compactGap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label,
              SizedBox(height: compactGap),
              detail,
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 2, child: label),
            const SizedBox(width: 28),
            Expanded(flex: 3, child: detail),
          ],
        );
      },
    );
  }
}

class SettingsRowText extends StatelessWidget {
  const SettingsRowText({super.key, required this.title, this.subtitle});
  final Widget title;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = DefaultTextStyle.merge(
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      child: title,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: subtitle == null
          ? label
          : SettingsColumns(
              label: label,
              compactGap: 3,
              detail: DefaultTextStyle.merge(
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                child: subtitle!,
              ),
            ),
    );
  }
}
