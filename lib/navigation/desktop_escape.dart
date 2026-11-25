import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus/dpad_navigator.dart';
import '../focus/key_event_utils.dart';
import '../utils/platform_detector.dart';
import '../widgets/overlay_sheet.dart';

/// Desktop embedders report every hardware key as a keyboard key, so a remote
/// (HDMI-CEC, IR receiver) Escape cannot be told apart from a keyboard Escape.
/// TV mode is the signal that the machine is remote-driven: there Escape stays
/// Back and keeps the press-back-again exit (#2490).
@visibleForTesting
bool shouldHandleDesktopEscape({
  required bool isDesktop,
  required bool isTV,
  required bool isPhysicalKeyboardEvent,
  required LogicalKeyboardKey logicalKey,
  required bool isCurrentRoute,
}) {
  return isDesktop && !isTV && isPhysicalKeyboardEvent && logicalKey == LogicalKeyboardKey.escape && isCurrentRoute;
}

/// Runs before the focused card or tab strip can interpret desktop keyboard
/// Escape as a remote Back press and move focus into the sidebar.
KeyEventResult dispatchDesktopEscape(
  BuildContext context,
  KeyEvent event, {
  bool searchSelected = false,
  bool suppressKeyUp = false,
  required VoidCallback goBack,
}) {
  if (event.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
  final route = ModalRoute.of(context);
  if (!shouldHandleDesktopEscape(
    isDesktop: PlatformDetector.isDesktopOS(),
    isTV: PlatformDetector.isTV(),
    isPhysicalKeyboardEvent: event.isPhysicalKeyboardEvent,
    logicalKey: event.logicalKey,
    isCurrentRoute: route?.isCurrent == true,
  )) {
    return KeyEventResult.ignored;
  }

  final focused = FocusManager.instance.primaryFocus?.context;
  if (OverlaySheetController.openSheetCount.value > 0 || (focused != null && ModalRoute.of(focused) != route)) {
    return KeyEventResult.ignored;
  }
  if ((suppressKeyUp && event is KeyUpEvent) || BackKeyUpSuppressor.consumeIfSuppressed(event)) {
    return KeyEventResult.handled;
  }

  // The search field already uses Escape to clear a query as its first step.
  final editor = focused?.findAncestorStateOfType<EditableTextState>();
  if (searchSelected && editor != null && editor.widget.controller.text.isNotEmpty) {
    return KeyEventResult.ignored;
  }
  // Menus may dismiss on key-down and deliver their key-up to this route.
  // Only a fresh press in the shell can navigate through its history.
  if (event is KeyDownEvent) {
    BackKeyCoordinator.markHandled();
    goBack();
    BackKeyUpSuppressor.suppressBackUntilKeyUp();
  }
  return KeyEventResult.handled;
}
