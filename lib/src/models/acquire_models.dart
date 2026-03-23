class AcquireCompanyState {
  AcquireCompanyState({
    required this.id,
    required this.tiles,
    required this.safe,
  });

  final String id;
  final Set<String> tiles;
  final bool safe;

  factory AcquireCompanyState.fromJson(Map<String, dynamic> json) {
    return AcquireCompanyState(
      id: json['id']?.toString() ?? '',
      tiles: _asStringSet(json['tiles']),
      safe: json['safe'] == true,
    );
  }
}

class AcquireMergeContext {
  AcquireMergeContext({
    required this.placedPos,
    required this.candidates,
    required this.allowedSurvivors,
  });

  final String placedPos;
  final List<String> candidates;
  final List<String> allowedSurvivors;

  factory AcquireMergeContext.fromJson(Map<String, dynamic> json) {
    return AcquireMergeContext(
      placedPos: json['placed_pos']?.toString() ?? '',
      candidates: _asStringList(json['candidates']),
      allowedSurvivors: _asStringList(json['allowed_survivors']),
    );
  }
}

class AcquireMergeSettlement {
  AcquireMergeSettlement({
    required this.placedPos,
    required this.candidates,
    required this.survivor,
    required this.losers,
    required this.pending,
  });

  final String placedPos;
  final List<String> candidates;
  final String survivor;
  final List<String> losers;
  final Map<String, Set<String>> pending;

  factory AcquireMergeSettlement.fromJson(Map<String, dynamic> json) {
    final pendingMap = <String, Set<String>>{};
    final raw = json['pending'];
    if (raw is Map) {
      raw.forEach((key, value) {
        pendingMap[key.toString()] = _asStringSet(value);
      });
    }

    return AcquireMergeSettlement(
      placedPos: json['placed_pos']?.toString() ?? '',
      candidates: _asStringList(json['candidates']),
      survivor: json['survivor']?.toString() ?? '',
      losers: _asStringList(json['losers']),
      pending: pendingMap,
    );
  }
}

class AcquireFoundingContext {
  AcquireFoundingContext({required this.tiles});

  final List<String> tiles;

  factory AcquireFoundingContext.fromJson(Map<String, dynamic> json) {
    return AcquireFoundingContext(tiles: _asStringList(json['tiles']));
  }
}

class AcquireFinalStanding {
  AcquireFinalStanding({
    required this.userId,
    required this.cash,
  });

  final String userId;
  final int cash;

  factory AcquireFinalStanding.fromJson(Map<String, dynamic> json) {
    return AcquireFinalStanding(
      userId: json['user_id']?.toString() ?? '',
      cash: _parseInt(json['cash']),
    );
  }
}

class AcquireStateSnapshot {
  AcquireStateSnapshot({
    required this.tiles,
    required this.players,
    required this.shares,
    required this.stockPool,
    required this.playerTiles,
    required this.companies,
    required this.currentPlayer,
    required this.phase,
    required this.turnNo,
    required this.gameOver,
    required this.finalStandings,
    required this.mergeContext,
    required this.mergeSettlement,
    required this.foundingContext,
  });

  final Set<String> tiles;
  final Map<String, int> players;
  final Map<String, Map<String, int>> shares;
  final Map<String, int> stockPool;
  final Map<String, Set<String>> playerTiles;
  final Map<String, AcquireCompanyState> companies;
  final String currentPlayer;
  final String phase;
  final int turnNo;
  final bool gameOver;
  final List<AcquireFinalStanding> finalStandings;
  final AcquireMergeContext? mergeContext;
  final AcquireMergeSettlement? mergeSettlement;
  final AcquireFoundingContext? foundingContext;

  bool get canOperate => currentPlayer.isNotEmpty;

