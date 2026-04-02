import 'package:flutter/material.dart';

class PlanetXRoomInfos extends StatelessWidget {
  const PlanetXRoomInfos({
    super.key,
    required this.roomId,
    required this.userId,
    required this.currentPlayer,
    required this.players,
    required this.playerNameById,
    required this.stateMap,
  });

  final String roomId;
  final String userId;
  final String currentPlayer;
  final List<String> players;
  final Map<String, String> playerNameById;
  final Map<String, dynamic> stateMap;

  @override
  Widget build(BuildContext context) {
    final seq = stateMap['seq']?.toString() ?? '-';
    final started = stateMap['started'] == true;
    final turnOrder = _asStringList(stateMap['turn_order']).map(_displayName).toList();
    final turnIndex = _asInt(stateMap['turn_index']);
    final mapSeed = stateMap['map_seed']?.toString() ?? '-';
    final mapType = stateMap['map_type']?.toString() ?? '-';
    final current = currentPlayer.isEmpty ? '-' : currentPlayer;
    final isMyTurn = currentPlayer.isNotEmpty && currentPlayer == userId;
    final stage = stateMap['game_stage']?.toString() ?? '';
    final phaseText = _phaseText(
      started: started,
      stage: stage,
      isMyTurn: isMyTurn,
      current: current,
    );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusChip(
                label: started ? 'STARTED' : 'WAIT_READY',
                color: started ? const Color(0xFF1E7D39) : const Color(0xFFB26A00),
              ),
              const SizedBox(width: 8),
              _statusChip(
                label: isMyTurn ? 'MY_TURN' : 'TURN_WAIT',
                color: isMyTurn ? const Color(0xFF00695C) : const Color(0xFF546E7A),
              ),
              if (stage.isNotEmpty) ...[
                const SizedBox(width: 8),
                _statusChip(
                  label: stage.toUpperCase(),
                  color: const Color(0xFF1565C0),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  phaseText,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              Text('room: $roomId'),
              Text('current: $current'),
              Text('seq: $seq'),
              Text('turn_idx: $turnIndex'),
              Text('mode: $mapType'),
              Text('seed: $mapSeed'),
            ],
          ),
          const SizedBox(height: 6),
          Text('players (${players.length}): ${players.join(', ')}'),
          if (turnOrder.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('turn order: ${turnOrder.join(' -> ')}'),
          ],
        ],
      ),
    );
  }

  String _phaseText({
    required bool started,
    required String stage,
    required bool isMyTurn,
    required String current,
  }) {
    if (!started) {
      return 'Waiting for ready/start';
    }

    switch (stage) {
      case 'meeting_proposal':
        return isMyTurn ? 'Meeting proposal: choose tokens' : 'Meeting proposal: waiting for $current';
      case 'meeting_publish':
        return isMyTurn ? 'Meeting publish: place token' : 'Meeting publish: waiting for $current';
      case 'last_move':
        return isMyTurn ? 'Last move: your final action' : 'Last move: waiting for $current';
      case 'game_end':
        return 'Game over';
      default:
        if (current == '-') {
          return 'Waiting for state sync';
        }
        return isMyTurn ? 'Your turn' : 'Waiting for $current';
    }
  }

  String _displayName(String idOrName) {
    final v = idOrName.trim();
    if (v.isEmpty) {
      return '-';
    }
    final mapped = playerNameById[v]?.trim();
    if (mapped != null && mapped.isNotEmpty) {
      return mapped;
    }
    return v;
  }
}

class PlanetXMessageBar extends StatelessWidget {
  const PlanetXMessageBar({
    super.key,
    required this.hint,
    required this.stageHint,
    required this.error,
  });

  final String hint;
  final String stageHint;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final normalizedHint = hint.trim();
    final text = error != null && error!.isNotEmpty
        ? error!
      : (normalizedHint.isNotEmpty
        ? normalizedHint
        : (stageHint.trim().isNotEmpty ? stageHint.trim() : 'Waiting for room/game state sync...'));
    final isError = error != null && error!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: isError ? const Color(0xFFB71C1C) : Colors.grey, width: 1),
        borderRadius: BorderRadius.circular(3),
        color: isError ? const Color(0xFFFFEBEE) : null,
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: isError ? const Color(0xFFB71C1C) : Colors.black,
        ),
      ),
    );
  }
}

Widget _statusChip({required String label, required Color color}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withAlpha(24),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withAlpha(80), width: 0.8),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
    ),
  );
}

class PlanetXGameResult extends StatelessWidget {
  const PlanetXGameResult({
    super.key,
    required this.stateMap,
    this.playerNameById = const <String, String>{},
  });

  final Map<String, dynamic> stateMap;
  final Map<String, String> playerNameById;

  @override
  Widget build(BuildContext context) {
    final gameResult = stateMap['game_result'];
    if (gameResult is! List || gameResult.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
        child: Table(
          border: TableBorder.all(color: Colors.grey.shade400),
          children: [
            TableRow(
              children: [
                _CellText('name', bold: true),
                _CellText('first', bold: true),
                const _HeaderIconText(asset: 'assets/icons/asteroid.png', label: 'asteroid'),
                const _HeaderIconText(asset: 'assets/icons/comet.png', label: 'comet'),
                const _HeaderIconText(asset: 'assets/icons/dwarf_planet.png', label: 'dwarf'),
                const _HeaderIconText(asset: 'assets/icons/nebula.png', label: 'nebula'),
                const _HeaderIconText(asset: 'assets/icons/x.png', label: 'x'),
                _CellText('sum', bold: true),
                _CellText('step', bold: true),
              ],
            ),
            for (final row in gameResult)
              if (row is Map)
                TableRow(
                  children: [
                    _CellText(_displayName(row['name']?.toString() ?? '')),
                    _CellText('${_asInt(row['first'])}'),
                    _CellText('${_asInt(row['asteroid'])}'),
                    _CellText('${_asInt(row['comet'])}'),
                    _CellText('${_asInt(row['dwarf_planet'])}'),
                    _CellText('${_asInt(row['nebula'])}'),
                    _CellText('${_asInt(row['x'])}'),
                    _CellText('${_asInt(row['sum'])}'),
                    _CellText('${_asInt(row['step'])}'),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  String _displayName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return '-';
    }
    final mapped = playerNameById[normalized]?.trim();
    if (mapped != null && mapped.isNotEmpty) {
      return mapped;
    }
    return normalized;
  }
}

class _CellText extends StatelessWidget {
  const _CellText(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
      ),
    );
  }
}

class _HeaderIconText extends StatelessWidget {
  const _HeaderIconText({
    required this.asset,
    required this.label,
  });

  final String asset;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Image.asset(
            asset,
            width: 18,
            height: 18,
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.circle, size: 14),
          ),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
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
