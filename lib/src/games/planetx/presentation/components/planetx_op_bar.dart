import 'package:flutter/material.dart';

enum PlanetXOpKind {
  survey,
  target,
  research,
  locate,
  readyPublish,
  doPublish,
}

class PlanetXOpBar extends StatelessWidget {
  const PlanetXOpBar({
    super.key,
    required this.busy,
    required this.roomStarted,
    required this.currentUserId,
    required this.currentPlayerId,
    required this.currentPlayerName,
    required this.gameStage,
    required this.mapSize,
    required this.sectorTypes,
    required this.publishableTypes,
    required this.onSync,
    required this.onSurvey,
    required this.onTarget,
    required this.onResearch,
    required this.onLocate,
    required this.onReadyPublish,
    required this.onDoPublish,
  });

  final bool busy;
  final bool roomStarted;
  final String currentUserId;
  final String currentPlayerId;
  final String currentPlayerName;
  final String gameStage;
  final int mapSize;
  final List<String> sectorTypes;
  final List<String> publishableTypes;
  final VoidCallback onSync;
  final VoidCallback onSurvey;
  final VoidCallback onTarget;
  final VoidCallback onResearch;
  final void Function(int index, String pre, String next) onLocate;
  final void Function(List<String> sectors) onReadyPublish;
  final void Function(int index, String sectorType) onDoPublish;

  @override
  Widget build(BuildContext context) {
    return _PlanetXOpBarForm(
      busy: busy,
      roomStarted: roomStarted,
      currentUserId: currentUserId,
      currentPlayerId: currentPlayerId,
      currentPlayerName: currentPlayerName,
      gameStage: gameStage,
      mapSize: mapSize,
      sectorTypes: sectorTypes,
      publishableTypes: publishableTypes,
      onSync: onSync,
      onSurvey: onSurvey,
      onTarget: onTarget,
      onResearch: onResearch,
      onLocate: onLocate,
      onReadyPublish: onReadyPublish,
      onDoPublish: onDoPublish,
    );
  }
}

class _PlanetXOpBarForm extends StatefulWidget {
  const _PlanetXOpBarForm({
    required this.busy,
    required this.roomStarted,
    required this.currentUserId,
    required this.currentPlayerId,
    required this.currentPlayerName,
    required this.gameStage,
    required this.mapSize,
    required this.sectorTypes,
    required this.publishableTypes,
    required this.onSync,
    required this.onSurvey,
    required this.onTarget,
    required this.onResearch,
    required this.onLocate,
    required this.onReadyPublish,
    required this.onDoPublish,
  });

  final bool busy;
  final bool roomStarted;
  final String currentUserId;
  final String currentPlayerId;
  final String currentPlayerName;
  final String gameStage;
  final int mapSize;
  final List<String> sectorTypes;
  final List<String> publishableTypes;
  final VoidCallback onSync;
  final VoidCallback onSurvey;
  final VoidCallback onTarget;
  final VoidCallback onResearch;
  final void Function(int index, String pre, String next) onLocate;
  final void Function(List<String> sectors) onReadyPublish;
  final void Function(int index, String sectorType) onDoPublish;

  @override
  State<_PlanetXOpBarForm> createState() => _PlanetXOpBarFormState();
}

class _PlanetXOpBarFormState extends State<_PlanetXOpBarForm> {
  PlanetXOpKind? _expanded;

  int _locateIndex = 1;
  String _locatePre = 'comet';
  String _locateNext = 'asteroid';

  String? _readyFirst;
  String? _readySecond;

  int _publishIndex = 1;
  String _publishType = 'comet';

