import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'platform_detector.dart';

/// Layout and sizing constants used throughout the application
/// Screen width breakpoints for responsive design
class ScreenBreakpoints {
  static const double mobile = 600;

  static const double wideTablet = 900;

  static const double desktop = 1200;

  static const double largeDesktop = 1600;

  // Legacy alias for backward compatibility
  static const double tablet = mobile;

  static bool isMobile(double width) => width < mobile;

  static bool isTablet(double width) => width >= mobile && width < desktop;

  static bool isDesktop(double width) => width >= desktop && width < largeDesktop;

  static bool isDesktopOrLarger(double width) => width >= desktop;

  static bool isWideTabletOrLarger(double width) => width >= wideTablet;
}

/// Animation and notification durations.
class AppDurations {
  static const Duration animMedium = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);
  static const Duration snackBarDefault = Duration(seconds: 3);
  static const Duration snackBarLong = Duration(seconds: 4);
}

/// Foreground content edges within the page's horizontal SafeArea.
class PageLayout {
  static const double tabContentTop = 8;

  static double horizontalOf(BuildContext context) {
    if (PlatformDetector.isTV()) return TvLayoutConstants.contentInsetForScale(TvLayoutConstants.scaleOf(context));
    if (PlatformDetector.isAutomotive()) return 24;
    return ScreenBreakpoints.isWideTabletOrLarger(MediaQuery.sizeOf(context).width) ? 36 : 12;
  }

  static EdgeInsets padding(BuildContext context, {double top = 0, double bottom = 0}) {
    final side = horizontalOf(context);
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }
}

class GridLayoutConstants {
  /// Artwork width:height per card shape. Captioned grid cells add the card's
  /// caption band on top of the artwork (see `MediaGridDelegate.cellHeightFor`);
  /// full-bleed cells are the artwork alone.
  static const double posterAspectRatio = 2 / 3;

  static const double episodeThumbnailAspectRatio = 16 / 9;

  /// 1:1 music artwork (albums/artists/tracks).
  static const double squareAspectRatio = 1 / 1;

  /// Inter-card gutter for square (music) grids on touch platforms. Cards
  /// already carry their own 3px internal padding, so the net visual gutter
  /// is ~14px horizontal. Automotive keeps its larger [crossAxisSpacing].
  static const double squareGridSpacing = 8.0;

  static double get crossAxisSpacing => PlatformDetector.isAutomotive() ? 24 : 0;
  static double get mainAxisSpacing => PlatformDetector.isAutomotive() ? 24 : 0;

  static double fullCardGridSpacingForScale(double scale) => (12 * scale).clamp(8, 18).toDouble();
}

class TvLayoutConstants {
  static double contentInsetForScale(double scale) => (24 * scale).clamp(18, 40).toDouble();
  static const double shelfVerticalGap = 32;
  static const double heroContentMaxWidth = 760;
  static const double heroLogoWidth = 520;
  static const double heroLogoHeight = 150;
  static const double compactHeroLogoWidth = 360;
  static const double compactHeroLogoHeight = 96;

  static double scaleForHeight(double height) => (height / 1080).clamp(0.85, 1.35).toDouble();

  /// Android TV reports density-independent dimensions, often 960x540 or
  /// 1280x720 even when HDMI output is 1080p or 4K. Fit both axes instead of
  /// enforcing the full-HD layout's minimum scale.
  static double androidTvScaleForSize(Size size) =>
      math.min(size.width / 1920, size.height / 1080).clamp(0.35, 1.35).toDouble();

  static double scaleForSize(Size size) =>
      Platform.isAndroid && PlatformDetector.isTV()
          ? androidTvScaleForSize(size)
          : scaleForHeight(size.height);

  static double scaleOf(BuildContext context) => scaleForSize(MediaQuery.sizeOf(context));
}
