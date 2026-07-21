import 'package:flutter_test/flutter_test.dart';
import 'package:stize/domain/models/app_config.dart';

void main() {
  test('vehicles_on_demand flag maps to the getter', () {
    final on = AppConfig.fromJson({
      'version': '1',
      'flags': {'vehicles_on_demand': true},
    });
    expect(on.vehiclesOnDemand, isTrue);

    final off = AppConfig.fromJson({
      'version': '1',
      'flags': {'vehicles_on_demand': false},
    });
    expect(off.vehiclesOnDemand, isFalse);
  });

  test('a missing flag defaults off, so the feature never leaks', () {
    expect(AppConfig.empty.vehiclesOnDemand, isFalse);
    final noFlag = AppConfig.fromJson({'version': '1', 'flags': {}});
    expect(noFlag.vehiclesOnDemand, isFalse);
  });
}