  factory AcquireStateSnapshot.fromJson(Map<String, dynamic> json) {
    final rawPlayers = _asMap(json['players']);
    final players = <String, int>{
      for (final entry in rawPlayers.entries) entry.key: _parseInt(entry.value),
    };

    final rawShares = _asMap(json['shares']);
    final shares = <String, Map<String, int>>{};
    for (final entry in rawShares.entries) {
      final inner = _asMap(entry.value);
      shares[entry.key] = {
        for (final i in inner.entries) i.key: _parseInt(i.value),
      };
    }

    final rawStockPool = _asMap(json['stock_pool']);
    final stockPool = <String, int>{
      for (final entry in rawStockPool.entries) entry.key: _parseInt(entry.value),
    };

    final rawPlayerTiles = _asMap(json['player_tiles']);
    final playerTiles = <String, Set<String>>{};
    for (final entry in rawPlayerTiles.entries) {
      playerTiles[entry.key] = _asStringSet(entry.value);
    }

    final rawCompanies = _asMap(json['companies']);
    final companies = <String, AcquireCompanyState>{};
    for (final entry in rawCompanies.entries) {
      final companyJson = _asMap(entry.value);
      companies[entry.key] = AcquireCompanyState.fromJson(companyJson);
    }

    final mergeContextJson = _asMapOrNull(json['merge_context']);
    final mergeSettlementJson = _asMapOrNull(json['merge_settlement']);
    final foundingContextJson = _asMapOrNull(json['founding_context']);

    return AcquireStateSnapshot(
      tiles: _asStringSet(json['tiles']),
      players: players,
      shares: shares,
      stockPool: stockPool,
      playerTiles: playerTiles,
      companies: companies,
      currentPlayer: json['current_player']?.toString() ?? '',
      phase: json['phase']?.toString() ?? '',
      turnNo: _parseInt(json['turn_no']),
      gameOver: json['game_over'] == true,
      finalStandings: _asMapList(json['final_standings']).map(AcquireFinalStanding.fromJson).toList(),
      mergeContext: mergeContextJson == null ? null : AcquireMergeContext.fromJson(mergeContextJson),
      mergeSettlement:
          mergeSettlementJson == null ? null : AcquireMergeSettlement.fromJson(mergeSettlementJson),
      foundingContext:
          foundingContextJson == null ? null : AcquireFoundingContext.fromJson(foundingContextJson),
    );
  }
}

class AcquireStateEnvelope {
  AcquireStateEnvelope({
    required this.state,
    required this.event,
    required this.by,
    required this.placement,
    required this.company,
    required this.survivor,
    required this.raw,
  });

  final AcquireStateSnapshot state;
  final String event;
  final String? by;
  final String? placement;
  final String? company;
  final String? survivor;
  final Map<String, dynamic> raw;

  factory AcquireStateEnvelope.fromJson(Map<String, dynamic> json) {
    final stateJson = _asMap(json['state']);
    return AcquireStateEnvelope(
      state: AcquireStateSnapshot.fromJson(stateJson),
      event: json['event']?.toString() ?? '',
      by: json['by']?.toString(),
      placement: json['placement']?.toString(),
      company: json['company']?.toString(),
      survivor: json['survivor']?.toString(),
      raw: json,
    );
  }
}

int _parseInt(dynamic value) {
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

Map<String, dynamic> _asMap(dynamic data) {
  if (data is Map<String, dynamic>) {
    return data;
  }
  if (data is Map) {
    return data.map((k, v) => MapEntry(k.toString(), v));
  }
  return <String, dynamic>{};
}

Map<String, dynamic>? _asMapOrNull(dynamic data) {
  if (data == null) {
    return null;
  }
  final map = _asMap(data);
  return map.isEmpty ? null : map;
}

List<Map<String, dynamic>> _asMapList(dynamic data) {
  if (data is! List) {
    return const [];
  }
  return data.map(_asMap).toList();
}

List<String> _asStringList(dynamic data) {
  if (data is! List) {
    return const [];
  }
  return data.map((e) => e.toString()).toList();
}

Set<String> _asStringSet(dynamic data) {
  return _asStringList(data).toSet();
}
