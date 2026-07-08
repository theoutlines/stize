class FavoriteStop {
  const FavoriteStop({required this.stopId, required this.name});

  final String stopId;
  final String name;

  Map<String, dynamic> toJson() => {'stop_id': stopId, 'name': name};

  factory FavoriteStop.fromJson(Map<String, dynamic> json) {
    return FavoriteStop(stopId: json['stop_id'] as String, name: json['name'] as String);
  }
}
