import 'package:flutter/painting.dart';

/// BANDANA design system border radius tokens.
///
/// Consistent rounded geometry following the neo-brutalist visual language.
class AppRadius {
  AppRadius._();

  /// 12px — Small radius for chips, badges, small cards.
  static const double sm = 12.0;

  /// 18px — Medium radius for standard cards, buttons.
  static const double md = 18.0;

  /// 24px — Large radius for prominent cards, dialogs.
  static const double lg = 24.0;

  /// 28px — Hero card radius (primary metric cards).
  static const double xl = 28.0;

  /// 32px — Maximum hero card radius.
  static const double xxl = 32.0;

  /// Fully rounded — For pills, circular buttons, status indicators.
  static const double pill = 9999.0;

  /// Circular — For avatars, circular icons.
  static const double circular = 9999.0;

  // Pre-built BorderRadius objects for convenience.
  static const BorderRadius smRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlRadius = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius xxlRadius = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius pillRadius = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius circularRadius = BorderRadius.all(Radius.circular(circular));

  /// Card radius — standard cards use md (18px).
  static const BorderRadius card = mdRadius;

  /// Bento container radius — prominent bento containers use lg (24px).
  static const BorderRadius bentoCard = lgRadius;

  /// Hero card radius — primary metrics use lg/xl (24px).
  static const BorderRadius heroCard = lgRadius;

  /// Button radius — standard buttons use md (18px).
  static const BorderRadius button = mdRadius;

  /// Small button radius — compact buttons use sm (12px).
  static const BorderRadius buttonSmall = smRadius;

  /// Chip/pill radius — fully rounded.
  static const BorderRadius chip = pillRadius;

  /// Input field radius.
  static const BorderRadius input = smRadius;

  /// Dialog/bottom sheet radius — top corners only.
  static const BorderRadius dialog = BorderRadius.vertical(top: Radius.circular(xl));

  /// App bar / sheet handle radius.
  static const BorderRadius handle = BorderRadius.all(Radius.circular(2));
}