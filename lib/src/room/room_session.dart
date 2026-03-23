import '../api/lobby_api.dart';

class RoomSession {
  const RoomSession({
    required this.roomId,
    required this.gameId,
    required this.userId,
    required this.api,
    required this.onLeaveRoom,
  });

  final String roomId;
  final String gameId;
  final String userId;
  final LobbyApi api;
  final Future<void> Function(String roomId) onLeaveRoom;
}
