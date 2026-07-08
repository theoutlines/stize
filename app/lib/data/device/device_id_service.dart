import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A random, anonymous, on-device identifier used to rate-limit idea
/// submissions and let each device cast one vote per idea. No accounts,
/// nothing tied to a real identity — just a locally generated string.
class DeviceIdService {
  static const _prefsKey = 'device_id_v1';

  Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null) return existing;

    final generated = _generate();
    await prefs.setString(_prefsKey, generated);
    return generated;
  }

  String _generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
