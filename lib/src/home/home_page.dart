import 'package:flutter/material.dart';
import 'dart:async';

import '../api/lobby_api.dart';
import '../models/lobby_models.dart';
import '../room/room_detail_page.dart';
import '../utils/device_identity.dart';
import '../utils/lobby_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _serverCtrl = TextEditingController(text: 'http://127.0.0.1:17980');
  final _userNameCtrl = TextEditingController(text: 'web-user');
  final _roomIdCtrl = TextEditingController(text: 'room_001');
  final _joinRoomCtrl = TextEditingController(text: 'demo');

  LobbyApi? _api;
  Timer? _lobbyRefreshTimer;

  bool _connected = false;
  bool _authed = false;
  bool _busy = false;
  bool _autoJoinOnCreate = true;

  String _message = 'Ready';
  String? _deviceId;

  List<RegisteredGame> _games = const [];
  List<RoomSummary> _rooms = const [];
  String? _selectedGameId;

  @override
  void initState() {
    super.initState();
    _initProfile();
  }

  Future<void> _initProfile() async {
    final profile = await LobbyPreferences.loadProfile();
    if (!mounted) {
      return;
    }
    setState(() {
      _deviceId = profile.deviceId;
      _userNameCtrl.text = profile.userName;
      _serverCtrl.text = profile.serverUrl;
    });
  }

  @override
  void dispose() {
    _lobbyRefreshTimer?.cancel();
    _api?.disconnect();
    _serverCtrl.dispose();
    _userNameCtrl.dispose();
    _roomIdCtrl.dispose();
    _joinRoomCtrl.dispose();
    super.dispose();
  }

  Future<void> _runTask(Future<void> Function() task) async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await task();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = 'Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _connect() async {
    await _runTask(() async {
      final deviceId = _deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        throw Exception('Device ID not ready');
      }

      final api = LobbyApi(serverUrl: _serverCtrl.text.trim());
      await api.connect();

      final normalizedName = _effectiveUserName(deviceId);
      await LobbyPreferences.saveServerUrl(_serverCtrl.text.trim());
      await LobbyPreferences.saveUserName(normalizedName);
      await api.auth(userId: deviceId, name: normalizedName);

      _api?.disconnect();
      _api = api;
      _bindLobbyPush(api);
      _startLobbyAutoRefresh();

      setState(() {
        _connected = true;
        _authed = true;
        _message = 'Connected and authenticated';
      });

      await _refreshGamesAndRooms();
    });
  }

  void _disconnect() {
    _lobbyRefreshTimer?.cancel();
    _lobbyRefreshTimer = null;
    _api?.disconnect();
    setState(() {
      _connected = false;
      _authed = false;
      _games = const [];
      _rooms = const [];
      _selectedGameId = null;
      _message = 'Disconnected';
    });
  }

  Future<void> _reauthWithNewName() async {
    await _runTask(() async {
      final api = _api;
      final deviceId = _deviceId;
      if (api == null || !_connected) {
        throw Exception('Connect first');
      }
      if (deviceId == null || deviceId.isEmpty) {
        throw Exception('Device ID not ready');
      }

      final normalizedName = _effectiveUserName(deviceId);
      await api.auth(userId: deviceId, name: normalizedName);

      await LobbyPreferences.saveUserName(normalizedName);

      setState(() {
        _authed = true;
        _message = 'Name updated';
      });
    });
  }

  Future<void> _refreshGamesAndRooms() async {
    final api = _api;
    if (api == null || !_connected) {
      throw Exception('Connect first');
    }

    final games = await api.listGames();
    final rooms = await api.listRooms();

    if (!mounted) {
      return;
    }

    setState(() {
      _games = games;
      _rooms = rooms;
      _selectedGameId = _resolveSelectedGame(games, _selectedGameId);
      _message = 'Fetched ${games.length} games, ${rooms.length} rooms';
    });
  }

  void _bindLobbyPush(LobbyApi api) {
    api.setRoomsUpdatedListener((rooms) {
      if (!mounted) {
        return;
      }

      setState(() {
        _rooms = rooms;
        _message = 'Lobby updated: ${rooms.length} rooms';
      });
    });
  }

  void _startLobbyAutoRefresh() {
    _lobbyRefreshTimer?.cancel();
    _lobbyRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!_connected || _busy) {
        return;
      }

      final api = _api;
      if (api == null) {
        return;
      }

      try {
        final games = await api.listGames();
        final rooms = await api.listRooms();
        if (!mounted) {
          return;
        }

        setState(() {
          _games = games;
          _rooms = rooms;
          _selectedGameId = _resolveSelectedGame(games, _selectedGameId);
        });
      } catch (_) {
        // Auto refresh should be best-effort and never interrupt user actions.
      }
    });
  }

  String? _resolveSelectedGame(List<RegisteredGame> games, String? selected) {
    if (games.isEmpty) {
      return null;
    }
    if (selected != null && games.any((g) => g.id == selected)) {
      return selected;
    }
    return games.first.id;
  }

  Future<void> _createRoom() async {
    await _runTask(() async {
      final api = _api;
      if (api == null || !_connected || !_authed) {
        throw Exception('Connect and auth first');
      }
      final gameId = _selectedGameId;
      if (gameId == null || gameId.isEmpty) {
        throw Exception('No game selected');
      }
      final roomId = _roomIdCtrl.text.trim();
      if (roomId.isEmpty) {
        throw Exception('Room id is required');
      }

      await api.createRoom(room: roomId, gameId: gameId, autoJoin: _autoJoinOnCreate);
      _joinRoomCtrl.text = roomId;

      await _refreshGamesAndRooms();
      if (_autoJoinOnCreate && mounted) {
        _openRoomDetail(roomId: roomId, gameId: gameId);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _message = 'Room "$roomId" created';
      });
    });
  }

  Future<void> _joinRoom() async {
    await _runTask(() async {
      final api = _api;
      if (api == null || !_connected || !_authed) {
        throw Exception('Connect and auth first');
      }
      final roomId = _joinRoomCtrl.text.trim();
      if (roomId.isEmpty) {
        throw Exception('Room id is required');
      }

      await api.joinRoom(roomId);
      _openRoomDetail(roomId: roomId);
      setState(() {
        _message = 'Joined room "$roomId"';
      });
    });
  }

  Future<void> _leaveRoom(String roomId) async {
    await _runTask(() async {
      final api = _api;
      if (api == null || !_connected || !_authed) {
        throw Exception('Connect and auth first');
      }

      await api.leaveRoom(roomId);
      await _refreshGamesAndRooms();
      if (!mounted) {
        return;
      }
      setState(() {
        _message = 'Left room "$roomId"';
      });
    });
  }

  void _openRoomDetail({required String roomId, String? gameId}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoomDetailPage(roomId: roomId, gameId: gameId, onLeaveRoom: _leaveRoom),
      ),
    );
  }

  String _effectiveUserName(String deviceId) {
    final name = _userNameCtrl.text.trim();
    if (name.isNotEmpty) {
      return name;
    }

    final fallback = DeviceIdentity.defaultUserName(deviceId);
    _userNameCtrl.text = fallback;
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(elevation: 0, title: const Text('Boardgame Web Lobby')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF5FAF8), Color(0xFFE9F2FF)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildConnectionCard(theme),
                  const SizedBox(height: 12),
                  _buildLobbyCard(theme),
                  const SizedBox(height: 12),
                  _buildRoomCard(theme),
                  const SizedBox(height: 12),
                  _buildStatus(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionCard(ThemeData theme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Server Connection', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Socket path is fixed to /socket.io', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: _serverCtrl,
              decoration: const InputDecoration(labelText: 'Server URL', hintText: 'http://127.0.0.1:17980'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userNameCtrl,
              decoration: const InputDecoration(labelText: 'Display Name'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(onPressed: _busy ? null : _connect, child: const Text('Connect')),
                OutlinedButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect')),
                OutlinedButton(
                  onPressed: _busy || !_connected ? null : _reauthWithNewName,
                  child: const Text('Update Name'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _runTask(_refreshGamesAndRooms),
                  child: const Text('Refresh'),
                ),
                Text(_connected ? 'Connected' : 'Offline'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLobbyCard(ThemeData theme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Games', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_games.isEmpty)
              const Text('No game registered yet')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _games
                    .map(
                      (g) => ChoiceChip(
                        label: Text('${g.name} (${g.id}) ${g.minPlayers}-${g.maxPlayers}'),
                        selected: _selectedGameId == g.id,
                        onSelected: (_) {
                          setState(() {
                            _selectedGameId = g.id;
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 12),
            Text('Rooms', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_rooms.isEmpty)
              const Text('No room available')
            else
              Column(
                children: _rooms
                    .map(
                      (r) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${r.id}   game=${r.gameId}'),
                        subtitle: Text('players: ${r.playerCount}'),
                        trailing: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _joinRoomCtrl.text = r.id;
                                  _runTask(_joinRoom);
                                },
                          child: const Text('Join'),
                        ),
                        onTap: () => _openRoomDetail(roomId: r.id, gameId: r.gameId),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomCard(ThemeData theme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Room Actions', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _roomIdCtrl,
              decoration: const InputDecoration(labelText: 'Create Room ID'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _autoJoinOnCreate,
                  onChanged: _busy
                      ? null
                      : (v) {
                          setState(() {
                            _autoJoinOnCreate = v ?? true;
                          });
                        },
                ),
                const Text('Auto join after create'),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _busy ? null : _createRoom, child: const Text('Create Room')),
            const Divider(height: 24),
            TextField(
              controller: _joinRoomCtrl,
              decoration: const InputDecoration(labelText: 'Join Room ID'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _busy ? null : _joinRoom, child: const Text('Join Room')),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD5E3F7)),
      ),
      child: Text(_message, style: theme.textTheme.bodyLarge),
    );
  }
}
