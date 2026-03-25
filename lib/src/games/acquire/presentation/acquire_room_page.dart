import 'package:flutter/material.dart';

import '../../../room/room_session.dart';
import '../data/acquire_client.dart';
import '../data/acquire_models.dart';

class AcquireRoomPage extends StatefulWidget {
  const AcquireRoomPage({super.key, required this.session});

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
  final List<_ActivityEntry> _activityLog = [];

  final Map<String, int> _buyPlan = {};
  int _mergeShares = 2;
  String? _pinnedTile;
  String? _pinnedCompanyId;
  String? _lastAutoPassBuyKey;
  bool? _roomStateCollapsed = false;
  bool? _roomStateAutoCollapsed = false;
  final Map<String, String> _playerNamesById = {};

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

  String? get _activeInfoTile => _pinnedTile;

  String? get _activeInfoCompanyId => _pinnedCompanyId;

  void _pinBoardInfo(String tile, String? companyId) {
    setState(() {
      _pinnedTile = tile;
      _pinnedCompanyId = companyId;
    });
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
      if (type == 'room_context') {
        _mergePlayerNamesMap(payload['player_names']);
        _error = null;
      } else if (type == 'state') {
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
      if (ty == 'room_context') {
        _mergePlayerNamesMap(payload['player_names']);
      } else if (ty == 'ready_state') {
        _applyReadyPayload(payload);
      }
      _appendActivityFromMessage(payload);
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
    final nextRoomStarted = readyState['started'] == true;
    if (nextRoomStarted && !_roomStarted && !(_roomStateAutoCollapsed ?? false)) {
      _roomStateCollapsed = true;
      _roomStateAutoCollapsed = true;
    }
    _roomStarted = nextRoomStarted;
    _isReady = _readyUsers.contains(widget.session.userId);
  }

  void _mergePlayerNamesMap(dynamic rawMap) {
    if (rawMap is! Map) {
      return;
    }

    for (final entry in rawMap.entries) {
      final id = entry.key.toString().trim();
      final name = entry.value?.toString().trim() ?? '';
      if (id.isNotEmpty && name.isNotEmpty) {
        _playerNamesById[id] = name;
      }
    }
  }

  String _playerDisplayName(String uid) {
    final mapped = _playerNamesById[uid]?.trim();
    if (mapped != null && mapped.isNotEmpty) {
      return mapped;
    }
    return uid;
  }

  void _applyStatePayload(Map<String, dynamic> payload) {
    _latestEnvelope = AcquireStateEnvelope.fromJson(payload);
    final envelope = _latestEnvelope;
    if (envelope != null) {
      _appendActivityFromEnvelope(envelope);
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

  void _appendActivity(_ActivityEntry entry) {
    _activityLog.insert(0, entry);
    if (_activityLog.length > 40) {
      _activityLog.removeLast();
    }
  }

  void _appendActivityFromMessage(Map<String, dynamic> payload) {
    final ty = payload['type']?.toString() ?? '';
    if (ty == 'buy_ok') {
      final user = payload['user']?.toString();
      final purchasesRaw = payload['purchases'];
      final purchases = purchasesRaw is List ? purchasesRaw : const <dynamic>[];
      final buyLines = <String>[];
      final companies = <String>[];

      for (final item in purchases) {
        if (item is! Map) {
          continue;
        }
        final company = item['company']?.toString() ?? '';
        final shares = _asInt(item['shares']);
        if (company.isEmpty || shares <= 0) {
          continue;
        }
        companies.add(company);
        buyLines.add('$company x$shares');
      }

      _appendActivity(
        _ActivityEntry(
          action: buyLines.isEmpty ? '跳过买股' : '买入股票',
          userId: user,
          companies: companies,
          cost: _asInt(payload['cost']),
          detail: buyLines.isEmpty ? null : buyLines.join('，'),
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    if (ty == 'draw_tile_ok') {
      final user = payload['user']?.toString();
      final tile = payload['tile']?.toString() ?? '';
      final remaining = _asInt(payload['remaining']);
      _appendActivity(
        _ActivityEntry(
          action: '抽牌',
          userId: user,
          companies: const <String>[],
          detail: tile.isEmpty ? null : '抽到 $tile，牌堆剩余 $remaining',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    if (ty == 'ready_state') {
      final readyStateRaw = payload['ready_state'];
      final readyState = readyStateRaw is Map ? readyStateRaw : const <dynamic, dynamic>{};
      _appendActivity(
        _ActivityEntry(
          action: '准备状态更新',
          companies: const <String>[],
          detail: '${_asInt(readyState['ready_count'])}/${_asInt(readyState['player_count'])} ready',
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  void _appendActivityFromEnvelope(AcquireStateEnvelope envelope) {
    final event = envelope.event.trim();
    if (event.isEmpty || event == 'turn_advanced') {
      return;
    }

    final raw = envelope.raw;
    final companies = <String>[];
    final primaryCompany = envelope.company?.trim() ?? '';
    if (primaryCompany.isNotEmpty) {
      companies.add(primaryCompany);
    }
    final survivor = envelope.survivor?.trim() ?? '';
    if (survivor.isNotEmpty && !companies.contains(survivor)) {
      companies.add(survivor);
    }

    String? detail;
    int? cost;

    final placement = envelope.placement?.trim() ?? '';
    if (placement.isNotEmpty) {
      detail = '位置: $placement';
      if (placement.startsWith('expand:')) {
        final expandedCompany = placement.substring('expand:'.length).trim();
        if (expandedCompany.isNotEmpty && !companies.contains(expandedCompany)) {
          companies.add(expandedCompany);
        }
      } else if (placement.startsWith('merge:')) {
        final mergedCompany = placement.substring('merge:'.length).trim();
        if (mergedCompany.isNotEmpty && !companies.contains(mergedCompany)) {
          companies.add(mergedCompany);
        }
      } else if (placement.startsWith('merge_pending_stock:')) {
        final pendingCompany = placement.substring('merge_pending_stock:'.length).trim();
        if (pendingCompany.isNotEmpty && !companies.contains(pendingCompany)) {
          companies.add(pendingCompany);
        }
      }
    }

    if (event == 'shares_sold') {
      final soldShares = _asInt(raw['sold_shares']);
      final soldCash = _asInt(raw['sold_cash']);
      if (soldShares > 0) {
        detail = '卖出 $soldShares 股';
      }
      if (soldCash > 0) {
        cost = -soldCash;
      }
    } else if (event == 'shares_converted') {
      final oldShares = _asInt(raw['traded_old_shares']);
      final newShares = _asInt(raw['traded_new_shares']);
      if (oldShares > 0 && newShares > 0) {
        detail = '换股 $oldShares -> $newShares';
      }
    } else if (event == 'final_scored') {
      final winner = raw['winner']?.toString() ?? '';
      if (winner.isNotEmpty) {
        detail = '胜者: ${_playerDisplayName(winner)}';
      }
    }

    _appendActivity(
      _ActivityEntry(
        action: _eventLabel(event),
        userId: envelope.by,
        companies: companies,
        cost: cost,
        detail: detail,
        createdAt: DateTime.now(),
      ),
    );
  }

  String _eventLabel(String event) {
    switch (event) {
      case 'place_ok':
        return '落子';
      case 'company_expanded':
        return '扩张公司';
      case 'choose_company_required':
        return '等待选择公司';
      case 'company_founded':
        return '创办公司';
      case 'merge_pending':
        return '触发并购';
      case 'merge_resolved':
        return '确定并购幸存公司';
      case 'merge_stock_decision_required':
        return '等待并购换股决策';
      case 'merge_stock_decision_applied':
        return '完成并购换股决策';
      case 'shares_sold':
        return '卖出并购股票';
      case 'shares_converted':
        return '并购换股';
      case 'merge_finalized':
        return '并购结算完成';
      case 'bonus_paid':
        return '并购奖励发放';
      case 'end_declared':
        return '宣布结束游戏';
      case 'final_scored':
        return '最终结算';
      case 'game_started':
        return '游戏开始';
      default:
        return event;
    }
  }

  Color _playerAccentColor(String userId) {
    return _AcquirePalette.playerColor(userId);
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
        () => _client.buy(room: widget.session.roomId, userId: widget.session.userId, purchases: const <String, int>{}),
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
    final canActNow =
        state != null &&
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
                _buildRoomControlBar(),
                const SizedBox(height: 8),
                if (!(_roomStateCollapsed ?? false))
                  _buildRoomStateCard(theme, envelope, state, isMyTurn, canActNow, myPendingMergeCompanies),
                const SizedBox(height: 8),
                _buildTurnHintBar(theme, state, isMyTurn, canActNow, myPendingMergeCompanies),
                const SizedBox(height: 12),
                _buildWorkspace(theme, state, isMyTurn, canActNow, myPendingMergeCompanies),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomControlBar() {
    final collapsed = _roomStateCollapsed ?? false;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _roomStateCollapsed = !(_roomStateCollapsed ?? false);
            });
          },
          icon: Icon(collapsed ? Icons.unfold_more : Icons.unfold_less),
          label: Text(collapsed ? 'Expand Room State' : 'Collapse Room State'),
        ),
        OutlinedButton(
          onPressed: _leaving || _busy || _settingReady || _roomStarted ? null : () => _setReady(!_isReady),
          child: Text(
            _roomStarted
                ? 'Game Started'
                : (_settingReady ? 'Updating Ready...' : (_isReady ? 'Cancel Ready' : 'Ready')),
          ),
        ),
        ElevatedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Back to Lobby')),
        OutlinedButton(
          onPressed: _leaving || _busy ? null : _leaveRoom,
          child: Text(_leaving ? 'Leaving...' : 'Leave Room'),
        ),
      ],
    );
  }

  Widget _buildTurnHintBar(
    ThemeData theme,
    AcquireStateSnapshot? state,
    bool isMyTurn,
    bool canActNow,
    List<String> myPendingMergeCompanies,
  ) {
    String message;
    Color bg;
    Color border;
    Color fg;
    IconData icon;

    if (_busy) {
      message = 'Submitting action...';
      bg = const Color(0xFFEFF4FF);
      border = const Color(0xFFBFD2FF);
      fg = const Color(0xFF1D4ED8);
      icon = Icons.hourglass_top_rounded;
    } else if (!_roomStarted) {
      message = 'Waiting for all players to be ready.';
      bg = const Color(0xFFFFF7E8);
      border = const Color(0xFFF1D39A);
      fg = const Color(0xFF9A6700);
      icon = Icons.group_outlined;
    } else if (state == null) {
      message = 'Waiting for latest game state...';
      bg = const Color(0xFFF8FAFC);
      border = const Color(0xFFD0D7E5);
      fg = const Color(0xFF475467);
      icon = Icons.sync;
    } else if (state.phase == 'merge_stock_decision' && myPendingMergeCompanies.isNotEmpty) {
      message = 'Your turn to decide merge stocks: ${myPendingMergeCompanies.join(', ')}.';
      bg = const Color(0xFFE7F9F8);
      border = const Color(0xFF9EDFD9);
      fg = const Color(0xFF0B7A75);
      icon = Icons.priority_high_rounded;
    } else if (canActNow && isMyTurn) {
      message = switch (state.phase) {
        'place' => 'Your turn: place a tile from your hand.',
        'buy' => 'Your turn: buy up to 3 shares.',
        'choose_company' => 'Your turn: choose a company to found.',
        'resolve_merge' => 'Your turn: choose the surviving company.',
        _ => 'Your turn: proceed with the current action.',
      };
      bg = const Color(0xFFE7F9F8);
      border = const Color(0xFF9EDFD9);
      fg = const Color(0xFF0B7A75);
      icon = Icons.play_circle_outline;
    } else {
      if (state.phase == 'merge_stock_decision') {
        final pendingUsers =
            (state.mergeSettlement?.pending.entries
                      .where((entry) => entry.value.isNotEmpty)
                      .map((entry) => entry.key)
                      .toList() ??
                  <String>[])
              ..sort();
        final target = pendingUsers.isEmpty ? 'pending players' : pendingUsers.join(', ');
        message = 'Waiting for $target to decide merge stocks.';
      } else {
        message = switch (state.phase) {
          'place' => 'Waiting for ${state.currentPlayer} to place a tile.',
          'buy' => 'Waiting for ${state.currentPlayer} to complete buy step.',
          'choose_company' => 'Waiting for ${state.currentPlayer} to choose a company.',
          'resolve_merge' => 'Waiting for ${state.currentPlayer} to resolve merge.',
          _ => 'Waiting for ${state.currentPlayer} to act.',
        };
      }
      bg = const Color(0xFFF8FAFC);
      border = const Color(0xFFD0D7E5);
      fg = const Color(0xFF475467);
      icon = Icons.schedule;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: fg, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
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
    final canPlace = state != null && _roomStarted && isMyTurn && state.phase == 'place' && !_busy && !_leaving;
    final activeTile = _activeInfoTile;
    final activeCompanyId = _activeInfoCompanyId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Board', style: theme.textTheme.titleLarge),
                if (state != null) Text('placed=${state.tiles.length}', style: theme.textTheme.bodySmall),
                if (activeTile != null)
                  Text(
                    'selected_tile=$activeTile',
                    style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF344054)),
                  ),
                if (activeCompanyId != null && state?.companies.containsKey(activeCompanyId) == true)
                  Text(
                    'selected_company=$activeCompanyId (${state!.companies[activeCompanyId]!.tiles.length} tiles)',
                    style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF0A7E8C)),
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
              AspectRatio(aspectRatio: 12 / 9, child: _buildBoardGrid(state, canPlace)),
            if (state != null) ...[
              const SizedBox(height: 10),
              Text(
                'Tip: click tile to show info below.',
                style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF667085)),
              ),
              if (activeTile != null || activeCompanyId != null) ...[
                const SizedBox(height: 8),
                _buildBoardInfoPanel(theme, state, activeTile, activeCompanyId),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBoardInfoPanel(ThemeData theme, AcquireStateSnapshot state, String? tile, String? companyId) {
    final company = companyId == null ? null : state.companies[companyId];
    final tiles = company == null ? <String>[] : (company.tiles.toList()..sort(_compareBoardPos));
    final color = companyId == null ? const Color(0xFF64748B) : _companyColor(companyId);
    final stockPool = companyId == null ? null : (state.stockPool[companyId] ?? 0);
    final unitPrice = companyId == null ? null : _companySharePrice(state, companyId);
    final tileInHand = tile == null
        ? null
        : ((state.playerTiles[widget.session.userId] ?? const <String>{}).contains(tile));
    final title = companyId ?? tile ?? 'Board Info';
    final tilePreview = tiles.length <= 8 ? tiles.join(', ') : '${tiles.take(8).join(', ')} ... +${tiles.length - 8}';

    Widget infoChip(String label, String value, {Color? tint}) {
      final fg = tint ?? const Color(0xFF334155);
      final bg = fg.withValues(alpha: 0.12);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: fg.withValues(alpha: 0.3)),
        ),
        child: Text(
          '$label $value',
          style: theme.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.75), width: 1.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (tile != null && companyId != null) infoChip('Tile', tile),
              if (tileInHand == true) infoChip('In Hand', 'Yes', tint: const Color(0xFF0A7E8C)),
            ],
          ),
          if (companyId != null && company != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                infoChip('Size', '${tiles.length}', tint: color),
                infoChip('Safe', company.safe ? 'Yes' : 'No', tint: company.safe ? const Color(0xFF027A48) : null),
                if (stockPool != null) infoChip('Pool', '$stockPool'),
                if (unitPrice != null) infoChip('Price', '$unitPrice'),
              ],
            ),
          ],
          if (tiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              tilePreview,
              style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF334155), fontWeight: FontWeight.w600),
            ),
          ],
        ],
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
        final company = companyId == null ? null : state.companies[companyId];
        final inHand = hand.contains(pos);
        final activeCompanyId = _activeInfoCompanyId;
        final activeTile = _activeInfoTile;
        final isCompanyHover = companyId != null && activeCompanyId != null && companyId == activeCompanyId;
        final isTileHover = activeTile == pos;

        final color = companyId == null
            ? (isPlaced
                  ? (isTileHover ? const Color(0xFFD6DFEC) : const Color(0xFFE5E7EB))
                  : (isTileHover ? const Color(0xFFF3F4F6) : Colors.white))
            : _companyColor(companyId).withValues(alpha: isCompanyHover ? 0.62 : 0.42);
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
        final companyBorderColor = _companyColor(companyId ?? '').withValues(alpha: isCompanyHover ? 1 : 0.95);
        final borderColor = companyId == null ? defaultBorderColor : companyBorderColor;
        final borderWidth = isCompanyHover ? 1.8 : 1.0;

        final border = Border(
          left: sameLeft ? BorderSide.none : BorderSide(color: borderColor, width: borderWidth),
          right: sameRight ? BorderSide.none : BorderSide(color: borderColor, width: borderWidth),
          top: sameUp ? BorderSide.none : BorderSide(color: borderColor, width: borderWidth),
          bottom: sameDown ? BorderSide.none : BorderSide(color: borderColor, width: borderWidth),
        );

        final radius = Radius.circular(companyId == null ? 6 : 3);
        final borderRadius = BorderRadius.only(
          topLeft: (!sameLeft && !sameUp) ? radius : Radius.zero,
          topRight: (!sameRight && !sameUp) ? radius : Radius.zero,
          bottomLeft: (!sameLeft && !sameDown) ? radius : Radius.zero,
          bottomRight: (!sameRight && !sameDown) ? radius : Radius.zero,
        );

        return Material(
          color: color,
          borderRadius: borderRadius,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: () {
              _pinBoardInfo(pos, companyId);
              if (canPlace && inHand) {
                _runAction(() => _client.place(room: widget.session.roomId, userId: widget.session.userId, pos: pos));
              }
            },
            child: Container(
              decoration: BoxDecoration(
                border: border,
                borderRadius: borderRadius,
                boxShadow: isCompanyHover
                    ? [
                        BoxShadow(
                          color: _companyColor(companyId).withValues(alpha: 0.24),
                          blurRadius: 3,
                          spreadRadius: 0.4,
                        ),
                      ]
                    : null,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 40;
                  final posFontSize = compact ? 8.6 : 11.2;
                  final badgePadding = compact
                      ? const EdgeInsets.symmetric(horizontal: 2.4, vertical: 1.4)
                      : const EdgeInsets.symmetric(horizontal: 4.8, vertical: 1.8);
                  final badgeMaxWidth = (constraints.maxWidth - (compact ? 1 : 3)).clamp(12.0, 64.0);
                  final posBadgeBg = isCompanyHover
                      ? const Color(0xFFE2E8F0).withValues(alpha: 0.96)
                      : const Color(0xFFE5E7EB).withValues(alpha: 0.92);
                  const posBadgeFg = Color(0xFF1F2937);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (companyId != null && !compact)
                        Positioned(
                          right: compact ? 1 : 2,
                          bottom: compact ? 1 : 2,
                          child: Container(
                            padding: badgePadding,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: isCompanyHover ? 0.32 : 0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              companyId[0],
                              style: TextStyle(fontSize: compact ? 8.0 : 9.0, fontWeight: FontWeight.w700, color: fg),
                            ),
                          ),
                        ),
                      if (inHand)
                        Positioned(
                          right: compact ? 1 : 2,
                          top: compact ? 1 : 2,
                          child: Container(
                            width: compact ? 11 : 14,
                            height: compact ? 11 : 14,
                            decoration: BoxDecoration(
                              color: canPlace ? const Color(0xFF0A7E8C) : const Color(0xFF334155),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.78), width: 0.7),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.14),
                                  blurRadius: 1.2,
                                  offset: const Offset(0, 0.6),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: compact ? 8.0 : 10.0,
                              color: const Color(0xFFF8FAFC),
                            ),
                          ),
                        ),
                      Positioned(
                        left: compact ? 1 : 2,
                        top: compact ? 1 : 2,
                        child: Container(
                          padding: badgePadding,
                          constraints: BoxConstraints(
                            minWidth: compact ? 12 : 15,
                            minHeight: compact ? 10 : 12,
                            maxWidth: badgeMaxWidth,
                          ),
                          decoration: BoxDecoration(
                            color: posBadgeBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.36), width: 0.7),
                          ),
                          child: Text(
                            pos,
                            maxLines: 1,
                            softWrap: false,
                            // overflow: TextOverflow.fade,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: posFontSize,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: posBadgeFg,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
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
            if (myPendingMergeCompanies.isNotEmpty) 'pending_merge_decisions: ${myPendingMergeCompanies.join(', ')}',
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
                  Text('Game will start when all players are ready.', style: theme.textTheme.bodySmall),
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

  Widget _buildStateHighlights(ThemeData theme, AcquireStateSnapshot? state, bool isMyTurn, bool canActNow) {
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
        _buildStatusChip(label: 'PHASE: $phase', bgColor: const Color(0xFFEFF4FF), fgColor: const Color(0xFF1D4ED8)),
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

  Widget _buildStatusChip({required String label, required Color bgColor, required Color fgColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fgColor.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fgColor),
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
          ...lines.map((line) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(line))),
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
            if (myPhase == 'choose_company' && isMyTurn) _buildChooseCompanyPanel(theme, state, canOperate),
            if (myPhase == 'resolve_merge' && isMyTurn) _buildResolveMergePanel(theme, state, canOperate),
            if (myPhase == 'merge_stock_decision' && myPendingMergeCompanies.isNotEmpty)
              _buildMergeStockDecisionPanel(theme, state, canOperate, myPendingMergeCompanies),
            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 2),
            const SizedBox(height: 10),
            Text(
              'Quick Actions',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF344054)),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD0D7E5)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: canOperate && isMyTurn && myHandSize < 6
                        ? () => _runAction(
                            () => _client.drawTile(room: widget.session.roomId, userId: widget.session.userId),
                          )
                        : null,
                    child: const Text('Draw Tile'),
                  ),
                  OutlinedButton(
                    onPressed: canOperate && isMyTurn && (myPhase == 'place' || myPhase == 'buy')
                        ? () => _runAction(
                            () => _client.declareEnd(room: widget.session.roomId, userId: widget.session.userId),
                          )
                        : null,
                    child: const Text('Declare End'),
                  ),
                ],
              ),
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
    final selectedSummary = _buyPlan.entries.where((e) => e.value > 0).map((e) => '${e.key} x${e.value}').toList();

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
        Row(children: [Text('Buy Shares', style: theme.textTheme.titleMedium)]),
        const SizedBox(height: 6),
        Text(
          '当前现金 \$$myCash  -  消耗现金 \$$estimatedCost  =  剩余现金 \$$estimatedAfterCash',
          style: theme.textTheme.titleSmall?.copyWith(
            color: insufficientCash ? const Color(0xFFB42318) : const Color(0xFF027A48),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        ...purchasable.map((company) {
          final pool = state.stockPool[company] ?? 0;
          final myHolding = (state.shares[widget.session.userId] ?? const <String, int>{})[company] ?? 0;
          final current = _buyPlan[company] ?? 0;
          final maxForCompany = pool.clamp(0, 3);
          final unitPrice = _companySharePrice(state, company);
          final canIncrease = canOperate && canAddMore && current < maxForCompany;
          final canDecrease = canOperate && current > 0;
          final allInTarget = maxForCompany;
          final canAllIn = canOperate && allInTarget > 0;
          final tint = _companyColor(company);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.08),
              border: Border.all(color: tint.withValues(alpha: 0.36)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        company,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '\$$unitPrice',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      '剩余 $pool 股',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF334155),
                      ),
                    ),
                    Text(
                      '已持有 $myHolding 股',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF475467),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
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
                    Container(
                      width: 34,
                      alignment: Alignment.center,
                      child: Text('$current', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
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
                    const SizedBox(width: 4),
                    OutlinedButton(
                      onPressed: canAllIn
                          ? () {
                              setState(() {
                                _buyPlan
                                  ..clear()
                                  ..[company] = allInTarget;
                              });
                            }
                          : null,
                      child: const Text('ALL IN'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        if (selectedSummary.isNotEmpty || insufficientCash)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD0D7E5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selectedSummary.isNotEmpty)
                  Text(
                    selectedSummary.join(', '),
                    style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF475467)),
                  ),
                if (selectedSummary.isNotEmpty && insufficientCash) const SizedBox(height: 6),
                if (insufficientCash)
                  Text(
                    'Not enough cash for current selection.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFB42318),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: canOperate && totalPlanned > 0
                  ? () {
                      setState(_buyPlan.clear);
                    }
                  : null,
              child: const Text('Clear'),
            ),
            const Spacer(),
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
        ),
      ],
    );
  }

  Widget _buildChooseCompanyPanel(ThemeData theme, AcquireStateSnapshot state, bool canOperate) {
    final active = state.companies.keys.toSet();
    final candidates = AcquireClient.companyCatalog.where((c) => !active.contains(c)).toList()
      ..sort((a, b) {
        final tierCmp = _companyTier(a).compareTo(_companyTier(b));
        if (tierCmp != 0) {
          return tierCmp;
        }
        return a.compareTo(b);
      });
    final foundingTiles = (state.foundingContext?.tiles ?? const <String>[])..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose Company', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (foundingTiles.isNotEmpty)
          Text(
            'Founding tiles: ${foundingTiles.join(', ')}',
            style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF475467), fontWeight: FontWeight.w600),
          ),
        if (foundingTiles.isNotEmpty) const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: candidates.map((c) {
            final tint = _companyColor(c);
            final tier = _companyTier(c);
            return ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: tint.withValues(alpha: 0.18),
                foregroundColor: const Color(0xFF0F172A),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: tint.withValues(alpha: 0.62), width: 1.1),
                ),
              ),
              onPressed: canOperate
                  ? () => _runAction(
                      () =>
                          _client.chooseCompany(room: widget.session.roomId, userId: widget.session.userId, company: c),
                    )
                  : null,
              icon: Icon(Icons.circle, size: 12, color: tint),
              label: Text('$c  L$tier', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            );
          }).toList(),
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
                              final maxTradeShares = holding - (holding % 2);
                              final canSell = canOperate && holding > 0;
                              final canTrade = canOperate && maxTradeShares >= 2;
                              final sellShares = canSell ? _mergeShares.clamp(1, holding) : 0;
                              final tradeShares = canTrade ? _mergeShares.clamp(2, maxTradeShares) : 0;

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

    Widget metricChip(String label, String value, {Color? tint}) {
      final bg = (tint ?? const Color(0xFF64748B)).withValues(alpha: 0.12);
      final fg = tint ?? const Color(0xFF334155);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: fg.withValues(alpha: 0.28)),
        ),
        child: Text(
          '$label $value',
          style: theme.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
        ),
      );
    }

    Widget companyHoldingChip(String company, int shares) {
      final tint = _companyColor(company);
      final bg = tint.withValues(alpha: 0.22);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tint.withValues(alpha: 0.62)),
        ),
        child: Text(
          '$company $shares',
          style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFF111827), fontWeight: FontWeight.w800),
        ),
      );
    }

    Widget playerChip(String uid) {
      final color = _playerAccentColor(uid);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          _playerDisplayName(uid),
          style: theme.textTheme.labelMedium?.copyWith(color: const Color(0xFF111827), fontWeight: FontWeight.w800),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Players', style: theme.textTheme.titleLarge),
                const Spacer(),
                metricChip('count', '${players.length}'),
              ],
            ),
            const SizedBox(height: 8),
            ...players.map((entry) {
              final uid = entry.key;
              final displayName = _playerDisplayName(uid);
              final cash = entry.value;
              final holding = state.shares[uid] ?? const <String, int>{};
              final nonZero = holding.entries.where((e) => e.value > 0).toList()
                ..sort((a, b) => a.key.compareTo(b.key));
              final isMe = uid == widget.session.userId;
              final isTurn = state.currentPlayer == uid;
              final playerColor = _playerAccentColor(uid);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isTurn
                        ? const Color(0xFFE8F7F5)
                        : (isMe ? const Color(0xFFF4F7FF) : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isTurn ? const Color(0xFF0B7A75).withValues(alpha: 0.45) : const Color(0xFFD0D7E5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 22,
                            decoration: BoxDecoration(color: playerColor, borderRadius: BorderRadius.circular(99)),
                          ),
                          const SizedBox(width: 8),
                          playerChip(uid),
                          const SizedBox(width: 8),
                          // Expanded(
                          //   child: Text(
                          //     displayName,
                          //     style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                          //   ),
                          // ),
                          if (isMe)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1D4ED8).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'ME',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: const Color(0xFF1D4ED8),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          if (isTurn)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0B7A75).withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'TURN',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: const Color(0xFF0B7A75),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '\$$cash',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF027A48),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (nonZero.isEmpty) metricChip('holding', '-'),
                          ...nonZero.map((e) => companyHoldingChip(e.key, e.value)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (state.gameOver && state.finalStandings.isNotEmpty) ...[
              const Divider(height: 24),
              Text('Final Standings', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              ...state.finalStandings.asMap().entries.map((entry) {
                final rank = entry.key + 1;
                final f = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      metricChip('#', '$rank', tint: const Color(0xFF7C3AED)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(f.userId, style: theme.textTheme.bodyMedium)),
                      metricChip('cash', '${f.cash}', tint: const Color(0xFF027A48)),
                    ],
                  ),
                );
              }),
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
    final safeCount = companies.where((e) => e.value.safe).length;

    Widget metricChip(String label, String value, {Color? tint}) {
      final bg = (tint ?? const Color(0xFF64748B)).withValues(alpha: 0.12);
      final fg = tint ?? const Color(0xFF334155);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: fg.withValues(alpha: 0.28)),
        ),
        child: Text(
          '$label $value',
          style: theme.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
        ),
      );
    }

    Widget companyIdChip(String id) {
      final tint = _companyColor(id);
      final bg = tint.withValues(alpha: 0.22);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tint.withValues(alpha: 0.62)),
        ),
        child: Text(
          id,
          style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFF111827), fontWeight: FontWeight.w800),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Companies', style: theme.textTheme.titleLarge),
                const Spacer(),
                metricChip('active', '${companies.length}'),
                const SizedBox(width: 6),
                metricChip('safe', '$safeCount', tint: const Color(0xFF0F766E)),
              ],
            ),
            const SizedBox(height: 8),
            if (companies.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD0D7E5)),
                ),
                child: Text('No active companies.', style: theme.textTheme.bodyMedium),
              ),
            if (companies.isNotEmpty)
              ...companies.map((entry) {
                final id = entry.key;
                final company = entry.value;
                final pool = state.stockPool[id] ?? 0;
                final size = company.tiles.length;
                final price = _companySharePrice(state, id);
                final color = _companyColor(id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withValues(alpha: 0.45)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(id, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            ),
                            if (company.safe)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'SAFE',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: const Color(0xFF0F766E),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            metricChip('size', '$size', tint: color),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '\$$price',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '剩余 $pool 股',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            if (state.mergeContext != null) ...[
              const Divider(height: 24),
              Text('Merge Context', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  metricChip('placed', state.mergeContext!.placedPos),
                  metricChip('candidates', '${state.mergeContext!.candidates.length}'),
                  metricChip('survivors', '${state.mergeContext!.allowedSurvivors.length}'),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: state.mergeContext!.candidates.map(companyIdChip).toList()),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: state.mergeContext!.allowedSurvivors.map(companyIdChip).toList(),
              ),
            ],
            if (state.mergeSettlement != null) ...[
              const Divider(height: 24),
              Text('Merge Settlement', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  metricChip(
                    'survivor',
                    state.mergeSettlement!.survivor,
                    tint: _companyColor(state.mergeSettlement!.survivor),
                  ),
                  metricChip('losers', '${state.mergeSettlement!.losers.length}'),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: state.mergeSettlement!.losers.map(companyIdChip).toList()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard(ThemeData theme) {
    Widget playerChip(String userId) {
      final color = _playerAccentColor(userId);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          _playerDisplayName(userId),
          style: theme.textTheme.labelMedium?.copyWith(color: const Color(0xFF111827), fontWeight: FontWeight.w800),
        ),
      );
    }

    Widget companyChip(String company) {
      final bg = _companyColor(company);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(999)),
        child: Text(
          company,
          style: theme.textTheme.labelMedium?.copyWith(color: const Color(0xFF111827), fontWeight: FontWeight.w800),
        ),
      );
    }

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
                    final item = _activityLog[index];
                    final time = item.createdAt;
                    final hh = time.hour.toString().padLeft(2, '0');
                    final mm = time.minute.toString().padLeft(2, '0');
                    final ss = time.second.toString().padLeft(2, '0');

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFD0D7E5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '$hh:$mm:$ss',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: const Color(0xFF667085),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              if (item.cost != null)
                                Text(
                                  item.cost! < 0 ? '+\$${-item.cost!}' : '-\$${item.cost}',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: item.cost! < 0 ? const Color(0xFF027A48) : const Color(0xFFB42318),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (item.userId != null && item.userId!.isNotEmpty) playerChip(item.userId!),
                              Text(
                                item.action,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              ...item.companies.map(companyChip),
                            ],
                          ),
                          if (item.detail != null && item.detail!.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.detail!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF475467),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
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

class _ActivityEntry {
  const _ActivityEntry({
    required this.action,
    required this.companies,
    required this.createdAt,
    this.userId,
    this.cost,
    this.detail,
  });

  final String action;
  final String? userId;
  final int? cost;
  final List<String> companies;
  final String? detail;
  final DateTime createdAt;
}

Color _companyColor(String company) {
  return _AcquirePalette.companyColor(company);
}

class _AcquirePalette {
  static const Color fallbackCompany = Color(0xFF9AA4B2);

  static const Map<String, Color> companyColors = <String, Color>{
    'Sackson': Color(0xFFE3B341),
    'Worldwide': Color(0xFF5B8FF9),
    'American': Color(0xFFE67E22),
    'Festival': Color(0xFF16A085),
    'Imperial': Color(0xFFD35454),
    'Continental': Color(0xFF8E5BBE),
    'Tower': Color(0xFF4E9F6D),
  };

  static const List<Color> playerColors = <Color>[
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ];

  static Color companyColor(String company) {
    return companyColors[company] ?? fallbackCompany;
  }

  static Color playerColor(String userId) {
    if (userId.isEmpty) {
      return playerColors.first;
    }
    final hash = userId.codeUnits.fold<int>(0, (sum, c) => (sum * 31 + c) & 0x7fffffff);
    return playerColors[hash % playerColors.length];
  }
}

int _compareBoardPos(String a, String b) {
  final pa = _parseBoardPos(a);
  final pb = _parseBoardPos(b);
  if (pa == null || pb == null) {
    return a.compareTo(b);
  }
  if (pa.rowIndex != pb.rowIndex) {
    return pa.rowIndex.compareTo(pb.rowIndex);
  }
  return pa.col.compareTo(pb.col);
}

_BoardPos? _parseBoardPos(String pos) {
  final match = RegExp(r'^(\d+)([A-Z])$').firstMatch(pos);
  if (match == null) {
    return null;
  }
  final col = int.tryParse(match.group(1) ?? '');
  final rowLetter = match.group(2);
  if (col == null || rowLetter == null || rowLetter.isEmpty) {
    return null;
  }
  return _BoardPos(col: col, rowIndex: rowLetter.codeUnitAt(0) - 'A'.codeUnitAt(0));
}

class _BoardPos {
  const _BoardPos({required this.col, required this.rowIndex});

  final int col;
  final int rowIndex;
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

int _companyTier(String companyId) {
  return switch (companyId) {
    'Worldwide' || 'Sackson' => 1,
    'American' || 'Festival' || 'Imperial' => 2,
    'Continental' || 'Tower' => 3,
    _ => 1,
  };
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

  final tier = _companyTier(companyId) - 1;

  return base + tier * 100;
}
