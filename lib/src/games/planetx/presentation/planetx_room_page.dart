import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../room/room_session.dart';
import '../data/planetx_client.dart';
import '../data/planetx_models.dart';
import '../../../utils/storage_box.dart';
import 'components/planetx_logs.dart';
import 'components/planetx_op_bar.dart';
import 'components/planetx_sections.dart';
import 'components/planetx_star_map.dart';

enum _SectorMarkMode {
  confirm,
  excluded,
}

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
  static const String _uiStateKeyPrefix = 'planetx_room_ui_state';

  late final PlanetXClient _client;

  PlanetXStateEnvelope? _latestState;
  final List<PlanetXLogEntry> _logs = [];
  bool _busy = false;
  bool _settingReady = false;
  bool _isReady = false;
  bool _roomStarted = false;
  int _readyCount = 0;
  int _playerCount = 0;
  int _minPlayers = 2;
  List<String> _readyUsers = const [];
  String? _error;
  bool _showMeetingView = false;
  double _mapRotationDegrees = 0;
  int _recommendCount = 0;
  bool _canLocate = false;
  final List<PlanetXLogEntry> _opLog = [];
  final List<PlanetXLogEntry> _clueLog = [];
  final List<PlanetXLogEntry> _meetingLog = [];
  String _latestHint = '';

  _SectorMarkMode _markMode = _SectorMarkMode.confirm;
  List<List<int>> _sectorMarks = [];
  final List<List<List<int>>> _markHistory = [];
  int _markHistoryIndex = -1;

  @override
  void initState() {
    super.initState();
    _client = PlanetXClient(api: widget.session.api);
    widget.session.api.addBroadcastListener(_onBroadcast);
    widget.session.api.addMessageListener(_onMessage);
    _restoreUiState();
    _ensureJoined();
  }

  @override
  void dispose() {
    _persistUiState();
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

    if (type == 'ready_state') {
      final readyStateRaw = payload['ready_state'];
      if (readyStateRaw is Map) {
        final prevStarted = _roomStarted;
        setState(() {
          _applyReadyPayload(_asMap(readyStateRaw));
        });

        // If room just entered started state, force a sync to avoid stale UI.
        if (!prevStarted && _roomStarted) {
          _run(
            () => _client.sync(
              room: widget.session.roomId,
              userId: widget.session.userId,
            ),
            'auto_sync_after_ready',
          );
        }
      }
      return;
    }

    if (type == 'state' && game == 'planetx') {
      setState(() {
        _latestState = PlanetXStateEnvelope.fromJson(payload);
        _roomStarted = _latestState?.state['started'] == true;
        _ensureMarkBuffer();
        _latestHint = _latestState?.event ?? '';
        _appendLimited(
          _logs,
          PlanetXLogEntry(
            time: DateTime.now(),
            type: 'state',
            actor: payload['by']?.toString() ?? '',
            summary: _latestState?.event ?? '',
            raw: jsonEncode(payload),
          ),
        );
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
        if (type == 'planetx_recommend_result') {
          final result = _asMap(payload['result']);
          if (result.containsKey('count')) {
            _recommendCount = _asInt(result['count']);
          }
          if (result.containsKey('can_locate')) {
            _canLocate = result['can_locate'] == true;
          }
          _appendLimited(
            _clueLog,
            PlanetXLogEntry(
              time: DateTime.now(),
              type: 'recommend',
              actor: payload['by']?.toString() ?? widget.session.userId,
              summary: 'count=${result['count'] ?? '-'} can_locate=${result['can_locate'] ?? '-'}',
              raw: jsonEncode(payload),
            ),
          );
        }
        if (type == 'planetx_op_result') {
          final result = _asMap(payload['result']);
          final hasMeetingPublish = result.containsKey('ready_publish') || result.containsKey('do_publish');
          _appendLimited(
            _opLog,
            PlanetXLogEntry(
              time: DateTime.now(),
              type: 'op',
              actor: payload['by']?.toString() ?? widget.session.userId,
              summary: _summarizeOperationResult(result),
              raw: jsonEncode(payload),
            ),
          );
          if (hasMeetingPublish) {
            _appendLimited(
              _meetingLog,
              PlanetXLogEntry(
                time: DateTime.now(),
                type: 'conference',
                actor: payload['by']?.toString() ?? widget.session.userId,
                summary: _summarizeOperationResult(result),
                raw: jsonEncode(payload),
              ),
            );
          }
          if (result.containsKey('research')) {
            _appendLimited(
              _clueLog,
              PlanetXLogEntry(
                time: DateTime.now(),
                type: 'research',
                actor: payload['by']?.toString() ?? widget.session.userId,
                summary: 'research clue updated',
                raw: jsonEncode(result['research']),
              ),
            );
          }
        }
        _appendLimited(
          _logs,
          PlanetXLogEntry(
            time: DateTime.now(),
            type: type,
            actor: payload['by']?.toString() ?? '',
            summary: _summarizeMessage(type, payload),
            raw: jsonEncode(payload),
          ),
        );
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
        _appendLimited(
          _logs,
          PlanetXLogEntry(
            time: DateTime.now(),
            type: 'action',
            actor: widget.session.userId,
            summary: '$label ok',
            raw: label,
          ),
        );
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
        _appendLimited(
          _logs,
          PlanetXLogEntry(
            time: DateTime.now(),
            type: 'action',
            actor: widget.session.userId,
            summary: '$label fail',
            raw: e.toString(),
          ),
        );
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

  Future<void> _setReady(bool ready) async {
    if (_busy || _settingReady || _roomStarted) {
      return;
    }

    setState(() {
      _settingReady = true;
      _error = null;
    });

    try {
      await widget.session.api.setReady(roomId: widget.session.roomId, ready: ready);
      if (!mounted) {
        return;
      }
      setState(() {
        _isReady = ready;
      });
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
          _settingReady = false;
        });
      }
    }
  }

  void _applyReadyPayload(Map<String, dynamic> readyState) {
    final users = readyState['ready_users'];
    final readyUsers = users is List ? users.map((e) => e.toString()).toList() : <String>[];
    readyUsers.sort();

    _readyUsers = readyUsers;
    _readyCount = _asInt(readyState['ready_count']);
    _playerCount = _asInt(readyState['player_count']);
    _minPlayers = _asInt(readyState['min_players']);
    _roomStarted = readyState['started'] == true;
    _isReady = _readyUsers.contains(widget.session.userId);
  }

  @override
  Widget build(BuildContext context) {
    final stateMap = _latestState?.state ?? <String, dynamic>{};
    final players = _asStringList(stateMap['players']);
    final sectors = _asStringList(stateMap['map_sectors']);
    final gameStage = stateMap['game_stage']?.toString() ?? '';
    final mapSize = _asInt(stateMap['map_type'] == 'expert' ? 18 : 12);
    final publishableTypes = _publishableTypes(stateMap);
    final availableSectorTypes = _availableSectorTypes(sectors, publishableTypes);
    final currentPlayer = _latestState?.raw['state'] is Map
        ? (_asMap(_latestState!.raw['state'])['current_player']?.toString() ?? '')
        : '';

    return Scaffold(
      appBar: AppBar(
        title: Text('Planet X · ${widget.session.roomId}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(4),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: PlanetXRoomInfos(
                roomId: widget.session.roomId,
                userId: widget.session.userId,
                currentPlayer: currentPlayer,
                players: players,
                stateMap: stateMap,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: PlanetXMessageBar(
                hint: _latestHint,
                error: _error,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildReadyBar(),
            ),
            PlanetXGameResult(stateMap: stateMap),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: PlanetXOpBar(
                busy: _busy,
                gameStage: gameStage,
                mapSize: mapSize,
                sectorTypes: availableSectorTypes,
                publishableTypes: publishableTypes,
                onSync: () => _run(
                  () => _client.sync(
                    room: widget.session.roomId,
                    userId: widget.session.userId,
                  ),
                  'sync',
                ),
                onSurvey: () => _run(
                  () => _client.sendSurvey(
                    room: widget.session.roomId,
                    userId: widget.session.userId,
                    sectorType: 'comet',
                    start: 1,
                    end: 6,
                  ),
                  'survey',
                ),
                onTarget: () => _run(
                  () => _client.sendTarget(
                    room: widget.session.roomId,
                    userId: widget.session.userId,
                    index: 1,
                  ),
                  'target',
                ),
                onResearch: () => _run(
                  () => _client.sendResearch(
                    room: widget.session.roomId,
                    userId: widget.session.userId,
                    clueIndex: 'A',
                  ),
                  'research_A',
                ),
                onLocate: (index, pre, next) => _run(
                  () => _client.sendLocate(
                    room: widget.session.roomId,
                    userId: widget.session.userId,
                    index: index,
                    pre: pre,
                    next: next,
                  ),
                  'locate',
                ),
                onReadyPublish: (tokens) => _run(
                  () => _client.sendReadyPublish(
                    room: widget.session.roomId,
                    userId: widget.session.userId,
                    sectors: tokens,
                  ),
                  'ready_publish',
                ),
                onDoPublish: (index, sectorType) => _run(
                  () => _client.sendDoPublish(
                    room: widget.session.roomId,
                    userId: widget.session.userId,
                    index: index,
                    sectorType: sectorType,
                  ),
                  'do_publish',
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final mapPanel = SizedBox(
                  height: 560,
                  child: PlanetXStarMap(
                    sectors: sectors,
                    showMeetingView: _showMeetingView,
                    onToggleView: () {
                      setState(() => _showMeetingView = !_showMeetingView);
                      _persistUiState();
                    },
                    rotationDegrees: _mapRotationDegrees,
                    onRotateCenter: () {
                      setState(() {
                        _mapRotationDegrees = (_mapRotationDegrees + 90) % 360;
                      });
                      _persistUiState();
                    },
                    recommendCount: _recommendCount,
                    canLocate: _canLocate,
                    onRecommendCount: () => _run(
                      () => _client.recommendCount(
                        room: widget.session.roomId,
                        userId: widget.session.userId,
                      ),
                      'recommend_count',
                    ),
                    onRecommendCanLocate: () => _run(
                      () => _client.recommendCanLocate(
                        room: widget.session.roomId,
                        userId: widget.session.userId,
                      ),
                      'recommend_can_locate',
                    ),
                    busy: _busy,
                    markModeConfirm: _markMode == _SectorMarkMode.confirm,
                    onMarkModeChanged: (confirmMode) {
                      setState(() {
                        _markMode = confirmMode ? _SectorMarkMode.confirm : _SectorMarkMode.excluded;
                      });
                      _persistUiState();
                    },
                    canUndo: _canUndoMarks,
                    canRedo: _canRedoMarks,
                    onUndo: _undoMarks,
                    onRedo: _redoMarks,
                    historyText: '${_markHistoryIndex + 1} / ${_markHistory.length}',
                    onMarkTap: _onMarkTap,
                    sectorMarks: _sectorMarks,
                    tokensCount: _countTokensInState(),
                    othersCount: _countOthersInState(),
                  ),
                );
                final logsPanel = PlanetXLogsPanel(
                  currentUserId: widget.session.userId,
                  opLog: _opLog,
                  clueLog: _clueLog,
                  meetingLog: _meetingLog,
                );

                if (constraints.maxWidth > 1000) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 40, child: mapPanel),
                      Flexible(flex: 60, child: logsPanel),
                    ],
                  );
                }

                return Column(
                  children: [
                    mapPanel,
                    logsPanel,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _ensureMarkBuffer() {
    final sectors = _asStringList(_latestState?.state['map_sectors']);
    if (sectors.isEmpty) {
      return;
    }
    if (_sectorMarks.length == sectors.length) {
      return;
    }
    _sectorMarks = List.generate(sectors.length, (_) => List<int>.filled(6, 0));
    _markHistory
      ..clear()
      ..add(_cloneMarks(_sectorMarks));
    _markHistoryIndex = 0;
    _persistUiState();
  }

  void _onMarkTap(int sectorIndex, int slotIndex) {
    if (sectorIndex < 0 || sectorIndex >= _sectorMarks.length) {
      return;
    }
    _pushMarkHistory();

    setState(() {
      if (_markMode == _SectorMarkMode.confirm) {
        for (int i = 0; i < 6; i++) {
          _sectorMarks[sectorIndex][i] = 2;
        }
        _sectorMarks[sectorIndex][slotIndex] = 1;
      } else {
        _sectorMarks[sectorIndex][slotIndex] = _sectorMarks[sectorIndex][slotIndex] == 1 ? 2 : 1;
      }
    });
    _persistUiState();
  }

  bool get _canUndoMarks => _markHistoryIndex > 0;

  bool get _canRedoMarks => _markHistoryIndex >= 0 && _markHistoryIndex < _markHistory.length - 1;

  void _undoMarks() {
    if (!_canUndoMarks) {
      return;
    }
    setState(() {
      _markHistoryIndex -= 1;
      _sectorMarks = _cloneMarks(_markHistory[_markHistoryIndex]);
    });
    _persistUiState();
  }

  void _redoMarks() {
    if (!_canRedoMarks) {
      return;
    }
    setState(() {
      _markHistoryIndex += 1;
      _sectorMarks = _cloneMarks(_markHistory[_markHistoryIndex]);
    });
    _persistUiState();
  }

  void _pushMarkHistory() {
    if (_markHistoryIndex < _markHistory.length - 1) {
      _markHistory.removeRange(_markHistoryIndex + 1, _markHistory.length);
    }
    _markHistory.add(_cloneMarks(_sectorMarks));
    _markHistoryIndex = _markHistory.length - 1;
  }

  List<List<int>> _cloneMarks(List<List<int>> marks) {
    return marks.map((row) => List<int>.from(row)).toList();
  }

  int _countTokensInState() {
    final stateMap = _latestState?.state ?? <String, dynamic>{};
    final userTokensById = _asMap(stateMap['user_tokens']);
    final tokens = userTokensById[widget.session.userId];
    if (tokens is List) {
      return tokens.length;
    }
    return 0;
  }

  int _countOthersInState() {
    final stateMap = _latestState?.state ?? <String, dynamic>{};
    final players = _asStringList(stateMap['players']);
    return players.length > 1 ? players.length - 1 : 0;
  }

  void _appendLimited(List<PlanetXLogEntry> target, PlanetXLogEntry value) {
    target.insert(0, value);
    if (target.length > 40) {
      target.removeRange(40, target.length);
    }
  }

  String _summarizeOperationResult(Map<String, dynamic> result) {
    if (result.containsKey('survey')) {
      return 'survey=${result['survey']}';
    }
    if (result.containsKey('target')) {
      return 'target=${result['target']}';
    }
    if (result.containsKey('research')) {
      return 'research';
    }
    if (result.containsKey('locate')) {
      return 'locate=${result['locate']}';
    }
    if (result.containsKey('ready_publish')) {
      return 'ready_publish=${result['ready_publish']}';
    }
    if (result.containsKey('do_publish')) {
      return 'do_publish';
    }
    return 'operation';
  }

  String _summarizeMessage(String type, Map<String, dynamic> payload) {
    if (type == 'planetx_op_result') {
      final result = _asMap(payload['result']);
      return _summarizeOperationResult(result);
    }
    if (type == 'planetx_recommend_result') {
      final result = _asMap(payload['result']);
      return 'recommend ${result.keys.join('/')}';
    }
    return type;
  }

  Widget _buildReadyBar() {
    final waitingReady = !_roomStarted;
    final readyText = 'ready $_readyCount/${_playerCount == 0 ? '-' : _playerCount} (min $_minPlayers)';
    final readyUsersText = _readyUsers.isEmpty ? '-' : _readyUsers.join(', ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: waitingReady ? const Color(0xFFFFF5E6) : const Color(0xFFEAF7EF),
        border: Border.all(
          color: waitingReady ? const Color(0xFFB26A00) : const Color(0xFF1E7D39),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  waitingReady ? 'WAIT_READY' : 'STARTED',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: waitingReady ? const Color(0xFFB26A00) : const Color(0xFF1E7D39),
                  ),
                ),
                const SizedBox(height: 2),
                Text(readyText, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 2),
                Text('users: $readyUsersText', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: _busy || _settingReady || _roomStarted ? null : () => _setReady(!_isReady),
            child: Text(
              _roomStarted
                  ? 'Game Started'
                  : (_settingReady ? 'Updating...' : (_isReady ? 'Cancel Ready' : 'Ready')),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _publishableTypes(Map<String, dynamic> stateMap) {
    final userTokensById = _asMap(stateMap['user_tokens']);
    final currentUserTokensRaw = userTokensById[widget.session.userId];
    if (currentUserTokensRaw is! List) {
      return const <String>[];
    }

    final result = <String>{};
    for (final item in currentUserTokensRaw) {
      if (item is! Map) {
        continue;
      }
      final token = _asMap(item);
      final placed = token['placed'] == true;
      if (placed) {
        continue;
      }
      final ty = token['type']?.toString();
      if (ty == null || ty.isEmpty) {
        continue;
      }
      result.add(ty);
    }
    return result.toList()..sort();
  }

  List<String> _availableSectorTypes(List<String> sectors, List<String> publishableTypes) {
    final result = <String>{};
    for (final s in sectors) {
      if (s != 'x' && s != 'space') {
        result.add(s);
      }
    }
    result.addAll(publishableTypes);
    if (result.isEmpty) {
      return ['comet', 'asteroid', 'dwarf_planet', 'nebula'];
    }
    return result.toList()..sort();
  }

  String _uiStateKey() {
    return '$_uiStateKeyPrefix:${widget.session.roomId}:${widget.session.userId}';
  }

  void _restoreUiState() {
    final raw = StorageBox.box.read<dynamic>(_uiStateKey());
    if (raw is! Map) {
      return;
    }
    final map = _asMap(raw);

    _showMeetingView = map['show_meeting_view'] == true;
    _mapRotationDegrees = _asInt(map['map_rotation_degrees']).toDouble();

    final mode = map['mark_mode']?.toString();
    if (mode == 'excluded') {
      _markMode = _SectorMarkMode.excluded;
    }

    final marksRaw = map['sector_marks'];
    final marks = _parseMarks(marksRaw);
    if (marks.isNotEmpty) {
      _sectorMarks = marks;
    }

    final historyRaw = map['mark_history'];
    final history = _parseMarkHistory(historyRaw);
    if (history.isNotEmpty) {
      _markHistory
        ..clear()
        ..addAll(history.map(_cloneMarks));
      final idx = _asInt(map['mark_history_index']);
      _markHistoryIndex = idx.clamp(0, _markHistory.length - 1);
      _sectorMarks = _cloneMarks(_markHistory[_markHistoryIndex]);
    }
  }

  void _persistUiState() {
    final markHistoryIndex = _markHistoryIndex < 0 ? 0 : _markHistoryIndex;
    final payload = {
      'show_meeting_view': _showMeetingView,
      'map_rotation_degrees': _mapRotationDegrees,
      'mark_mode': _markMode == _SectorMarkMode.confirm ? 'confirm' : 'excluded',
      'sector_marks': _sectorMarks,
      'mark_history': _markHistory,
      'mark_history_index': markHistoryIndex,
    };
    StorageBox.box.write(_uiStateKey(), payload);
  }

  List<List<int>> _parseMarks(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    final parsed = <List<int>>[];
    for (final row in raw) {
      if (row is! List) {
        continue;
      }
      parsed.add(row.map((e) => _asInt(e)).toList());
    }
    return parsed;
  }

  List<List<List<int>>> _parseMarkHistory(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    final parsed = <List<List<int>>>[];
    for (final snapshot in raw) {
      final marks = _parseMarks(snapshot);
      if (marks.isNotEmpty) {
        parsed.add(marks);
      }
    }
    return parsed;
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

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}
