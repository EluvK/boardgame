import 'package:flutter/material.dart';

import '../games/acquire/presentation/acquire_room_page.dart';
import 'room_session.dart';
import 'unsupported_game_room_page.dart';

class RoomGameRouter extends StatelessWidget {
  const RoomGameRouter({
    super.key,
    required this.session,
  });

  final RoomSession session;

  @override
  Widget build(BuildContext context) {
    switch (session.gameId) {
      case 'acquire':
        return AcquireRoomPage(session: session);
      default:
        return UnsupportedGameRoomPage(session: session);
    }
  }
}
