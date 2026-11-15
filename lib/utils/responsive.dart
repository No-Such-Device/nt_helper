import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/constants.dart';

/// Utility class for responsive layout helpers
class Responsive {
  /// Check if the current screen width is mobile-sized
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < Constants.mobileBreakpoint;
  }

  /// Check if the current screen width is tablet-sized
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= Constants.mobileBreakpoint &&
        width < Constants.tabletBreakpoint;
  }

  /// Check if the current screen width is desktop-sized
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= Constants.tabletBreakpoint;
  }

  /// Get the appropriate number of columns for a grid based on screen size
  static int getGridColumns(BuildContext context) {
    if (isMobile(context)) return 1;
    if (isTablet(context)) return 2;
    return 3;
  }

  /// Get appropriate padding for the current screen size
  static EdgeInsets getScreenPadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.all(Constants.mobileSearchBarPadding);
    }
    return const EdgeInsets.all(16.0);
  }

  /// Get appropriate spacing for filters based on screen size
  static double getFilterSpacing(BuildContext context) {
    return isMobile(context) ? Constants.mobileFilterSpacing : 12.0;
  }

  /// Determine if navigation should be compact (mobile style)
  static bool shouldUseCompactNavigation(BuildContext context) {
    return isMobile(context);
  }

  /// Get the appropriate NavigationRail width based on screen size
  static double getNavigationRailWidth(BuildContext context) {
    return isMobile(context) ? Constants.mobileNavRailWidth : 80.0;
  }
}
