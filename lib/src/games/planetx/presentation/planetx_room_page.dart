import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../room/room_session.dart';
import '../data/planetx_client.dart';
import '../data/planetx_models.dart';

class PlanetXRoomPage extends StatefulWidget {
  const PlanetXRoomPage({
    super.key,
    required this.session,
  });

  final RoomSession session;

  @override
  State<PlanetXRoomPage> createState() => _PlanetXRoomPageState();
}

class _PlanetXRoomPageState extends State<PlanetXRoomPage> {
  late final PlanetXClient _client;

  PlanetXStateEnvelope? _latestState;
  final List<String> _logs = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = PlanetXClient(api: widget.session.api);
    widget.session.api.addBroadcastListener(_onBroadcast);
    widget.session.api.addMessageListener(_onMessage);
    _ensureJoined();
  }

  @override
  void dispose() {
    widget.session.api.removeBroadcastListener(_onBroadcast);
    widget.session.api.removeMessageListener(_onMessage);
    super.dispose();
  }

  Future<void> _ensureJoined() async {
    try {
      await widget.session.api.joinRoom(widget.session.roomId);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
      });
    }
  }

  void _onBroadcast(Map<String, dynamic> payload) {
    if (!mounted) {
      return;
    }

    final type = payload['type']?.toString() ?? '';
    final game = payload['game']?.toString() ?? '';

    if (type == 'state' && game == 'planetx') {
      setState(() {
        _latestState = PlanetXStateEnvelope.fromJson(payload);
        _logs.insert(0, 'state:${_latestState?.event ?? ''}');
        if (_logs.length > 30) {
          _logs.removeLast();
        }
      });
    }
  }

  void _onMessage(Map<String, dynamic> payload) {
    if (!mounted) {
      return;
    }

    final type = payload['type']?.toString() ?? '';
    if (type.startsWith('planetx_')) {
      setState(() {
        _logs.insert(0, '$type ${jsonEncode(payload)}');
        if (_logs.length > 30) {
          _logs.removeLast();
        }
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String label) async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await action();
      if (!mounted) {
        return;
      }
      setState(() {
        _logs.insert(0, 'action:$label ok');
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
        _logs.insert(0, 'action:$label fail $e');
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (_logs.length > 30) {
            _logs.removeRange(30, _logs.length);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateMap = _latestState?.state ?? <String, dynamic>{};
    final players = _asStringList(stateMap['players']);
    final currentPlayer = _latestState?.raw['state'] is Map
        ? (_asMap(_latestState!.raw['state'])['current_player']?.toString() ?? '')
        : '';

    return Scaffold(
      appBar: AppBar(
        title: Text('Planet X · ${widget.session.roomId}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('User: ${widget.session.userId}'),
            Text('Current: $currentPlayer'),
            Text('Players: ${players.join(', ')}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => _client.sync(
                              room: widget.session.roomId,
                              userId: widget.session.userId,
                            ),
                            'sync',
                          ),
                  child: const Text('Sync'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => _client.recommendCount(
                              room: widget.session.roomId,
                              userId: widget.session.userId,
                            ),
                            'recommend_count',
                          ),
                  child: const Text('Recommend Count'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => _client.recommendCanLocate(
                              room: widget.session.roomId,
                              userId: widget.session.userId,
                            ),
                            'recommend_can_locate',
                          ),
                  child: const Text('Recommend CanLocate'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => _client.sendSurvey(
                              room: widget.session.roomId,
                              userId: widget.session.userId,
                              sectorType: 'comet',
                              start: 1,
                              end: 6,
                            ),
                            'survey',
                          ),
                  child: const Text('Survey 1-6 comet'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => _client.sendTarget(
                              room: widget.session.roomId,
                              userId: widget.session.userId,
                              index: 1,
                            ),
                            'target',
                          ),
                  child: const Text('Target 1'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => _client.sendResearch(
                              room: widget.session.roomId,
                              userId: widget.session.userId,
                              clueIndex: 'A',
                            ),
                            'research_A',
                          ),
                  child: const Text('Research A'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 8),
            const Text('Logs'),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) => Text(_logs[index]),
                ),
              ),
            ),
          ],
        ),
      ),
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

List<String> _asStringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((e) => e.toString()).toList();
}
