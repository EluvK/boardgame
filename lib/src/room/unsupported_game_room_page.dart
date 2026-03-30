import 'package:flutter/material.dart';

import '../i18n/app_i18n.dart';
import 'room_session.dart';

class UnsupportedGameRoomPage extends StatelessWidget {
  const UnsupportedGameRoomPage({
    super.key,
    required this.session,
  });

  final RoomSession session;

  @override
  Widget build(BuildContext context) {
    final t = AppI18n.of(context).room;

    return Scaffold(
      appBar: AppBar(title: Text(t.text(zh: '房间: ${session.roomId}', en: 'Room: ${session.roomId}'))),
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
                  Text(t.text(zh: '当前游戏尚未支持客户端界面', en: 'Unsupported game view'), style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(t.text(zh: '房间ID: ${session.roomId}', en: 'roomId: ${session.roomId}')),
                  Text(t.text(zh: '游戏ID: ${session.gameId.isEmpty ? '-' : session.gameId}', en: 'gameId: ${session.gameId.isEmpty ? '-' : session.gameId}')),
                  const SizedBox(height: 8),
                  Text(t.text(zh: '该游戏暂未实现客户端页面。', en: 'This game does not have a client page yet.')),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: Text(t.text(zh: '返回大厅', en: 'Back to Lobby')),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          await session.onLeaveRoom(session.roomId);
                          if (context.mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                        child: Text(t.text(zh: '离开房间', en: 'Leave Room')),
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
