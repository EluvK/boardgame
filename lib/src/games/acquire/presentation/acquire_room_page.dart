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

  int _buyShares = 0;
  String? _buyCompany;
  int _mergeShares = 2;

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
    final activeCompanies = state.companies.keys.toList()..sort();
    if (_buyCompany != null && !activeCompanies.contains(_buyCompany)) {
      _buyCompany = activeCompanies.isEmpty ? null : activeCompanies.first;
    }
    if (_buyCompany == null && activeCompanies.isNotEmpty) {
      _buyCompany = activeCompanies.first;
    }
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
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRoomStateCard(theme, envelope, state, isMyTurn, canActNow, myPendingMergeCompanies),
                const SizedBox(height: 12),
                _buildActionCard(theme, state, isMyTurn, canActNow, myPendingMergeCompanies),
                const SizedBox(height: 12),
                _buildHandCard(theme, state, isMyTurn),
                const SizedBox(height: 12),
                _buildPlayersCard(theme, state),
                const SizedBox(height: 12),
                _buildCompaniesCard(theme, state),
                const SizedBox(height: 12),
                _buildActivityCard(theme),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _leaving || _busy || _settingReady || _roomStarted
                          ? null
                          : () => _setReady(!_isReady),
                      child: Text(
                        _roomStarted
                            ? 'Game Started'
                            : (_settingReady
                                  ? 'Updating Ready...'
                                  : (_isReady ? 'Cancel Ready' : 'Ready')),
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
                ),
              ],
            ),
          ),
        ),
      ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Acquire Room', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('roomId: ${widget.session.roomId}'),
            Text('gameId: ${widget.session.gameId}'),
            Text('me: ${widget.session.userId}'),
            if (state != null) ...[
              const SizedBox(height: 8),
              Text('phase: ${state.phase}'),
              Text('turn: ${state.turnNo}'),
              Text('current_player: ${state.currentPlayer}'),
              Text('my_turn: $isMyTurn'),
              Text('can_act_now: $canActNow'),
              Text('room_started: $_roomStarted'),
              Text('ready: $_readyCount/$_playerCount  (min=$_minPlayers)'),
              if (_readyUsers.isNotEmpty) Text('ready_users: ${_readyUsers.join(', ')}'),
              if (myPendingMergeCompanies.isNotEmpty)
                Text('pending_merge_decisions: ${myPendingMergeCompanies.join(', ')}'),
              if (envelope != null && envelope.event.isNotEmpty) Text('last_event: ${envelope.event}'),
            ] else
              const Text('Waiting for first state snapshot...'),
            if (!_roomStarted)
              Text(
                'Game will start when all players are ready.',
                style: theme.textTheme.bodySmall,
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red.shade700)),
            ],
          ],
        ),
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
            if (myPhase == 'buy') _buildBuyPanel(theme, state, canOperate),
            if (myPhase == 'choose_company') _buildChooseCompanyPanel(theme, state, canOperate),
            if (myPhase == 'resolve_merge') _buildResolveMergePanel(theme, state, canOperate),
            if (myPhase == 'merge_stock_decision')
              _buildMergeStockDecisionPanel(theme, state, canOperate, myPendingMergeCompanies),
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
    final canPickCompany = _buyShares > 0 && activeCompanies.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Buy Shares', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: List<Widget>.generate(4, (i) {
            return ChoiceChip(
              label: Text('$i'),
              selected: _buyShares == i,
              onSelected: canOperate
                  ? (_) {
                      setState(() {
                        _buyShares = i;
                      });
                    }
                  : null,
            );
          }),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: canPickCompany ? _buyCompany : null,
          decoration: const InputDecoration(labelText: 'Company (required when shares > 0)'),
          items: activeCompanies
              .map(
                (c) => DropdownMenuItem<String>(
                  value: c,
                  child: Text(c),
                ),
              )
              .toList(),
          onChanged: canOperate && canPickCompany
              ? (v) {
                  setState(() {
                    _buyCompany = v;
                  });
                }
              : null,
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: canOperate && (_buyShares == 0 || (_buyCompany != null && _buyCompany!.isNotEmpty))
              ? () => _runAction(
                    () => _client.buy(
                      room: widget.session.roomId,
                      userId: widget.session.userId,
                      shares: _buyShares,
                      company: _buyShares == 0 ? null : _buyCompany,
                    ),
                  )
              : null,
          child: const Text('Submit Buy'),
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
            if (_activityLog.isEmpty) const Text('No events yet.'),
            if (_activityLog.isNotEmpty)
              ..._activityLog.map((line) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(line),
                  )),
          ],
        ),
      ),
    );
  }
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
