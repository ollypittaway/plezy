import 'dart:math' as math;

import 'package:flutter/foundation.dart' show AsyncCallback;
import 'package:flutter/material.dart';

import '../focus/focusable_wrapper.dart';
import '../focus/key_event_utils.dart';
import '../i18n/strings.g.dart';
import 'splash_logo.dart';
import '../profiles/profile.dart';
import '../profiles/profile_avatar.dart';
import '../theme/mono_theme.dart';
import 'app_system_ui_style.dart';

class ProfileChooser extends StatefulWidget {
  const ProfileChooser({
    super.key,
    required this.profiles,
    required this.activeId,
    required this.loading,
    required this.focusNodeFor,
    required this.avatarUrlFor,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onBack,
    required this.showBack,
  });

  final List<Profile> profiles;
  final String? activeId;
  final bool loading;
  final FocusNode Function(Profile) focusNodeFor;
  final String? Function(String) avatarUrlFor;
  final Future<void> Function(Profile)? onSelect;
  final AsyncCallback? onAdd;
  final VoidCallback? onEdit;
  final VoidCallback onBack;
  final bool showBack;

  @override
  State<ProfileChooser> createState() => _ProfileChooserState();
}

class _ProfileChooserState extends State<ProfileChooser> {
  final _addNode = FocusNode(debugLabel: 'AddProfile');
  FocusNode? _activating;

  Future<void> _activate(FocusNode node, AsyncCallback action, Duration wait) async {
    if (_activating != null) return;
    setState(() => _activating = node);
    try {
      if (wait != Duration.zero) await Future<void>.delayed(wait);
      // Back, Edit, or a profile refresh can remove the tapped tile mid-animation.
      if (!mounted || node.context == null || ModalRoute.isCurrentOf(context) != true) return;
      await action();
    } finally {
      if (mounted) setState(() => _activating = null);
    }
  }

  @override
  void dispose() {
    _addNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? theme
        : monoTheme(MonoPalette.dark.withColor(MonoPaletteSlot.accent, theme.colorScheme.primary));
    return Theme(
      data: palette.copyWith(scaffoldBackgroundColor: Colors.black),
      child: AppSystemUiStyle(child: Builder(builder: _buildChooser)),
    );
  }

  Widget _buildChooser(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) => handleBackKeyAction(event, widget.onBack),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) {
              final compact = viewport.maxWidth < 560;
              final margin = compact ? 16.0 : 36.0;
              return SingleChildScrollView(
                padding: EdgeInsets.all(margin),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: math.max(0, viewport.maxHeight - 2 * margin)),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(compact ? 12 : 24, 10, compact ? 12 : 24, compact ? 38 : 66),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: widget.showBack
                                        ? IconButton(
                                            onPressed: widget.onBack,
                                            tooltip: t.common.back,
                                            color: colors.onSurface,
                                            icon: const Icon(Icons.arrow_back_rounded, size: 20),
                                          )
                                        : null,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const OffstageMark(size: 24),
                                      const SizedBox(width: 5),
                                      Flexible(child: OffstageWordmark(width: 62, color: colors.onSurface)),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: widget.onEdit == null
                                        ? null
                                        : TextButton(
                                            onPressed: widget.onEdit,
                                            style: TextButton.styleFrom(
                                              foregroundColor: colors.onSurface,
                                              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                fontWeight: FontWeight.w400,
                                                fontSize: 14,
                                              ),
                                            ),
                                            child: Text(t.common.edit),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: compact ? 30 : 42),
                            Semantics(
                              header: true,
                              child: Text(
                                t.profiles.whoIsWatching,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: compact ? 25 : 32,
                                  fontWeight: FontWeight.w400,
                                  height: 1.15,
                                  letterSpacing: -1.1,
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 18 : 24),
                            if (widget.loading)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: CircularProgressIndicator(color: colors.onSurfaceVariant),
                              )
                            else ...[
                              if (widget.profiles.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    t.messages.noProfilesAvailable,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: colors.onSurfaceVariant),
                                  ),
                                ),
                              LayoutBuilder(
                                builder: (context, constraints) => _choices(context, constraints.maxWidth, compact),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _choices(BuildContext context, double width, bool compact) {
    final colors = Theme.of(context).colorScheme;
    final slots = <FocusNode>[for (final profile in widget.profiles) widget.focusNodeFor(profile), _addNode];
    final active = widget.profiles.where((profile) => profile.id == widget.activeId).firstOrNull;
    final preferred = active == null ? slots.first : widget.focusNodeFor(active);
    final highlighted = _activating ?? slots.where((node) => node.hasFocus).firstOrNull ?? preferred;
    final gap = compact ? 4.0 : 16.0;
    final columns = math.max(1, ((width + gap) / ((compact ? 76 : 124) + gap)).floor());
    final tileWidth = math.min(compact ? 102.0 : 132.0, (width - gap * (columns - 1)) / columns);
    final diameter = math.min(compact ? 72.0 : 96.0, tileWidth / 1.23);

    Widget tile(FocusNode node, String name, Widget avatar, AsyncCallback? onSelect, {bool active = false}) {
      final selected = highlighted == node;
      final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 210);
      final activate = onSelect == null || _activating != null
          ? null
          : () => _activate(node, onSelect, selected ? Duration.zero : duration);
      return SizedBox(
        key: ObjectKey(node),
        width: tileWidth,
        child: FocusableWrapper(
          focusNode: node,
          autofocus: node == preferred,
          disableScale: true,
          delegateFocusBorder: true,
          semanticLabel: name,
          semanticValue: active ? t.profiles.active : null,
          onSelect: activate,
          onFocusChange: (_) {
            if (mounted) setState(() {});
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) {
              if (activate != null) node.requestFocus();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: activate,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: diameter * 1.25,
                    child: Center(
                      child: AnimatedScale(
                        scale: selected ? 1.2 : 1,
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        child: AnimatedOpacity(opacity: selected ? 1 : 0.66, duration: duration, child: avatar),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? colors.onSurface : colors.onSurfaceVariant,
                      fontSize: compact ? 14 : 17,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final selectProfile = widget.onSelect;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: gap,
      runSpacing: 18,
      children: [
        for (final profile in widget.profiles)
          tile(
            widget.focusNodeFor(profile),
            profile.displayName,
            ProfileAvatar(profile: profile, avatarUrl: widget.avatarUrlFor(profile.id), size: diameter),
            selectProfile == null ? null : () => selectProfile(profile),
            active: profile == active,
          ),
        tile(
          _addNode,
          t.profiles.add,
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.onSurfaceVariant),
              borderRadius: BorderRadius.circular(diameter * 0.2),
            ),
            child: SizedBox.square(
              dimension: diameter,
              child: Icon(Icons.add_rounded, color: colors.onSurface, size: diameter * 0.52),
            ),
          ),
          widget.onAdd,
        ),
      ],
    );
  }
}
