import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../room/room_session.dart';
import '../data/planetx_client.dart';
import '../data/planetx_models.dart';
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
  late final PlanetXClient _client;

  PlanetXStateEnvelope? _latestState;
  final List<String> _logs = [];
  bool _busy = false;
  String? _error;
  bool _showMeetingView = false;
  int _recommendCount = 0;
  bool _canLocate = false;
  final List<String> _opLog = [];
  final List<String> _clueLog = [];
  final List<String> _meetingLog = [];
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
        _ensureMarkBuffer();
        _latestHint = _latestState?.event ?? '';
        if (_latestHint.isNotEmpty) {
          _appendLimited(_meetingLog, _latestHint);
        }
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
        if (type == 'planetx_recommend_result') {
          final result = _asMap(payload['result']);
          if (result.containsKey('count')) {
            _recommendCount = _asInt(result['count']);
          }
          if (result.containsKey('can_locate')) {
            _canLocate = result['can_locate'] == true;
          }
          _appendLimited(_clueLog, 'recommend: ${jsonEncode(result)}');
        }
        if (type == 'planetx_op_result') {
          final result = _asMap(payload['result']);
          _appendLimited(_opLog, jsonEncode(result));
          if (result.containsKey('research')) {
            _appendLimited(_clueLog, jsonEncode(result['research']));
          }
        }
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
    final sectors = _asStringList(stateMap['map_sectors']);
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
            PlanetXGameResult(stateMap: stateMap),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: PlanetXOpBar(
                busy: _busy,
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
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final mapPanel = SizedBox(
                  height: 560,
                  child: PlanetXStarMap(
                    sectors: sectors,
                    showMeetingView: _showMeetingView,
                    onToggleView: () => setState(() => _showMeetingView = !_showMeetingView),
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
  }

  void _redoMarks() {
    if (!_canRedoMarks) {
      return;
    }
    setState(() {
      _markHistoryIndex += 1;
      _sectorMarks = _cloneMarks(_markHistory[_markHistoryIndex]);
    });
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
    final tokens = stateMap['tokens'];
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

  void _appendLimited(List<String> target, String value) {
    target.insert(0, value);
    if (target.length > 40) {
      target.removeRange(40, target.length);
    }
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
