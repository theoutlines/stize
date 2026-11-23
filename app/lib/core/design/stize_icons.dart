import 'package:flutter/widgets.dart';

/// Stiže's own icon set (design system: 24px frame, 2px stroke, butt caps,
/// mitre joins), built into the StizeIcons font from
/// `design/icons/*.svg`. Drop-in for Material `Icons.*`: same `Icon` widget,
/// size and colour from the theme. Regenerate with `tool/icons/build_font.py`.
abstract final class StizeIcons {
  static const _family = 'StizeIcons';

  static const IconData accessible = IconData(0xE000, fontFamily: _family);
  static const IconData arrowDown = IconData(0xE001, fontFamily: _family);
  static const IconData arrowUp = IconData(0xE002, fontFamily: _family);
  static const IconData back = IconData(0xE003, fontFamily: _family);
  static const IconData bug = IconData(0xE004, fontFamily: _family);
  static const IconData building = IconData(0xE005, fontFamily: _family);
  static const IconData bus = IconData(0xE006, fontFamily: _family);
  static const IconData busMultiple = IconData(0xE007, fontFamily: _family);
  static const IconData chat = IconData(0xE008, fontFamily: _family);
  static const IconData check = IconData(0xE009, fontFamily: _family);
  static const IconData chevronDown = IconData(0xE00A, fontFamily: _family);
  static const IconData chevronRight = IconData(0xE00B, fontFamily: _family);
  static const IconData chevronUp = IconData(0xE00C, fontFamily: _family);
  static const IconData circle = IconData(0xE00D, fontFamily: _family);
  static const IconData clock = IconData(0xE00E, fontFamily: _family);
  static const IconData close = IconData(0xE00F, fontFamily: _family);
  static const IconData compare = IconData(0xE010, fontFamily: _family);
  static const IconData compass = IconData(0xE011, fontFamily: _family);
  static const IconData dataset = IconData(0xE012, fontFamily: _family);
  static const IconData document = IconData(0xE013, fontFamily: _family);
  static const IconData dot = IconData(0xE014, fontFamily: _family);
  static const IconData edit = IconData(0xE015, fontFamily: _family);
  static const IconData error = IconData(0xE016, fontFamily: _family);
  static const IconData factory = IconData(0xE017, fontFamily: _family);
  static const IconData flag = IconData(0xE018, fontFamily: _family);
  static const IconData forward = IconData(0xE019, fontFamily: _family);
  static const IconData fuel = IconData(0xE01A, fontFamily: _family);
  static const IconData groups = IconData(0xE01B, fontFamily: _family);
  static const IconData heart = IconData(0xE01C, fontFamily: _family);
  static const IconData history = IconData(0xE01D, fontFamily: _family);
  static const IconData hourglass = IconData(0xE01E, fontFamily: _family);
  static const IconData hub = IconData(0xE01F, fontFamily: _family);
  static const IconData info = IconData(0xE020, fontFamily: _family);
  static const IconData leaf = IconData(0xE021, fontFamily: _family);
  static const IconData liveTransport = IconData(0xE022, fontFamily: _family);
  static const IconData locate = IconData(0xE023, fontFamily: _family);
  static const IconData locateOff = IconData(0xE024, fontFamily: _family);
  static const IconData luggage = IconData(0xE025, fontFamily: _family);
  static const IconData map = IconData(0xE026, fontFamily: _family);
  static const IconData menu = IconData(0xE027, fontFamily: _family);
  static const IconData minus = IconData(0xE028, fontFamily: _family);
  static const IconData moon = IconData(0xE029, fontFamily: _family);
  static const IconData nearMe = IconData(0xE02A, fontFamily: _family);
  static const IconData nearMeOff = IconData(0xE02B, fontFamily: _family);
  static const IconData offline = IconData(0xE02C, fontFamily: _family);
  static const IconData pause = IconData(0xE02D, fontFamily: _family);
  static const IconData pin = IconData(0xE02E, fontFamily: _family);
  static const IconData pinPush = IconData(0xE02F, fontFamily: _family);
  static const IconData pinPushFilled = IconData(0xE030, fontFamily: _family);
  static const IconData plus = IconData(0xE031, fontFamily: _family);
  static const IconData repeat = IconData(0xE032, fontFamily: _family);
  static const IconData ruler = IconData(0xE033, fontFamily: _family);
  static const IconData search = IconData(0xE034, fontFamily: _family);
  static const IconData searchOff = IconData(0xE035, fontFamily: _family);
  static const IconData seat = IconData(0xE036, fontFamily: _family);
  static const IconData settings = IconData(0xE037, fontFamily: _family);
  static const IconData shield = IconData(0xE038, fontFamily: _family);
  static const IconData snowflake = IconData(0xE039, fontFamily: _family);
  static const IconData speed = IconData(0xE03A, fontFamily: _family);
  static const IconData stairs = IconData(0xE03B, fontFamily: _family);
  static const IconData star = IconData(0xE03C, fontFamily: _family);
  static const IconData starFilled = IconData(0xE03D, fontFamily: _family);
  static const IconData stats = IconData(0xE03E, fontFamily: _family);
  static const IconData stop = IconData(0xE03F, fontFamily: _family);
  static const IconData sun = IconData(0xE040, fontFamily: _family);
  static const IconData timelapse = IconData(0xE041, fontFamily: _family);
  static const IconData train = IconData(0xE042, fontFamily: _family);
  static const IconData tram = IconData(0xE043, fontFamily: _family);
  static const IconData transit = IconData(0xE044, fontFamily: _family);
  static const IconData trendingUp = IconData(0xE045, fontFamily: _family);
  static const IconData trolleybus = IconData(0xE046, fontFamily: _family);
  static const IconData usb = IconData(0xE047, fontFamily: _family);
  static const IconData walk = IconData(0xE048, fontFamily: _family);
  static const IconData warning = IconData(0xE049, fontFamily: _family);
  static const IconData zoomIn = IconData(0xE04A, fontFamily: _family);
}
