import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../utils/layout_constants.dart';
import '../focus/focusable_button.dart';
import '../focus/focusable_text_field.dart';
import '../i18n/strings.g.dart';
import '../theme/mono_tokens.dart';
import 'app_icon.dart';
import 'pill_input_decoration.dart';

/// The pill search field the search screens put above their results, with the
/// clear affordance that appears once there is text: RIGHT out of the field
/// lands on it, LEFT goes back, and both escape down into the results.
///
/// [onBack] stays null unless the host wants the back key — a pushed route
/// needs it for its own pop.
class SearchInputField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;

  /// Names the clear button's focus node.
  final String debugLabel;

  final TvTextInputController? tvTextInputController;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onEditingComplete;
  final VoidCallback? onBack;

  const SearchInputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.debugLabel,
    this.tvTextInputController,
    this.onNavigateLeft,
    this.onNavigateDown,
    this.onEditingComplete,
    this.onBack,
  });

  @override
  State<SearchInputField> createState() => _SearchInputFieldState();
}

class _SearchInputFieldState extends State<SearchInputField> {
  late final FocusNode _clearFocusNode = FocusNode(debugLabel: '${widget.debugLabel}.clear');

  @override
  void dispose() {
    _clearFocusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    widget.controller.clear();
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labelStyle = navigationPillLabelStyle(theme);
    final height = theme.materialTapTargetSize == MaterialTapTargetSize.padded ? kMinInteractiveDimension : 42.0;
    final hasText = widget.controller.text.isNotEmpty;
    return Padding(
      padding: PageLayout.padding(context, top: PageLayout.tabContentTop, bottom: 16),
      child: Stack(
        children: [
          FocusableTextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            tvTextInputController: widget.tvTextInputController,
            style: labelStyle,
            textInputAction: TextInputAction.search,
            onNavigateLeft: widget.onNavigateLeft,
            onNavigateRight: hasText ? _clearFocusNode.requestFocus : null,
            onNavigateDown: widget.onNavigateDown,
            onEditingComplete: widget.onEditingComplete,
            onBack: widget.onBack,
            decoration: pillInputDecoration(context, hintText: widget.hintText).copyWith(
              prefixIcon: AppIcon(
                Symbols.search_rounded,
                size: 18,
                weight: 400,
                fill: 0,
                color: colors.onSurfaceVariant,
              ),
              prefixIconConstraints: BoxConstraints.tightFor(width: 40, height: height),
              suffixIcon: hasText ? const SizedBox.shrink() : null,
              suffixIconConstraints: BoxConstraints.tightFor(width: kMinInteractiveDimension, height: height),
            ),
          ),
          if (hasText)
            PositionedDirectional(
              end: 0,
              top: 0,
              bottom: 0,
              width: kMinInteractiveDimension,
              child: Center(
                child: FocusableButton(
                  focusNode: _clearFocusNode,
                  onPressed: _clearSearch,
                  onNavigateLeft: widget.focusNode.requestFocus,
                  onNavigateDown: widget.onNavigateDown,
                  autoScroll: false,
                  child: IconButton(
                    tooltip: t.common.clear,
                    icon: const AppIcon(Symbols.clear_rounded, size: 18, weight: 400, fill: 0),
                    onPressed: _clearSearch,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
