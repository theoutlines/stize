enum VehicleType {
  bus,
  tram,
  trolleybus;

  static VehicleType fromApi(String value) {
    return VehicleType.values.firstWhere(
      (v) => v.name == value,
      orElse: () => VehicleType.bus,
    );
  }
}
