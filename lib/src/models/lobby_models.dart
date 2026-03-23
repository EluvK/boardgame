class RegisteredGame {
  RegisteredGame({
    required this.id,
    required this.name,
    required this.minPlayers,
    required this.maxPlayers,
    required this.version,
  });

  final String id;
  final String name;
  final int minPlayers;
  final int maxPlayers;
  final String version;

  factory RegisteredGame.fromJson(Map<String, dynamic> json) {
    return RegisteredGame(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      minPlayers: _parseInt(json['min_players']),
      maxPlayers: _parseInt(json['max_players']),
      version: json['version']?.toString() ?? '',
    );
  }
}

class RoomSummary {
  RoomSummary({
    required this.id,
    required this.gameId,
    required this.playerCount,
    required this.readyCount,
    required this.started,
  });

  final String id;
  final String gameId;
  final int playerCount;
  final int readyCount;
  final bool started;

  factory RoomSummary.fromJson(Map<String, dynamic> json) {
    return RoomSummary(
      id: json['id']?.toString() ?? '',
      gameId: json['game_id']?.toString() ?? '',
      playerCount: _parseInt(json['player_count']),
      readyCount: _parseInt(json['ready_count']),
      started: json['started'] == true,
    );
  }
}

int _parseInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}
