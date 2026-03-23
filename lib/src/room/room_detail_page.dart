import 'package:flutter/material.dart';

import '../api/lobby_api.dart';
import 'room_game_router.dart';
import 'room_session.dart';

class RoomDetailPage extends StatefulWidget {
  const RoomDetailPage({
    super.key,
    required this.roomId,
    this.gameId,
    required this.userId,
    required this.api,
    required this.onLeaveRoom,
  });

  static const String routeName = '/room';

  final String roomId;
  final String? gameId;
  final String userId;
  final LobbyApi api;
  final Future<void> Function(String roomId) onLeaveRoom;

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  @override
  Widget build(BuildContext context) {
    final session = RoomSession(
      roomId: widget.roomId,
      gameId: widget.gameId ?? '',
      userId: widget.userId,
      api: widget.api,
      onLeaveRoom: widget.onLeaveRoom,
    );

    return RoomGameRouter(session: session);
  }
}
