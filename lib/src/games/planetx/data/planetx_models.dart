class PlanetXStateEnvelope {
  PlanetXStateEnvelope({
    required this.event,
    required this.raw,
  });

  final String event;
  final Map<String, dynamic> raw;

  Map<String, dynamic> get state => _asMap(raw['state']);

  String get game => raw['game']?.toString() ?? '';

  factory PlanetXStateEnvelope.fromJson(Map<String, dynamic> json) {
    return PlanetXStateEnvelope(
      event: json['event']?.toString() ?? '',
      raw: json,
    );
  }
}

Map<String, dynamic> _asMap(dynamic data) {
  if (data is Map<String, dynamic>) {
    return data;
  }
  if (data is Map) {
    return data.map((k, v) => MapEntry(k.toString(), v));
  }
  return <String, dynamic>{};
}
