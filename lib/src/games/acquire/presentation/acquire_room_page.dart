import 'package:flutter/material.dart';

import '../../../room/room_session.dart';
import '../data/acquire_client.dart';
import '../data/acquire_models.dart';

class AcquireRoomPage extends StatefulWidget {
  const AcquireRoomPage({
    super.key,
    required this.session,
  });

  final RoomSession session;

  @override
  State<AcquireRoomPage> createState() => _AcquireRoomPageState();
}

class _AcquireRoomPageState extends State<AcquireRoomPage> {
  late final AcquireClient _client;
  bool _leaving = false;
  bool _busy = false;
  bool _settingReady = false;
  bool _isReady = false;
  bool _roomStarted = false;
  int _readyCount = 0;
  int _playerCount = 0;
  int _minPlayers = 2;
  List<String> _readyUsers = const [];
  String? _error;
  AcquireStateEnvelope? _latestEnvelope;
  final List<String> _activityLog = [];

  final Map<String, int> _buyPlan = {};
  int _mergeShares = 2;
  String? _hoveredTile;
  String? _lastAutoPassBuyKey;

  @override
  void initState() {
    super.initState();
    _client = AcquireClient(api: widget.session.api);
    widget.session.api.addBroadcastListener(_onBroadcast);
    widget.session.api.addMessageListener(_onMessage);

    final latest = widget.session.api.latestStatePayload;
    if (latest != null && latest['type']?.toString() == 'state') {
      _applyStatePayload(latest);
    }

    _ensureRoomReady();
  }

  @override
  void dispose() {
    widget.session.api.removeBroadcastListener(_onBroadcast);
    widget.session.api.removeMessageListener(_onMessage);
    super.dispose();
  }

  Future<void> _ensureRoomReady() async {
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

    setState(() {
      final type = payload['type']?.toString() ?? '';
      if (type == 'state') {
        _applyStatePayload(payload);
        _error = null;
      } else if (type == 'ready_state') {
        _applyReadyPayload(payload);
        _error = null;
      }
    });
  }

  void _onMessage(Map<String, dynamic> payload) {
    if (!mounted) {
      return;
    }

    final ty = payload['type']?.toString() ?? 'message';
    setState(() {
      if (ty == 'ready_state') {
        _applyReadyPayload(payload);
      }
      _activityLog.insert(0, '$ty: ${payload.toString()}');
      if (_activityLog.length > 30) {
        _activityLog.removeLast();
      }
    });
  }

  void _applyReadyPayload(Map<String, dynamic> payload) {
    final readyStateRaw = payload['ready_state'];
    if (readyStateRaw is! Map) {
      return;
    }
    final readyState = readyStateRaw.map((k, v) => MapEntry(k.toString(), v));
    final users = readyState['ready_users'];
    final readyUsers = users is List ? users.map((e) => e.toString()).toList() : <String>[];
    final readyUsersSorted = [...readyUsers]..sort();

    _readyUsers = readyUsersSorted;
    _readyCount = _asInt(readyState['ready_count']);
    _playerCount = _asInt(readyState['player_count']);
    _minPlayers = _asInt(readyState['min_players']);
    _roomStarted = readyState['started'] == true;
    _isReady = _readyUsers.contains(widget.session.userId);
  }

  void _applyStatePayload(Map<String, dynamic> payload) {
    _latestEnvelope = AcquireStateEnvelope.fromJson(payload);
    final eventName = _latestEnvelope?.event;
    if (eventName != null && eventName.isNotEmpty) {
      _activityLog.insert(0, 'event=$eventName');
      if (_activityLog.length > 30) {
        _activityLog.removeLast();
      }
    }

    final state = _latestEnvelope?.state;
    if (state == null) {
      return;
    }

    if (state.phase != 'buy') {
      _buyPlan.clear();
      _lastAutoPassBuyKey = null;
      return;
    }

    final pools = state.stockPool;
    _buyPlan.removeWhere((company, shares) => (pools[company] ?? 0) <= 0 || shares <= 0);
    for (final entry in _buyPlan.entries.toList()) {
      final pool = pools[entry.key] ?? 0;
      final clamped = entry.value.clamp(0, pool);
      if (clamped <= 0) {
        _buyPlan.remove(entry.key);
      } else if (clamped != entry.value) {
        _buyPlan[entry.key] = clamped;
      }
    }

    _maybeAutoPassBuy(state);
  }

