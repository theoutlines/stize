import '../models/jam.dart';

abstract class JamsRepository {
  /// The current tram-jam set. `sim` (staging only) forces a synthetic jam so a
  /// stand can be verified without a live jam.
  Future<JamsBoard> current({String? sim});
}
