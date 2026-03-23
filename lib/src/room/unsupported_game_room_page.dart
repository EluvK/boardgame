import 'package:flutter/material.dart';

import 'room_session.dart';

class UnsupportedGameRoomPage extends StatelessWidget {
  const UnsupportedGameRoomPage({
    super.key,
    required this.session,
  });

  final RoomSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Room: ${session.roomId}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Unsupported game view', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('roomId: ${session.roomId}'),
                  Text('gameId: ${session.gameId.isEmpty ? '-' : session.gameId}'),
                  const SizedBox(height: 8),
                  const Text('This game does not have a client page yet.'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('Back to Lobby'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          await session.onLeaveRoom(session.roomId);
                          if (context.mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                        child: const Text('Leave Room'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
