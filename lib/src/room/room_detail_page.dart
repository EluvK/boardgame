import 'package:flutter/material.dart';

import '../api/lobby_api.dart';
import '../models/acquire_models.dart';

class RoomDetailPage extends StatefulWidget {
  const RoomDetailPage({
    super.key,
    required this.roomId,
    this.gameId,
    required this.userId,
    required this.api,
    required this.onLeaveRoom,
  });

  static const String routeName = '/room';

  final String roomId;
  final String? gameId;
  final String userId;
  final LobbyApi api;
  final Future<void> Function(String roomId) onLeaveRoom;

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  bool _leaving = false;
  bool _busy = false;
  String? _error;
  AcquireStateEnvelope? _latestEnvelope;
  final List<String> _activityLog = [];

  int _buyShares = 0;
  String? _buyCompany;
  int _mergeShares = 2;

  @override
  void initState() {
    super.initState();
    widget.api.addBroadcastListener(_onBroadcast);
    widget.api.addMessageListener(_onMessage);

    final latest = widget.api.latestStatePayload;
    if (latest != null && latest['type']?.toString() == 'state') {
      _applyStatePayload(latest);
    }

    _ensureRoomReady();
  }

  @override
  void dispose() {
    widget.api.removeBroadcastListener(_onBroadcast);
    widget.api.removeMessageListener(_onMessage);
    super.dispose();
  }

  Future<void> _ensureRoomReady() async {
    try {
      await widget.api.joinRoom(widget.roomId);
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
    if (payload['type']?.toString() != 'state') {
      return;
    }

    setState(() {
      _applyStatePayload(payload);
      _error = null;
    });
  }

  void _onMessage(Map<String, dynamic> payload) {
    if (!mounted) {
      return;
    }

    final ty = payload['type']?.toString() ?? 'message';
    setState(() {
      _activityLog.insert(0, '$ty: ${payload.toString()}');
      if (_activityLog.length > 30) {
        _activityLog.removeLast();
      }
    });
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
    final envelope = _latestEnvelope;
    final state = envelope?.state;
    final isMyTurn = state?.currentPlayer == widget.userId;

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
                _buildRoomStateCard(theme, envelope, state, isMyTurn),
                const SizedBox(height: 12),
                _buildActionCard(theme, state, isMyTurn),
                const SizedBox(height: 12),
                _buildHandCard(theme, state, isMyTurn),
                const SizedBox(height: 12),
                _buildPlayersCard(theme, state),
                const SizedBox(height: 12),
                _buildActivityCard(theme),
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
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Acquire Room', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('roomId: ${widget.roomId}'),
            Text('gameId: ${widget.gameId ?? '-'}'),
            Text('me: ${widget.userId}'),
            if (state != null) ...[
              const SizedBox(height: 8),
              Text('phase: ${state.phase}'),
              Text('turn: ${state.turnNo}'),
              Text('current_player: ${state.currentPlayer}'),
              Text('my_turn: $isMyTurn'),
              if (envelope != null && envelope.event.isNotEmpty) Text('last_event: ${envelope.event}'),
            ] else
              const Text('Waiting for first state snapshot...'),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red.shade700)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(ThemeData theme, AcquireStateSnapshot? state, bool isMyTurn) {
    if (state == null) {
      return const SizedBox.shrink();
    }

    final myPhase = state.phase;
    final canOperate = isMyTurn && !_busy && !_leaving;

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
            if (myPhase == 'merge_stock_decision') _buildMergeStockDecisionPanel(theme, state, canOperate),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: canOperate
                      ? () => _runAction(
                            () => widget.api.drawTile(room: widget.roomId, userId: widget.userId),
                          )
                      : null,
                  child: const Text('Draw Tile'),
                ),
                OutlinedButton(
                  onPressed: canOperate && (myPhase == 'place' || myPhase == 'buy')
                      ? () => _runAction(
                            () => widget.api.declareEnd(room: widget.roomId, userId: widget.userId),
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
                    () => widget.api.buy(
                      room: widget.roomId,
                      userId: widget.userId,
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
    final candidates = widget.api.acquireCompanyCatalog.where((c) => !active.contains(c)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose Company', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: candidates
              .map(
                (c) => ElevatedButton(
                  onPressed: canOperate
                      ? () => _runAction(
                            () => widget.api.chooseCompany(room: widget.roomId, userId: widget.userId, company: c),
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
                            () => widget.api.resolveMerge(room: widget.roomId, userId: widget.userId, survivor: s),
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

  Widget _buildMergeStockDecisionPanel(ThemeData theme, AcquireStateSnapshot state, bool canOperate) {
    final pending = state.mergeSettlement?.pending[widget.userId] ?? const <String>{};
    final companies = pending.toList()..sort();

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
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            OutlinedButton(
                              onPressed: canOperate
                                  ? () => _runAction(
                                        () => widget.api.mergeStockDecision(
                                          room: widget.roomId,
                                          userId: widget.userId,
                                          company: company,
                                          mode: 'hold',
                                        ),
                                      )
                                  : null,
                              child: const Text('Hold'),
                            ),
                            OutlinedButton(
                              onPressed: canOperate
                                  ? () => _runAction(
                                        () => widget.api.mergeStockDecision(
                                          room: widget.roomId,
                                          userId: widget.userId,
                                          company: company,
                                          mode: 'sell',
                                          shares: _mergeShares,
                                        ),
                                      )
                                  : null,
                              child: Text('Sell $_mergeShares'),
                            ),
                            OutlinedButton(
                              onPressed: canOperate
                                  ? () => _runAction(
                                        () => widget.api.mergeStockDecision(
                                          room: widget.roomId,
                                          userId: widget.userId,
                                          company: company,
                                          mode: 'trade',
                                          shares: _mergeShares,
                                        ),
                                      )
                                  : null,
                              child: Text('Trade $_mergeShares'),
                            ),
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
              onPressed: () {
                setState(() {
                  _mergeShares += 1;
                });
              },
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

    final hand = (state.playerTiles[widget.userId] ?? const <String>{}).toList()..sort();
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
                                  () => widget.api.place(room: widget.roomId, userId: widget.userId, pos: tile),
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
              final holdingText = nonZero.isEmpty
                  ? '-'
                  : nonZero.map((e) => '${e.key}:${e.value}').join(', ');
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
