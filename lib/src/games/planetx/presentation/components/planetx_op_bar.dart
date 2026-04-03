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
    required this.visibleStart,
    required this.visibleEnd,
    required this.targetUsedCount,
    required this.researchChoices,
    required this.canResearch,
    required this.readyPublishLimit,
    required this.revealedIndexes,
    required this.pendingPublishTypes,
    required this.sectorTypes,
    required this.publishableTypes,
    required this.onSync,
    required this.onSurvey,
    required this.onTarget,
    required this.onResearch,
    required this.onLocate,
    required this.onReadyPublish,
    required this.onDoPublish,
    required this.meetingProposalSubmitted,
  });

  final bool busy;
  final bool roomStarted;
  final String currentUserId;
  final String currentPlayerId;
  final String currentPlayerName;
  final String gameStage;
  final int mapSize;
  final int visibleStart;
  final int visibleEnd;
  final int targetUsedCount;
  final List<String> researchChoices;
  final bool canResearch;
  final int readyPublishLimit;
  final List<int> revealedIndexes;
  final List<String> pendingPublishTypes;
  final List<String> sectorTypes;
  final List<String> publishableTypes;
  final VoidCallback onSync;
  final void Function(String sectorType, int start, int end) onSurvey;
  final void Function(int index) onTarget;
  final void Function(String clueIndex) onResearch;
  final void Function(int index, String pre, String next) onLocate;
  final void Function(List<String> sectors) onReadyPublish;
  final void Function(int index, String sectorType) onDoPublish;
  final bool meetingProposalSubmitted;

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
      visibleStart: visibleStart,
      visibleEnd: visibleEnd,
      targetUsedCount: targetUsedCount,
      researchChoices: researchChoices,
      canResearch: canResearch,
      readyPublishLimit: readyPublishLimit,
      revealedIndexes: revealedIndexes,
      pendingPublishTypes: pendingPublishTypes,
      sectorTypes: sectorTypes,
      publishableTypes: publishableTypes,
      onSync: onSync,
      onSurvey: onSurvey,
      onTarget: onTarget,
      onResearch: onResearch,
      onLocate: onLocate,
      onReadyPublish: onReadyPublish,
      onDoPublish: onDoPublish,
      meetingProposalSubmitted: meetingProposalSubmitted,
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
    required this.visibleStart,
    required this.visibleEnd,
    required this.targetUsedCount,
    required this.researchChoices,
    required this.canResearch,
    required this.readyPublishLimit,
    required this.revealedIndexes,
    required this.pendingPublishTypes,
    required this.sectorTypes,
    required this.publishableTypes,
    required this.onSync,
    required this.onSurvey,
    required this.onTarget,
    required this.onResearch,
    required this.onLocate,
    required this.onReadyPublish,
    required this.onDoPublish,
    required this.meetingProposalSubmitted,
  });

  final bool busy;
  final bool roomStarted;
  final String currentUserId;
  final String currentPlayerId;
  final String currentPlayerName;
  final String gameStage;
  final int mapSize;
  final int visibleStart;
  final int visibleEnd;
  final int targetUsedCount;
  final List<String> researchChoices;
  final bool canResearch;
  final int readyPublishLimit;
  final List<int> revealedIndexes;
  final List<String> pendingPublishTypes;
  final List<String> sectorTypes;
  final List<String> publishableTypes;
  final VoidCallback onSync;
  final void Function(String sectorType, int start, int end) onSurvey;
  final void Function(int index) onTarget;
  final void Function(String clueIndex) onResearch;
  final void Function(int index, String pre, String next) onLocate;
  final void Function(List<String> sectors) onReadyPublish;
  final void Function(int index, String sectorType) onDoPublish;
  final bool meetingProposalSubmitted;

  @override
  State<_PlanetXOpBarForm> createState() => _PlanetXOpBarFormState();
}

class _PlanetXOpBarFormState extends State<_PlanetXOpBarForm> {
  PlanetXOpKind? _expanded;

  String _surveyType = 'comet';
  int _surveyStart = 1;
  int _surveyEnd = 1;

  int _targetIndex = 1;
  String _researchIndex = 'A';

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
    _surveyType = opTypes.contains('comet') ? 'comet' : (opTypes.isEmpty ? 'comet' : opTypes.first);
    _surveyStart = _normalizeIndex(widget.visibleStart, widget.mapSize);
    _surveyEnd = _normalizeIndex(widget.visibleEnd, widget.mapSize);
    _targetIndex = _normalizeIndex(widget.visibleStart, widget.mapSize);
    _researchIndex = widget.researchChoices.isEmpty ? 'A' : widget.researchChoices.first;
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
    final canActByStage = widget.gameStage == 'meeting_proposal'
      ? !widget.meetingProposalSubmitted
      : isMyTurn;
    final availableOps = widget.roomStarted && canActByStage ? _opsByStage(widget.gameStage) : const <PlanetXOpKind>[];
    final surveyStart = _normalizeIndex(widget.visibleStart, widget.mapSize);
    final surveyEnd = _normalizeIndex(widget.visibleEnd, widget.mapSize);
    final canTarget = widget.targetUsedCount < 2;
    final researchChoices = widget.researchChoices.isEmpty ? const ['A'] : widget.researchChoices;
    final readyLimit = widget.readyPublishLimit <= 1 ? 1 : 2;
    final doPublishTypes = widget.gameStage == 'last_move'
        ? publishTypes
        : (widget.pendingPublishTypes.isEmpty ? publishTypes : widget.pendingPublishTypes);

