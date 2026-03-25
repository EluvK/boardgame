import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  static const String _serverUrlFromDefine = String.fromEnvironment('LOBBY_SERVER_URL', defaultValue: '');
  static const String _debugDefaultServerUrl = 'http://127.0.0.1:17980';
  static const String _releaseDefaultServerUrl = 'https://your-production-server.example.com';

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
  String _messageTone = 'info';
  String? _deviceId;
  DateTime? _lastLobbySyncAt;

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
      _serverCtrl.text = _resolveInitialServerUrl(profile.serverUrl);
    });
  }

  String _resolveInitialServerUrl(String? savedServerUrl) {
    final fromDefine = _serverUrlFromDefine.trim();
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }

    final saved = savedServerUrl?.trim() ?? '';
    if (saved.isNotEmpty) {
      return saved;
    }

    return kReleaseMode ? _releaseDefaultServerUrl : _debugDefaultServerUrl;
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
        _messageTone = 'error';
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
        _messageTone = 'success';
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
      _messageTone = 'info';
      _lastLobbySyncAt = null;
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
        _messageTone = 'success';
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
      _messageTone = 'info';
      _lastLobbySyncAt = DateTime.now();
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
        _messageTone = 'info';
        _lastLobbySyncAt = DateTime.now();
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
          _lastLobbySyncAt = DateTime.now();
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
        _messageTone = 'success';
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
      final resolvedGameId = _rooms
          .where((r) => r.id == roomId)
          .map((r) => r.gameId)
          .cast<String?>()
          .firstWhere((id) => id != null && id.isNotEmpty, orElse: () => _selectedGameId);
      _openRoomDetail(roomId: roomId, gameId: resolvedGameId);
      setState(() {
        _message = 'Joined room "$roomId"';
        _messageTone = 'success';
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
        _messageTone = 'info';
      });
    });
  }

  void _openRoomDetail({required String roomId, String? gameId}) {
    final api = _api;
    final userId = _deviceId;
    if (api == null || !_connected || !_authed) {
      setState(() {
        _message = 'Connect and auth first';
      });
      return;
    }
    if (userId == null || userId.isEmpty) {
      setState(() {
        _message = 'Device ID not ready';
      });
      return;
    }

    final resolvedGameId =
        gameId ??
        _rooms
            .where((r) => r.id == roomId)
            .map((r) => r.gameId)
            .cast<String?>()
            .firstWhere((id) => id != null && id.isNotEmpty, orElse: () => null);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RoomDetailPage(roomId: roomId, gameId: resolvedGameId, userId: userId, api: api, onLeaveRoom: _leaveRoom),
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
    final lastSync = _lastLobbySyncAt;
    final lastSyncText = lastSync == null
        ? 'Not synced yet'
        : 'Updated ${lastSync.hour.toString().padLeft(2, '0')}:${lastSync.minute.toString().padLeft(2, '0')}:${lastSync.second.toString().padLeft(2, '0')}';

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
                  _buildHero(theme, lastSyncText),
                  const SizedBox(height: 12),
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

  Widget _buildHero(ThemeData theme, String lastSyncText) {
    Widget statusPill(String label, bool active, {Color? activeColor}) {
      final color = activeColor ?? const Color(0xFF1769AA);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.16) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? color.withValues(alpha: 0.45) : const Color(0xFFD1D5DB)),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: active ? color : const Color(0xFF475467),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE7F5FF), Color(0xFFEFFAF5)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFD8F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lobby Control Center', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              statusPill('1. Connected', _connected, activeColor: const Color(0xFF1D4ED8)),
              statusPill('2. Authenticated', _authed, activeColor: const Color(0xFF0F766E)),
              statusPill('3. Ready to Play', _connected && _authed, activeColor: const Color(0xFF027A48)),
            ],
          ),
          const SizedBox(height: 8),
          Text(lastSyncText, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF475467))),
        ],
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
            // const SizedBox(height: 4),
            // Text('Socket path is fixed to /socket.io', style: theme.textTheme.bodySmall),
            // const SizedBox(height: 2),
            // Text('Override: --dart-define=LOBBY_SERVER_URL=...', style: theme.textTheme.bodySmall),
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
                ElevatedButton.icon(
                  onPressed: _busy ? null : _connect,
                  icon: const Icon(Icons.power_settings_new),
                  label: Text(_connected ? 'Reconnect' : 'Connect'),
                ),
                OutlinedButton(onPressed: _busy ? null : _disconnect, child: const Text('Disconnect')),
                OutlinedButton(
                  onPressed: _busy || !_connected ? null : _reauthWithNewName,
                  child: const Text('Update Name'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _runTask(_refreshGamesAndRooms),
                  child: const Text('Refresh'),
                ),
                Text(
                  _connected ? (_authed ? 'Online + Authed' : 'Online') : 'Offline',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _connected ? const Color(0xFF027A48) : const Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD0D7E5)),
                ),
                child: const Text('No room available. Create one to get started.'),
              )
            else
              Column(
                children: _rooms.map((r) {
                  final playerCount = r.playerCount;
                  final crowded = playerCount >= 4;
                  final accent = crowded ? const Color(0xFFB42318) : const Color(0xFF027A48);
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD0D7E5)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _openRoomDetail(roomId: r.id, gameId: r.gameId),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.id, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _buildMiniTag('game', r.gameId),
                                    _buildMiniTag('players', '$playerCount', tint: accent),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _joinRoomCtrl.text = r.id;
                                  _runTask(_joinRoom);
                                },
                          child: const Text('Join'),
                        ),
                      ],
                    ),
                  );
                }).toList(),
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
            ElevatedButton.icon(
              onPressed: _busy ? null : _createRoom,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Create Room'),
            ),
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
    final isError = _messageTone == 'error' || _message.startsWith('Error:');
    final isSuccess = _messageTone == 'success';
    final bg = isError ? const Color(0xFFFEF3F2) : (isSuccess ? const Color(0xFFEAF7EF) : const Color(0xFFF8FAFC));
    final border = isError ? const Color(0xFFFDA29B) : (isSuccess ? const Color(0xFFA6D8B8) : const Color(0xFFD5E3F7));
    final fg = isError ? const Color(0xFFB42318) : (isSuccess ? const Color(0xFF027A48) : const Color(0xFF344054));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : (isSuccess ? Icons.check_circle_outline : Icons.info_outline),
            color: fg,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_message, style: theme.textTheme.bodyLarge?.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniTag(String label, String value, {Color? tint}) {
    final fg = tint ?? const Color(0xFF475467);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
