import 'package:flutter/widgets.dart';

/// Stiže's own icon set (design system: 24px frame, 2px stroke, butt caps,
/// mitre joins), built into the StizeIcons font from
/// `design/icons/*.svg`. Drop-in for Material `Icons.*`: same `Icon` widget,
/// size and colour from the theme. Regenerate with `tool/icons/build_font.py`.
abstract final class StizeIcons {
  static const _family = 'StizeIcons';

  static const IconData back = IconData(0xE003, fontFamily: _family);
  static const IconData bus = IconData(0xE006, fontFamily: _family);
  static const IconData busMultiple = IconData(0xE007, fontFamily: _family);
  static const IconData chat = IconData(0xE008, fontFamily: _family);
  static const IconData check = IconData(0xE009, fontFamily: _family);
  static const IconData chevronDown = IconData(0xE00A, fontFamily: _family);
  static const IconData chevronRight = IconData(0xE00B, fontFamily: _family);
  static const IconData chevronUp = IconData(0xE00C, fontFamily: _family);
  static const IconData clock = IconData(0xE00E, fontFamily: _family);
  static const IconData close = IconData(0xE00F, fontFamily: _family);
  static const IconData compass = IconData(0xE011, fontFamily: _family);
  static const IconData document = IconData(0xE013, fontFamily: _family);
  static const IconData error = IconData(0xE016, fontFamily: _family);
  static const IconData flag = IconData(0xE018, fontFamily: _family);
  static const IconData forward = IconData(0xE019, fontFamily: _family);
  static const IconData heart = IconData(0xE01C, fontFamily: _family);
  static const IconData hourglass = IconData(0xE01E, fontFamily: _family);
  static const IconData hub = IconData(0xE01F, fontFamily: _family);
  static const IconData info = IconData(0xE020, fontFamily: _family);
  static const IconData liveTransport = IconData(0xE022, fontFamily: _family);
  static const IconData locate = IconData(0xE023, fontFamily: _family);
  static const IconData luggage = IconData(0xE025, fontFamily: _family);
  static const IconData map = IconData(0xE026, fontFamily: _family);
  static const IconData menu = IconData(0xE027, fontFamily: _family);
  static const IconData minus = IconData(0xE028, fontFamily: _family);
  static const IconData moon = IconData(0xE029, fontFamily: _family);
  static const IconData more = IconData(0xE02A, fontFamily: _family);
  static const IconData nearMe = IconData(0xE02B, fontFamily: _family);
  static const IconData offline = IconData(0xE02D, fontFamily: _family);
  static const IconData pause = IconData(0xE02E, fontFamily: _family);
  static const IconData pin = IconData(0xE02F, fontFamily: _family);
  static const IconData plus = IconData(0xE032, fontFamily: _family);
  static const IconData refresh = IconData(0xE033, fontFamily: _family);
  static const IconData repeat = IconData(0xE034, fontFamily: _family);
  static const IconData search = IconData(0xE036, fontFamily: _family);
  static const IconData searchOff = IconData(0xE037, fontFamily: _family);
  static const IconData settings = IconData(0xE039, fontFamily: _family);
  static const IconData shield = IconData(0xE03A, fontFamily: _family);
  static const IconData star = IconData(0xE03E, fontFamily: _family);
  static const IconData starFilled = IconData(0xE03F, fontFamily: _family);
  static const IconData stopOff = IconData(0xE04D, fontFamily: _family);
  static const IconData stats = IconData(0xE040, fontFamily: _family);
  static const IconData train = IconData(0xE044, fontFamily: _family);
  static const IconData tram = IconData(0xE045, fontFamily: _family);
  static const IconData trolleybus = IconData(0xE048, fontFamily: _family);
  static const IconData warning = IconData(0xE04B, fontFamily: _family);
}
