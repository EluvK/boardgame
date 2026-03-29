import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';

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
  final _roomIdCtrl = TextEditingController();
  final _joinRoomCtrl = TextEditingController(text: '');

  LobbyApi? _api;
  Timer? _lobbyRefreshTimer;
  Timer? _messageFadeTimer;
  Timer? _messageHideTimer;
  final Random _random = Random();

  bool _connected = false;
  bool _authed = false;
  bool _busy = false;
  bool _hasAttemptedAutoConnect = false;

  String _message = 'Ready';
  String _messageTone = 'info';
  bool _showTopMessage = false;
  double _topMessageOpacity = 1;
  String? _deviceId;
  DateTime? _lastLobbySyncAt;

  List<RegisteredGame> _games = const [];
  List<RoomSummary> _rooms = const [];
  String? _selectedGameId;

  @override
  void initState() {
    super.initState();
    _roomIdCtrl.text = _generateRoomCode();
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

    _scheduleAutoConnect();
  }

  void _scheduleAutoConnect() {
    if (_hasAttemptedAutoConnect) {
      return;
    }
    _hasAttemptedAutoConnect = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _connected || _busy) {
        return;
      }

      _showMessage('Preparing lobby and auto-connecting...', tone: 'info');

      _connect(autoTriggered: true);
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
    _messageFadeTimer?.cancel();
    _messageHideTimer?.cancel();
    _api?.disconnect();
    _serverCtrl.dispose();
    _userNameCtrl.dispose();
    _roomIdCtrl.dispose();
    _joinRoomCtrl.dispose();
    super.dispose();
  }

  Future<bool> _runTask(Future<void> Function() task) async {
    if (_busy) {
      return false;
    }

    setState(() {
      _busy = true;
    });

    var success = false;
    try {
      await task();
      success = true;
    } catch (e) {
      if (!mounted) {
        return false;
      }
      _showMessage('Error: $e', tone: 'error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }

    return success;
  }

  Future<void> _connect({bool autoTriggered = false}) async {
    final success = await _runTask(() async {
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
      });
      _showMessage('Connected and authenticated', tone: 'success');

      await _refreshGamesAndRooms();
    });

    if (!mounted || success || !autoTriggered) {
      return;
    }

    _showMessage('Auto-connect failed. You can adjust name and tap Connect.', tone: 'info');
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
      _lastLobbySyncAt = null;
    });
    _showMessage('Disconnected', tone: 'info');
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
      });
      _showMessage('Name updated', tone: 'success');
    });
  }

  Future<void> _saveOrApplyUserName() async {
    final deviceId = _deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      return;
    }

    final normalizedName = _effectiveUserName(deviceId);
    await LobbyPreferences.saveUserName(normalizedName);

    if (_connected && !_busy) {
      await _reauthWithNewName();
      return;
    }

    if (!mounted) {
      return;
    }

    _showMessage('Name saved', tone: 'info');
  }

  Future<void> _randomizeUserName() async {
    final prefixes = [
      'Fox',
      'Oak',
      'Nova',
      'Atlas',
      'River',
      'Pixel',
      'Comet',
      'Maple',
      'Amber',
      'Blaze',
      'Cedar',
      'Drift',
      'Echo',
      'Flint',
      'Glint',
      'Harbor',
      'Iris',
      'Jade',
      'Kite',
      'Lumen',
      'Moss',
      'Nimbus',
      'Onyx',
      'Pine',
      'Quartz',
      'Rune',
      'Sol',
      'Tide',
      'Umber',
      'Vale',
      'Wave',
      'Yonder',
      'Zephyr',
    ];
    final suffix = _random.nextInt(9000) + 1000;
    final generated = '${prefixes[_random.nextInt(prefixes.length)]}-$suffix';

    setState(() {
      _userNameCtrl.text = generated;
    });
    _showMessage('Generated a new name: $generated', tone: 'info');

    await LobbyPreferences.saveUserName(generated);

    if (_connected && !_busy) {
      await _reauthWithNewName();
    }
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
      _lastLobbySyncAt = DateTime.now();
    });
    _showMessage('Fetched ${games.length} games, ${rooms.length} rooms', tone: 'info');
  }

  void _bindLobbyPush(LobbyApi api) {
    api.setRoomsUpdatedListener((rooms) {
      if (!mounted) {
        return;
      }

      setState(() {
        _rooms = rooms;
        _lastLobbySyncAt = DateTime.now();
      });
      _showMessage('Lobby updated: ${rooms.length} rooms', tone: 'info');
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

  String _generateRoomCode() {
    final code = _random.nextInt(9000) + 1000;
    return code.toString();
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
      final requested = _roomIdCtrl.text.trim();
      final roomId = requested.isEmpty ? _generateRoomCode() : requested;

      await api.createRoom(room: roomId, gameId: gameId, autoJoin: true);
      _joinRoomCtrl.text = roomId;
      _roomIdCtrl.text = _generateRoomCode();

      await _refreshGamesAndRooms();
      if (mounted) {
        _openRoomDetail(roomId: roomId, gameId: gameId);
      }
      if (!mounted) {
        return;
      }
      _showMessage('Room "$roomId" created', tone: 'success');
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
      _showMessage('Joined room "$roomId"', tone: 'success');
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
      _showMessage('Left room "$roomId"', tone: 'info');
    });
  }

  void _openRoomDetail({required String roomId, String? gameId}) {
    final api = _api;
    final userId = _deviceId;
    if (api == null || !_connected || !_authed) {
      _showMessage('Connect and auth first', tone: 'info');
      return;
    }
    if (userId == null || userId.isEmpty) {
      _showMessage('Device ID not ready', tone: 'error');
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

  void _showMessage(String text, {String tone = 'info', bool autoHide = true}) {
    if (!mounted) {
      return;
    }

    _messageFadeTimer?.cancel();
    _messageHideTimer?.cancel();

    setState(() {
      _message = text;
      _messageTone = tone;
      _showTopMessage = true;
      _topMessageOpacity = 1;
    });

    if (!autoHide) {
      return;
    }

    _messageFadeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _topMessageOpacity = 0;
      });

      _messageHideTimer = Timer(const Duration(milliseconds: 260), () {
        if (!mounted) {
          return;
        }
        setState(() {
          _showTopMessage = false;
        });
      });
    });
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
                  _buildTopMessage(theme),
                  if (_showTopMessage) const SizedBox(height: 10),
                  _buildHero(theme, lastSyncText),
                  const SizedBox(height: 12),
                  _buildConnectionCard(theme),
                  const SizedBox(height: 12),
                  _buildLobbyCard(theme),
                  const SizedBox(height: 12),
                  _buildRoomCard(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(ThemeData theme, String lastSyncText) {
    final connected = _connected && _authed;
    final statusColor = connected ? const Color(0xFF027A48) : const Color(0xFF475467);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0D7E5)),
      ),
      child: Row(
        children: [
          Icon(connected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, size: 18, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'Connected' : 'Not connected',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: statusColor),
                ),
                Text(lastSyncText, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF667085))),
              ],
            ),
          ),
          if (_busy) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
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
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F9FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_outline, color: Color(0xFF1D4ED8)),
                      const SizedBox(width: 8),
                      Text(
                        'Display Name (auto-generated, editable)',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _userNameCtrl,
                    maxLength: 20,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    textInputAction: TextInputAction.done,
                    onEditingComplete: () {
                      FocusScope.of(context).unfocus();
                      _saveOrApplyUserName();
                    },
                    inputFormatters: [LengthLimitingTextInputFormatter(20)],
                    decoration: InputDecoration(
                      labelText: 'Your name shown to other players',
                      suffixIcon: IconButton(
                        tooltip: 'Generate random name',
                        onPressed: _busy ? null : _randomizeUserName,
                        icon: const Icon(Icons.casino_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tip: keep it short so room member lists stay readable.',
                    style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF475467)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  'Advanced: server address',
                  style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF667085)),
                ),
                subtitle: Text(
                  'Usually no change needed',
                  style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF98A2B3)),
                ),
                children: [
                  const SizedBox(height: 4),
                  TextField(
                    controller: _serverCtrl,
                    decoration: const InputDecoration(labelText: 'Server URL', hintText: 'http://127.0.0.1:17980'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          if (_connected) {
                            _disconnect();
                          } else {
                            _connect();
                          }
                        },
                  icon: Icon(_connected ? Icons.link_off : Icons.power_settings_new),
                  label: Text(_connected ? 'Disconnect' : 'Connect'),
                ),
                if (_connected)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _runTask(_refreshGamesAndRooms),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Lobby'),
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
                                  _joinRoom();
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
    Widget sectionCard({
      required IconData icon,
      required String title,
      required String subtitle,
      required List<Widget> children,
      Color tint = const Color(0xFFEAF2FF),
      Color border = const Color(0xFFD5E3F7),
    }) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: const Color(0xFF1D4ED8)),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF667085))),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
    }

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
            sectionCard(
              icon: Icons.add_home_work_outlined,
              title: 'Create Room',
              subtitle: 'Creates a room and joins it immediately.',
              children: [
                TextField(
                  controller: _roomIdCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  decoration: InputDecoration(
                    labelText: 'Room ID (optional, 4 digits)',
                    hintText: 'Leave empty to auto-generate',
                    suffixIcon: IconButton(
                      tooltip: 'Generate room ID',
                      onPressed: _busy
                          ? null
                          : () {
                              _roomIdCtrl.text = _generateRoomCode();
                            },
                      icon: const Icon(Icons.casino_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _createRoom,
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Create and Join'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            sectionCard(
              icon: Icons.login_outlined,
              title: 'Join Existing Room',
              subtitle: 'Joins a room by ID and opens its detail page.',
              tint: const Color(0xFFF8FAFC),
              border: const Color(0xFFD0D7E5),
              children: [
                TextField(
                  controller: _joinRoomCtrl,
                  decoration: const InputDecoration(labelText: 'Join Room ID'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _joinRoom,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Join Room'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopMessage(ThemeData theme) {
    if (!_showTopMessage) {
      return const SizedBox.shrink();
    }

    final isError = _messageTone == 'error' || _message.startsWith('Error:');
    final isSuccess = _messageTone == 'success';
    final bg = isError ? const Color(0xFFFEF3F2) : (isSuccess ? const Color(0xFFEAF7EF) : const Color(0xFFF8FAFC));
    final border = isError ? const Color(0xFFFDA29B) : (isSuccess ? const Color(0xFFA6D8B8) : const Color(0xFFD5E3F7));
    final fg = isError ? const Color(0xFFB42318) : (isSuccess ? const Color(0xFF027A48) : const Color(0xFF344054));

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      opacity: _topMessageOpacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
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
              child: Text(
                _message,
                style: theme.textTheme.bodyMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
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