    if (_expanded != null && !availableOps.contains(_expanded)) {
      _expanded = null;
    }

    if (_surveyStart != surveyStart) {
      _surveyStart = surveyStart;
    }
    if (_surveyEnd != surveyEnd) {
      _surveyEnd = surveyEnd;
    }
    if (!researchChoices.contains(_researchIndex)) {
      _researchIndex = researchChoices.first;
    }
    if (!doPublishTypes.contains(_publishType) && doPublishTypes.isNotEmpty) {
      _publishType = doPublishTypes.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            !widget.roomStarted
                ? 'Game not started'
              : widget.gameStage == 'meeting_proposal'
                ? (widget.meetingProposalSubmitted
                  ? 'Proposal submitted, waiting others'
                  : 'Meeting proposal: submit your hidden tokens')
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
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _typeDropdown(
                  label: 'Type',
                  value: _surveyType,
                  items: opTypes,
                  onChanged: (v) => setState(() => _surveyType = v),
                ),
                _numberField(
                  label: 'From',
                  value: _surveyStart,
                  min: surveyStart,
                  max: surveyEnd,
                  onChanged: (v) => setState(() {
                    _surveyStart = v;
                    if (_surveyEnd < _surveyStart) {
                      _surveyEnd = _surveyStart;
                    }
                  }),
                ),
                _numberField(
                  label: 'To',
                  value: _surveyEnd,
                  min: _surveyStart,
                  max: surveyEnd,
                  onChanged: (v) => setState(() => _surveyEnd = v),
                ),
                _costTag('Cost ${_surveyCost(_surveyStart, _surveyEnd, widget.mapSize)}'),
                _confirmButton(
                  label: 'Confirm Survey',
                  onPressed: widget.busy
                      ? null
                      : () => widget.onSurvey(_surveyType, _surveyStart, _surveyEnd),
                ),
              ],
            ),
          ),
        if (_expanded == PlanetXOpKind.target)
          _inlinePanel(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _numberField(
                  label: 'Sector',
                  value: _targetIndex,
                  min: surveyStart,
                  max: surveyEnd,
                  onChanged: (v) => setState(() => _targetIndex = v),
                ),
                _costTag('Cost 4 · left ${2 - widget.targetUsedCount}'),
                _confirmButton(
                  label: canTarget ? 'Confirm Target' : 'Target Exhausted',
                  onPressed: widget.busy || !canTarget ? null : () => widget.onTarget(_targetIndex),
                ),
              ],
            ),
          ),
        if (_expanded == PlanetXOpKind.research)
          _inlinePanel(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Clue:'),
                    const SizedBox(width: 6),
                    DropdownButton<String>(
                      value: _researchIndex,
                      items: researchChoices
                          .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                          .toList(),
                      onChanged: widget.busy || !widget.canResearch
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() => _researchIndex = v);
                              }
                            },
                    ),
                  ],
                ),
                _costTag('Cost 1'),
                _confirmButton(
                  label: widget.canResearch ? 'Confirm Research' : 'Research Locked',
                  onPressed:
                      widget.busy || !widget.canResearch ? null : () => widget.onResearch(_researchIndex),
                ),
              ],
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
                _costTag('Cost 5'),
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
                if (readyLimit >= 2)
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
                          final selected = <String?>[_readyFirst, if (readyLimit >= 2) _readySecond]
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
                  items: doPublishTypes,
                  onChanged: (v) => setState(() => _publishType = v),
                ),
                _costTag('revealed: ${widget.revealedIndexes.length}'),
                _confirmButton(
                  label: 'Confirm Publish',
                  onPressed: widget.busy
                      || widget.revealedIndexes.contains(_publishIndex)
                      || doPublishTypes.isEmpty
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
      case 'meeting_check':
        return const [];
      case 'last_move':
        return const [PlanetXOpKind.locate, PlanetXOpKind.doPublish];
      case 'game_end':
        return const [];
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

  int _normalizeIndex(int value, int max) {
    if (max <= 0) {
      return 1;
    }
    if (value <= 0) {
      return 1;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  int _surveyCost(int from, int to, int max) {
    final length = from <= to ? (to - from + 1) : (max - from + to + 1);
    return 4 - ((length - 1) ~/ 3);
  }

  Widget _costTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.blueGrey.withAlpha(22),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
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
