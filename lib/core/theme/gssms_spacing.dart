/// Spacing scale for GSSMS Mobile. Use these instead of ad-hoc padding values.
class GssmsSpacing {
  const GssmsSpacing._();

  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  /// Bottom inset for scrollable content under a FAB / sticky action bar.
  static const double fabClearance = 88;
}

/// Component dimensions shared across screens.
class GssmsSize {
  const GssmsSize._();

  /// Material minimum touch target; also the floor for button heights.
  static const double touchTarget = 48;

  /// Primary actions on operational screens (gloved / outdoor use).
  static const double primaryAction = 52;

  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 48;
}
