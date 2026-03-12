import 'package:flutter/material.dart';

class RoomDetailPage extends StatefulWidget {
  const RoomDetailPage({super.key, required this.roomId, this.gameId, required this.onLeaveRoom});

  static const String routeName = '/room';

  final String roomId;
  final String? gameId;
  final Future<void> Function(String roomId) onLeaveRoom;

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  bool _leaving = false;
  String? _error;

  Future<void> _leaveRoom() async {
    if (_leaving) {
      return;
    }

    setState(() {
      _leaving = true;
      _error = null;
    });

    try {
      await widget.onLeaveRoom(widget.roomId);
      if (!mounted) {
        return;
      }
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _leaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('Room: ${widget.roomId}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Room Detail Scaffold', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text('roomId: ${widget.roomId}'),
                        Text('gameId: ${widget.gameId ?? '-'}'),
                        const SizedBox(height: 8),
                        Text(
                          'Next: wire realtime room state, player list, and in-room actions.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red.shade700)),
                        ],
                      ],
                    ),
                  ),
                ),
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
                      onPressed: _leaving ? null : _leaveRoom,
                      child: Text(_leaving ? 'Leaving...' : 'Leave Room'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
