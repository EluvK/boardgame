import 'package:flutter/material.dart';

class PlanetXRoomInfos extends StatelessWidget {
  const PlanetXRoomInfos({
    super.key,
    required this.roomId,
    required this.userId,
    required this.currentPlayer,
    required this.players,
    required this.stateMap,
  });

  final String roomId;
  final String userId;
  final String currentPlayer;
  final List<String> players;
  final Map<String, dynamic> stateMap;

  @override
  Widget build(BuildContext context) {
    final seq = stateMap['seq']?.toString() ?? '-';
    final started = stateMap['started'] == true;
    final turnOrder = _asStringList(stateMap['turn_order']);
    final mapSeed = stateMap['map_seed']?.toString() ?? '-';
    final mapType = stateMap['map_type']?.toString() ?? '-';

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.spaceEvenly,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('room: $roomId'),
          Text('user: $userId'),
          Text('current: ${currentPlayer.isEmpty ? '-' : currentPlayer}'),
          Text('players: ${players.join(', ')}'),
          Text('started: $started'),
          Text('seq: $seq'),
          Text('seed: $mapSeed'),
          Text('mode: $mapType'),
          if (turnOrder.isNotEmpty) Text('turn: ${turnOrder.join(' -> ')}'),
        ],
      ),
    );
  }
}

class PlanetXMessageBar extends StatelessWidget {
  const PlanetXMessageBar({
    super.key,
    required this.hint,
    required this.error,
  });

  final String hint;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = error == null || error!.isEmpty ? hint : '$hint | $error';
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey, width: 1),
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class PlanetXGameResult extends StatelessWidget {
  const PlanetXGameResult({
    super.key,
    required this.stateMap,
  });

  final Map<String, dynamic> stateMap;

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
                    _CellText(row['name']?.toString() ?? ''),
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