  @override
  void initState() {
    super.initState();
    final opTypes = widget.sectorTypes.where((s) => s != 'x' && s != 'space').toList();
    _locatePre = opTypes.isEmpty ? 'comet' : opTypes.first;
    _locateNext = opTypes.length > 1 ? opTypes[1] : _locatePre;
    final publishTypes = widget.publishableTypes.isEmpty ? opTypes : widget.publishableTypes;
    if (publishTypes.isNotEmpty) {
      _publishType = publishTypes.first;
      _readyFirst = publishTypes.first;
      _readySecond = publishTypes.length > 1 ? publishTypes[1] : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final opTypes = widget.sectorTypes.where((s) => s != 'x' && s != 'space').toList();
    final publishTypes = widget.publishableTypes.isEmpty ? opTypes : widget.publishableTypes;
    final isMyTurn = widget.currentPlayerId.isNotEmpty && widget.currentPlayerId == widget.currentUserId;
    final availableOps = widget.roomStarted && isMyTurn ? _opsByStage(widget.gameStage) : const <PlanetXOpKind>[];

    if (_expanded != null && !availableOps.contains(_expanded)) {
      _expanded = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            !widget.roomStarted
                ? 'Game not started'
                : (isMyTurn
                    ? 'Your turn'
                    : 'Waiting: ${widget.currentPlayerName.isEmpty ? '-' : widget.currentPlayerName}'),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: widget.busy ? null : widget.onSync,
              child: const Text('Sync'),
            ),
            for (final op in availableOps) _opChip(op, _labelForOp(op)),
          ],
        ),
        const SizedBox(height: 8),
        if (_expanded == PlanetXOpKind.survey)
          _inlinePanel(
            child: _confirmButton(
              label: 'Confirm Survey (1-6 comet)',
              onPressed: widget.busy ? null : widget.onSurvey,
            ),
          ),
        if (_expanded == PlanetXOpKind.target)
          _inlinePanel(
            child: _confirmButton(
              label: 'Confirm Target (1)',
              onPressed: widget.busy ? null : widget.onTarget,
            ),
          ),
        if (_expanded == PlanetXOpKind.research)
          _inlinePanel(
            child: _confirmButton(
              label: 'Confirm Research A',
              onPressed: widget.busy ? null : widget.onResearch,
            ),
          ),
        if (_expanded == PlanetXOpKind.locate)
          _inlinePanel(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _numberField(
                  label: 'Index',
                  value: _locateIndex,
                  min: 1,
                  max: widget.mapSize,
                  onChanged: (v) => setState(() => _locateIndex = v),
                ),
                _typeDropdown(
                  label: 'Pre',
                  value: _locatePre,
                  items: opTypes,
                  onChanged: (v) => setState(() => _locatePre = v),
                ),
                _typeDropdown(
                  label: 'Next',
                  value: _locateNext,
                  items: opTypes,
                  onChanged: (v) => setState(() => _locateNext = v),
                ),
                _confirmButton(
                  label: 'Confirm Locate',
                  onPressed: widget.busy
                      ? null
                      : () => widget.onLocate(_locateIndex, _locatePre, _locateNext),
                ),
              ],
            ),
          ),
        if (_expanded == PlanetXOpKind.readyPublish)
          _inlinePanel(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _typeDropdownNullable(
                  label: 'Token 1',
                  value: _readyFirst,
                  items: publishTypes,
                  onChanged: (v) => setState(() => _readyFirst = v),
                ),
                _typeDropdownNullable(
                  label: 'Token 2',
                  value: _readySecond,
                  items: publishTypes,
                  onChanged: (v) => setState(() => _readySecond = v),
                ),
                _confirmButton(
                  label: 'Confirm Ready Publish',
                  onPressed: widget.busy
                      ? null
                      : () {
                          final selected = <String?>[_readyFirst, _readySecond]
                              .whereType<String>()
                              .toList();
                          if (selected.isEmpty) {
                            return;
                          }
                          widget.onReadyPublish(selected);
                        },
                ),
              ],
            ),
          ),
        if (_expanded == PlanetXOpKind.doPublish)
          _inlinePanel(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _numberField(
                  label: 'Index',
                  value: _publishIndex,
                  min: 1,
                  max: widget.mapSize,
                  onChanged: (v) => setState(() => _publishIndex = v),
                ),
                _typeDropdown(
                  label: 'Type',
                  value: _publishType,
                  items: publishTypes,
                  onChanged: (v) => setState(() => _publishType = v),
                ),
                _confirmButton(
                  label: 'Confirm Publish',
                  onPressed: widget.busy
                      ? null
                      : () => widget.onDoPublish(_publishIndex, _publishType),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<PlanetXOpKind> _opsByStage(String stage) {
    switch (stage) {
      case 'user_move':
        return const [
          PlanetXOpKind.survey,
          PlanetXOpKind.target,
          PlanetXOpKind.research,
          PlanetXOpKind.locate,
        ];
      case 'meeting_proposal':
        return const [PlanetXOpKind.readyPublish];
      case 'meeting_publish':
        return const [PlanetXOpKind.doPublish];
      case 'last_move':
        return const [PlanetXOpKind.locate, PlanetXOpKind.doPublish];
      default:
        return const [
          PlanetXOpKind.survey,
          PlanetXOpKind.target,
          PlanetXOpKind.research,
          PlanetXOpKind.locate,
          PlanetXOpKind.readyPublish,
          PlanetXOpKind.doPublish,
        ];
    }
  }

  String _labelForOp(PlanetXOpKind kind) {
    switch (kind) {
      case PlanetXOpKind.survey:
        return 'Survey';
      case PlanetXOpKind.target:
        return 'Target';
      case PlanetXOpKind.research:
        return 'Research A';
      case PlanetXOpKind.locate:
        return 'Locate X';
      case PlanetXOpKind.readyPublish:
        return 'Ready Publish';
      case PlanetXOpKind.doPublish:
        return 'Do Publish';
    }
  }

  Widget _opChip(PlanetXOpKind kind, String label) {
    final selected = _expanded == kind;
    return ChoiceChip(
      selected: selected,
      onSelected: widget.busy
          ? null
          : (_) {
              setState(() {
                _expanded = selected ? null : kind;
              });
            },
      label: Text(label),
    );
  }

  Widget _inlinePanel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  Widget _confirmButton({required String label, required VoidCallback? onPressed}) {
    return ElevatedButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }

  Widget _numberField({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label:'),
        const SizedBox(width: 4),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          visualDensity: VisualDensity.compact,
        ),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w600)),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _typeDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    final safeItems = items.isEmpty ? const ['comet'] : items;
    final safeValue = safeItems.contains(value) ? value : safeItems.first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label:'),
        const SizedBox(width: 6),
        DropdownButton<String>(
          value: safeValue,
          items: safeItems
              .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
              .toList(),
          onChanged: widget.busy
              ? null
              : (v) {
                  if (v != null) {
                    onChanged(v);
                  }
                },
        ),
      ],
    );
  }

  Widget _typeDropdownNullable({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safeItems = items.isEmpty ? const ['comet'] : items;
    final nullableItems = <String?>[null, ...safeItems];
    final safeValue = nullableItems.contains(value) ? value : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label:'),
        const SizedBox(width: 6),
        DropdownButton<String?>(
          value: safeValue,
          items: nullableItems
              .map(
                (e) => DropdownMenuItem<String?>(
                  value: e,
                  child: Text(e ?? '-'),
                ),
              )
              .toList(),
          onChanged: widget.busy ? null : onChanged,
        ),
      ],
    );
  }
}