  void _maybeAutoPassBuy(AcquireStateSnapshot state) {
    if (!_roomStarted || _busy || _leaving) {
      return;
    }
    if (state.phase != 'buy' || state.currentPlayer != widget.session.userId) {
      return;
    }

    final hasPurchasable = state.companies.keys.any((c) => (state.stockPool[c] ?? 0) > 0);
    if (hasPurchasable) {
      return;
    }

    final key = '${state.turnNo}:${state.currentPlayer}:buy_pass';
    if (_lastAutoPassBuyKey == key) {
      return;
    }
    _lastAutoPassBuyKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _runAction(
        () => _client.buy(
          room: widget.session.roomId,
          userId: widget.session.userId,
          purchases: const <String, int>{},
        ),
      );
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy || _leaving) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await action();
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
          _busy = false;
        });
      }
    }
  }

  Future<void> _setReady(bool ready) async {
    if (_busy || _leaving || _settingReady) {
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

  Future<void> _leaveRoom() async {
    if (_leaving) {
      return;
    }

    setState(() {
      _leaving = true;
      _error = null;
    });

    try {
      await widget.session.onLeaveRoom(widget.session.roomId);
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
    final envelope = _latestEnvelope;
    final state = envelope?.state;
    final isMyTurn = state?.currentPlayer == widget.session.userId;
    final myPendingMergeCompanies = state == null
        ? const <String>[]
        : ((state.mergeSettlement?.pending[widget.session.userId] ?? const <String>{}).toList()..sort());
    final canActNow = state != null &&
      _roomStarted &&
        !_busy &&
        !_leaving &&
        (isMyTurn || (state.phase == 'merge_stock_decision' && myPendingMergeCompanies.isNotEmpty));

    return Scaffold(
      appBar: AppBar(title: Text('Room: ${widget.session.roomId}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRoomStateCard(theme, envelope, state, isMyTurn, canActNow, myPendingMergeCompanies),
                const SizedBox(height: 8),
                _buildRoomControlBar(),
                const SizedBox(height: 12),
                _buildWorkspace(
                  theme,
                  state,
                  isMyTurn,
                  canActNow,
                  myPendingMergeCompanies,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomControlBar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: _leaving || _busy || _settingReady || _roomStarted ? null : () => _setReady(!_isReady),
          child: Text(
            _roomStarted
                ? 'Game Started'
                : (_settingReady ? 'Updating Ready...' : (_isReady ? 'Cancel Ready' : 'Ready')),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Back to Lobby'),
        ),
        OutlinedButton(
          onPressed: _leaving || _busy ? null : _leaveRoom,
          child: Text(_leaving ? 'Leaving...' : 'Leave Room'),
        ),
      ],
    );
  }

  Widget _buildWorkspace(
    ThemeData theme,
    AcquireStateSnapshot? state,
    bool isMyTurn,
    bool canActNow,
    List<String> myPendingMergeCompanies,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 1100;

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBoardCard(theme, state, isMyTurn),
              const SizedBox(height: 12),
              _buildActionCard(theme, state, isMyTurn, canActNow, myPendingMergeCompanies),
              const SizedBox(height: 12),
              _buildHandCard(theme, state, isMyTurn),
              const SizedBox(height: 12),
              _buildCompaniesCard(theme, state),
              const SizedBox(height: 12),
              _buildPlayersCard(theme, state),
              const SizedBox(height: 12),
              SizedBox(height: 320, child: _buildActivityCard(theme)),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBoardCard(theme, state, isMyTurn),
                  const SizedBox(height: 12),
                  _buildActionCard(theme, state, isMyTurn, canActNow, myPendingMergeCompanies),
                  const SizedBox(height: 12),
                  _buildHandCard(theme, state, isMyTurn),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 360,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCompaniesCard(theme, state),
                  const SizedBox(height: 12),
                  _buildPlayersCard(theme, state),
                  const SizedBox(height: 12),
                  SizedBox(height: 300, child: _buildActivityCard(theme)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBoardCard(ThemeData theme, AcquireStateSnapshot? state, bool isMyTurn) {
    final canPlace =
        state != null && _roomStarted && isMyTurn && state.phase == 'place' && !_busy && !_leaving;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Board', style: theme.textTheme.titleLarge),
                const SizedBox(width: 8),
                if (state != null)
                  Text(
                    'placed=${state.tiles.length}',
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(width: 10),
                if (_hoveredTile != null)
                  Text(
                    'hover=$_hoveredTile',
                    style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF344054)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (state == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Waiting for state snapshot...')),
              )
            else
              AspectRatio(
                aspectRatio: 12 / 9,
                child: _buildBoardGrid(state, canPlace),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardGrid(AcquireStateSnapshot state, bool canPlace) {
    final hand = state.playerTiles[widget.session.userId] ?? const <String>{};
    final companyByTile = <String, String>{};
    for (final entry in state.companies.entries) {
      for (final tile in entry.value.tiles) {
        companyByTile[tile] = entry.key;
      }
    }

    const rows = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'];

    return GridView.builder(
      itemCount: rows.length * 12,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 12,
        crossAxisSpacing: 0,
        mainAxisSpacing: 0,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final rowIndex = index ~/ 12;
        final col = (index % 12) + 1;
        final pos = '$col${rows[rowIndex]}';

        final isPlaced = state.tiles.contains(pos);
        final companyId = companyByTile[pos];
        final inHand = hand.contains(pos);

        final color = companyId == null
            ? (isPlaced ? const Color(0xFFE5E7EB) : Colors.white)
          : _companyColor(companyId).withValues(alpha: 0.42);
        final fg = _readableTextColor(color);

        final leftPos = _boardPosOrNull(col - 1, rowIndex, rows);
        final rightPos = _boardPosOrNull(col + 1, rowIndex, rows);
        final upPos = _boardPosOrNull(col, rowIndex - 1, rows);
        final downPos = _boardPosOrNull(col, rowIndex + 1, rows);

        final sameLeft = companyId != null && leftPos != null && companyByTile[leftPos] == companyId;
        final sameRight = companyId != null && rightPos != null && companyByTile[rightPos] == companyId;
        final sameUp = companyId != null && upPos != null && companyByTile[upPos] == companyId;
        final sameDown = companyId != null && downPos != null && companyByTile[downPos] == companyId;

        final defaultBorderColor = inHand && canPlace ? const Color(0xFF0A7E8C) : const Color(0xFFD0D7E5);
        final companyBorderColor = _companyColor(companyId ?? '').withValues(alpha: 0.95);
        final borderColor = companyId == null ? defaultBorderColor : companyBorderColor;
        const borderWidth = 1.0;

        final border = Border(
          left: BorderSide(color: borderColor, width: sameLeft ? 0 : borderWidth),
          right: BorderSide(color: borderColor, width: sameRight ? 0 : borderWidth),
          top: BorderSide(color: borderColor, width: sameUp ? 0 : borderWidth),
          bottom: BorderSide(color: borderColor, width: sameDown ? 0 : borderWidth),
        );

        final radius = Radius.circular(companyId == null ? 6 : 3);
        final borderRadius = BorderRadius.only(
          topLeft: (!sameLeft && !sameUp) ? radius : Radius.zero,
          topRight: (!sameRight && !sameUp) ? radius : Radius.zero,
          bottomLeft: (!sameLeft && !sameDown) ? radius : Radius.zero,
          bottomRight: (!sameRight && !sameDown) ? radius : Radius.zero,
        );

        final tooltip = StringBuffer()
          ..writeln('tile: $pos')
          ..writeln('placed: $isPlaced')
          ..writeln('in_hand: $inHand')
          ..writeln('company: ${companyId ?? '-'}')
          ..write('can_place_now: ${canPlace && inHand}');

        return Tooltip(
          message: tooltip.toString(),
          waitDuration: const Duration(milliseconds: 120),
          child: MouseRegion(
            onEnter: (_) {
              if (!mounted) {
                return;
              }
              setState(() {
                _hoveredTile = pos;
              });
            },
            onExit: (_) {
              if (!mounted) {
                return;
              }
              setState(() {
                if (_hoveredTile == pos) {
                  _hoveredTile = null;
                }
              });
            },
            child: Material(
              color: color,
              borderRadius: borderRadius,
              child: InkWell(
                borderRadius: borderRadius,
                onTap: canPlace && inHand
                    ? () => _runAction(
                          () => _client.place(
                            room: widget.session.roomId,
                            userId: widget.session.userId,
                            pos: pos,
                          ),
                        )
                    : null,
                child: Container(
                  decoration: BoxDecoration(
                    border: border,
                    borderRadius: borderRadius,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 2,
                        top: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB).withValues(alpha: 0.94),
                            border: Border.all(color: const Color(0xFFB8C0CC), width: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            pos,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                      ),
                      if (companyId != null)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              companyId[0],
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: fg,
                              ),
                            ),
                          ),
                        ),
                      if (inHand)
                        Positioned(
                          right: 3,
                          top: 2,
                          child: Icon(Icons.circle, size: 7, color: canPlace ? const Color(0xFF0A7E8C) : fg),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoomStateCard(
    ThemeData theme,
    AcquireStateEnvelope? envelope,
    AcquireStateSnapshot? state,
    bool isMyTurn,
    bool canActNow,
    List<String> myPendingMergeCompanies,
  ) {
    final roomInfo = <String>[
      'roomId: ${widget.session.roomId}',
      'gameId: ${widget.session.gameId}',
      'me: ${widget.session.userId}',
      'room_started: $_roomStarted',
      'ready: $_readyCount/$_playerCount  (min=$_minPlayers)',
      if (_readyUsers.isNotEmpty) 'ready_users: ${_readyUsers.join(', ')}',
    ];

    final gameInfo = state == null
        ? const <String>['Waiting for first state snapshot...']
        : <String>[
            'phase: ${state.phase}',
            'turn: ${state.turnNo}',
            'current_player: ${state.currentPlayer}',
            'my_turn: $isMyTurn',
            'can_act_now: $canActNow',
            if (myPendingMergeCompanies.isNotEmpty)
              'pending_merge_decisions: ${myPendingMergeCompanies.join(', ')}',
            if (envelope != null && envelope.event.isNotEmpty) 'last_event: ${envelope.event}',
          ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final split = constraints.maxWidth >= 900;
            final roomPanel = _buildInfoPanel(theme, 'Room Info', roomInfo);
            final statePanel = _buildInfoPanel(theme, 'Game State', gameInfo);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (split)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: roomPanel),
                      const SizedBox(width: 12),
                      Expanded(child: statePanel),
                    ],
                  )
                else ...[
                  roomPanel,
                  const SizedBox(height: 10),
                  statePanel,
                ],
                const SizedBox(height: 8),
                _buildStateHighlights(theme, state, isMyTurn, canActNow),
                if (!_roomStarted) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Game will start when all players are ready.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red.shade700)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStateHighlights(
    ThemeData theme,
    AcquireStateSnapshot? state,
    bool isMyTurn,
    bool canActNow,
  ) {
    final phase = state?.phase ?? '-';
    final waitingReady = !_roomStarted;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _buildStatusChip(
          label: waitingReady ? 'WAIT_READY' : 'STARTED',
          bgColor: waitingReady ? const Color(0xFFFFF5E6) : const Color(0xFFEAF7EF),
          fgColor: waitingReady ? const Color(0xFFB26A00) : const Color(0xFF1E7D39),
        ),
        _buildStatusChip(
          label: 'PHASE: $phase',
          bgColor: const Color(0xFFEFF4FF),
          fgColor: const Color(0xFF1D4ED8),
        ),
        _buildStatusChip(
          label: isMyTurn ? 'MY TURN' : 'WAIT TURN',
          bgColor: isMyTurn ? const Color(0xFFE7F9F8) : const Color(0xFFF3F4F6),
          fgColor: isMyTurn ? const Color(0xFF0B7A75) : const Color(0xFF4B5563),
        ),
        _buildStatusChip(
          label: canActNow ? 'CAN ACT' : 'READ ONLY',
          bgColor: canActNow ? const Color(0xFFEAF7EF) : const Color(0xFFF3F4F6),
          fgColor: canActNow ? const Color(0xFF1E7D39) : const Color(0xFF4B5563),
        ),
      ],
    );
  }

  Widget _buildStatusChip({
    required String label,
    required Color bgColor,
    required Color fgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fgColor.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fgColor,
        ),
      ),
    );
  }

  Widget _buildInfoPanel(ThemeData theme, String title, List<String> lines) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        border: Border.all(color: const Color(0xFFD0D7E5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          ...lines.map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(line),
              )),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    ThemeData theme,
    AcquireStateSnapshot? state,
    bool isMyTurn,
    bool canActNow,
    List<String> myPendingMergeCompanies,
  ) {
    if (state == null) {
      return const SizedBox.shrink();
    }

    final myPhase = state.phase;
    final canOperate = canActNow;
    final myHandSize = (state.playerTiles[widget.session.userId] ?? const <String>{}).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Actions', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (myPhase == 'buy' && isMyTurn) _buildBuyPanel(theme, state, canOperate),
            if (myPhase == 'buy' && !isMyTurn)
              Text(
                'Waiting for ${state.currentPlayer} to complete buy step.',
                style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF475467)),
              ),
            if (myPhase == 'choose_company' && isMyTurn) _buildChooseCompanyPanel(theme, state, canOperate),
            if (myPhase == 'choose_company' && !isMyTurn)
              Text(
                'Waiting for ${state.currentPlayer} to choose company.',
                style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF475467)),
              ),
            if (myPhase == 'resolve_merge' && isMyTurn) _buildResolveMergePanel(theme, state, canOperate),
            if (myPhase == 'resolve_merge' && !isMyTurn)
              Text(
                'Waiting for ${state.currentPlayer} to resolve merge.',
                style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF475467)),
              ),
            if (myPhase == 'merge_stock_decision' && myPendingMergeCompanies.isNotEmpty)
              _buildMergeStockDecisionPanel(theme, state, canOperate, myPendingMergeCompanies),
            if (myPhase == 'merge_stock_decision' && myPendingMergeCompanies.isEmpty)
              Text(
                'Waiting for pending players to complete merge stock decisions.',
                style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF475467)),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: canOperate && isMyTurn && myHandSize < 6
                      ? () => _runAction(
                            () => _client.drawTile(
                              room: widget.session.roomId,
                              userId: widget.session.userId,
                            ),
                          )
                      : null,
                  child: const Text('Draw Tile'),
                ),
                OutlinedButton(
                  onPressed: canOperate && isMyTurn && (myPhase == 'place' || myPhase == 'buy')
                      ? () => _runAction(
                            () => _client.declareEnd(
                              room: widget.session.roomId,
                              userId: widget.session.userId,
                            ),
                          )
                      : null,
                  child: const Text('Declare End'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuyPanel(ThemeData theme, AcquireStateSnapshot state, bool canOperate) {
    final activeCompanies = state.companies.keys.toList()..sort();
    final purchasable = activeCompanies.where((c) => (state.stockPool[c] ?? 0) > 0).toList();
    final totalPlanned = _buyPlan.values.fold<int>(0, (sum, v) => sum + v);
    final canAddMore = totalPlanned < 3;
    final myCash = state.players[widget.session.userId] ?? 0;
    final estimatedCost = _buyPlan.entries.fold<int>(0, (sum, entry) {
      final unitPrice = _companySharePrice(state, entry.key);
      return sum + (unitPrice * entry.value);
    });
    final estimatedAfterCash = myCash - estimatedCost;
    final insufficientCash = estimatedAfterCash < 0;
    final selectedSummary = _buyPlan.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.key} x${e.value}')
        .toList();

    if (purchasable.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Buy Shares', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('No active company shares can be purchased now. Auto passing this buy step...'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Buy Shares', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...purchasable.map((company) {
          final pool = state.stockPool[company] ?? 0;
          final current = _buyPlan[company] ?? 0;
          final maxForCompany = pool.clamp(0, 3);
          final unitPrice = _companySharePrice(state, company);
          final subTotal = unitPrice * current;
          final canIncrease = canOperate && canAddMore && current < maxForCompany;
          final canDecrease = canOperate && current > 0;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD0D7E5)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('$company (pool: $pool, price: $unitPrice)'),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: canDecrease
                      ? () {
                          setState(() {
                            final next = current - 1;
                            if (next <= 0) {
                              _buyPlan.remove(company);
                            } else {
                              _buyPlan[company] = next;
                            }
                          });
                        }
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$current', style: const TextStyle(fontWeight: FontWeight.w700)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: canIncrease
                      ? () {
                          setState(() {
                            _buyPlan[company] = current + 1;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
                const SizedBox(width: 8),
                Text('= $subTotal'),
              ],
            ),
          );
        }),
        Row(
          children: [
            Expanded(
              child: Text('Total shares: $totalPlanned / 3', style: theme.textTheme.bodyMedium),
            ),
            TextButton(
              onPressed: canOperate && totalPlanned > 0
                  ? () {
                      setState(_buyPlan.clear);
                    }
                  : null,
              child: const Text('Clear'),
            ),
          ],
        ),
        if (selectedSummary.isNotEmpty)
          Text(
            'Selected: ${selectedSummary.join(', ')}',
            style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF475467)),
          ),
        const SizedBox(height: 4),
        Text('Estimated cost: $estimatedCost', style: theme.textTheme.bodySmall),
        Text(
          'Cash after buy: $estimatedAfterCash',
          style: theme.textTheme.bodySmall?.copyWith(
            color: insufficientCash ? const Color(0xFFB42318) : const Color(0xFF027A48),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (insufficientCash)
          Text(
            'Not enough cash for current selection.',
            style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFB42318)),
          ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: canOperate && !insufficientCash
              ? () => _runAction(
                    () => _client.buy(
                      room: widget.session.roomId,
                      userId: widget.session.userId,
                      purchases: {
                        for (final entry in _buyPlan.entries)
                          if (entry.value > 0) entry.key: entry.value,
                      },
                    ),
                  )
              : null,
          child: const Text('Confirm Buy'),
        ),
      ],
    );
  }

  Widget _buildChooseCompanyPanel(ThemeData theme, AcquireStateSnapshot state, bool canOperate) {
    final active = state.companies.keys.toSet();
    final candidates = AcquireClient.companyCatalog.where((c) => !active.contains(c)).toList();
    final foundingTiles = (state.foundingContext?.tiles ?? const <String>[])..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose Company', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (foundingTiles.isNotEmpty)
          Text('Founding tiles: ${foundingTiles.join(', ')}'),
        if (foundingTiles.isNotEmpty)
          const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: candidates
              .map(
                (c) => ElevatedButton(
                  onPressed: canOperate
                      ? () => _runAction(
                            () => _client.chooseCompany(
                              room: widget.session.roomId,
                              userId: widget.session.userId,
                              company: c,
                            ),
                          )
                      : null,
                  child: Text(c),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildResolveMergePanel(ThemeData theme, AcquireStateSnapshot state, bool canOperate) {
    final survivors = state.mergeContext?.allowedSurvivors ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Resolve Merge', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: survivors
              .map(
                (s) => ElevatedButton(
                  onPressed: canOperate
                      ? () => _runAction(
                            () => _client.resolveMerge(
                              room: widget.session.roomId,
                              userId: widget.session.userId,
                              survivor: s,
                            ),
                          )
                      : null,
                  child: Text('Survivor: $s'),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildMergeStockDecisionPanel(
    ThemeData theme,
    AcquireStateSnapshot state,
    bool canOperate,
    List<String> companies,
  ) {
    final holdings = state.shares[widget.session.userId] ?? const <String, int>{};
    final maxHolding = companies.fold<int>(0, (maxValue, company) {
      final holding = holdings[company] ?? 0;
      return holding > maxValue ? holding : maxValue;
    });
    final maxShareInput = maxHolding < 2 ? 2 : maxHolding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Merge Stock Decision', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (companies.isEmpty) const Text('No pending merge stock decisions for me.'),
        if (companies.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: companies
                .map(
                  (company) => Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFD0D7E5)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(company, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 6),
                        Text('holding: ${holdings[company] ?? 0}'),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ...() {
                              final holding = holdings[company] ?? 0;
                              final sellShares = _mergeShares.clamp(1, holding);
                              final maxTradeShares = holding - (holding % 2);
                              final tradeShares = _mergeShares.clamp(2, maxTradeShares);
                              final canSell = canOperate && holding > 0;
                              final canTrade = canOperate && maxTradeShares >= 2;

                              return [
                            OutlinedButton(
                              onPressed: canOperate
                                  ? () => _runAction(
                                        () => _client.mergeStockDecision(
                                          room: widget.session.roomId,
                                          userId: widget.session.userId,
                                          company: company,
                                          mode: 'hold',
                                        ),
                                      )
                                  : null,
                              child: const Text('Hold'),
                            ),
                            OutlinedButton(
                              onPressed: canSell
                                  ? () => _runAction(
                                        () => _client.mergeStockDecision(
                                          room: widget.session.roomId,
                                          userId: widget.session.userId,
                                          company: company,
                                          mode: 'sell',
                                          shares: sellShares,
                                        ),
                                      )
                                  : null,
                              child: Text('Sell $sellShares'),
                            ),
                            OutlinedButton(
                              onPressed: canTrade
                                  ? () => _runAction(
                                        () => _client.mergeStockDecision(
                                          room: widget.session.roomId,
                                          userId: widget.session.userId,
                                          company: company,
                                          mode: 'trade',
                                          shares: tradeShares,
                                        ),
                                      )
                                  : null,
                              child: Text('Trade $tradeShares'),
                            ),
                              ];
                            }(),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            Text('shares: $_mergeShares'),
            OutlinedButton(
              onPressed: _mergeShares > 1
                  ? () {
                      setState(() {
                        _mergeShares -= 1;
                      });
                    }
                  : null,
              child: const Text('-'),
            ),
            OutlinedButton(
              onPressed: _mergeShares < maxShareInput
                  ? () {
                      setState(() {
                        _mergeShares += 1;
                      });
                    }
                  : null,
              child: const Text('+'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHandCard(ThemeData theme, AcquireStateSnapshot? state, bool isMyTurn) {
    if (state == null) {
      return const SizedBox.shrink();
    }

    final hand = (state.playerTiles[widget.session.userId] ?? const <String>{}).toList()..sort();
    final canPlace = isMyTurn && state.phase == 'place' && !_busy && !_leaving;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My Hand (${hand.length})', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (hand.isEmpty) const Text('No tiles in hand.'),
            if (hand.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: hand
                    .map(
                      (tile) => ElevatedButton(
                        onPressed: canPlace
                            ? () => _runAction(
                                  () => _client.place(
                                    room: widget.session.roomId,
                                    userId: widget.session.userId,
                                    pos: tile,
                                  ),
                                )
                            : null,
                        child: Text(tile),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayersCard(ThemeData theme, AcquireStateSnapshot? state) {
    if (state == null) {
      return const SizedBox.shrink();
    }

    final players = state.players.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Players', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            ...players.map((entry) {
              final uid = entry.key;
              final cash = entry.value;
              final holding = state.shares[uid] ?? const <String, int>{};
              final nonZero = holding.entries.where((e) => e.value > 0).toList()
                ..sort((a, b) => a.key.compareTo(b.key));
              final holdingText = nonZero.isEmpty ? '-' : nonZero.map((e) => '${e.key}:${e.value}').join(', ');
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('$uid  cash=$cash  shares=[$holdingText]'),
              );
            }),
            if (state.gameOver && state.finalStandings.isNotEmpty) ...[
              const Divider(height: 24),
              Text('Final Standings', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              ...state.finalStandings.map((f) => Text('${f.userId}: ${f.cash}')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompaniesCard(ThemeData theme, AcquireStateSnapshot? state) {
    if (state == null) {
      return const SizedBox.shrink();
    }

    final companies = state.companies.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Companies', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (companies.isEmpty) const Text('No active companies.'),
            if (companies.isNotEmpty)
              ...companies.map((entry) {
                final id = entry.key;
                final company = entry.value;
                final pool = state.stockPool[id] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '$id  size=${company.tiles.length}  safe=${company.safe}  stock_pool=$pool',
                  ),
                );
              }),
            if (state.mergeContext != null) ...[
              const Divider(height: 24),
              Text('Merge Context', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('placed: ${state.mergeContext!.placedPos}'),
              Text('candidates: ${state.mergeContext!.candidates.join(', ')}'),
              Text('allowed_survivors: ${state.mergeContext!.allowedSurvivors.join(', ')}'),
            ],
            if (state.mergeSettlement != null) ...[
              const Divider(height: 24),
              Text('Merge Settlement', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('survivor: ${state.mergeSettlement!.survivor}'),
              Text('losers: ${state.mergeSettlement!.losers.join(', ')}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Activity', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_activityLog.isEmpty)
              const Text('No events yet.')
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _activityLog.length,
                  itemBuilder: (context, index) {
                    final line = _activityLog[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(line),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Color _companyColor(String company) {
  switch (company) {
    case 'Sackson':
      return const Color(0xFFE3B341);
    case 'Zeta':
      return const Color(0xFF4E9F6D);
    case 'America':
      return const Color(0xFF5B8FF9);
    case 'Fusion':
      return const Color(0xFFE67E22);
    case 'Hydra':
      return const Color(0xFF16A085);
    case 'Phoenix':
      return const Color(0xFFD35454);
    case 'Worldwide':
      return const Color(0xFF8E5BBE);
    default:
      return const Color(0xFF9AA4B2);
  }
}

String? _boardPosOrNull(int col, int rowIndex, List<String> rows) {
  if (col < 1 || col > 12) {
    return null;
  }
  if (rowIndex < 0 || rowIndex >= rows.length) {
    return null;
  }
  return '$col${rows[rowIndex]}';
}

Color _readableTextColor(Color background) {
  final luminance = background.computeLuminance();
  return luminance > 0.58 ? const Color(0xFF111827) : Colors.white;
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

int _companySharePrice(AcquireStateSnapshot state, String companyId) {
  final size = state.companies[companyId]?.tiles.length ?? 0;
  if (size < 2) {
    return 0;
  }

  final base = switch (size) {
    2 => 200,
    3 => 300,
    4 => 400,
    5 => 500,
    <= 10 => 600,
    <= 20 => 700,
    <= 30 => 800,
    <= 40 => 900,
    _ => 1000,
  };

  final tier = switch (companyId) {
    'Worldwide' || 'Sackson' => 0,
    'American' || 'Festival' || 'Imperial' => 1,
    'Continental' || 'Tower' => 2,
    _ => 0,
  };

  return base + tier * 100;
}
