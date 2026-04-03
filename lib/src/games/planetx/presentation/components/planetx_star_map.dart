import 'dart:math' as math;

import 'package:flutter/material.dart';

class PlanetXPlayerMarker {
  const PlanetXPlayerMarker({
    required this.name,
    required this.step,
    required this.order,
  });

  final String name;
  final int step;
  final int order;
}

class PlanetXPublicTokenMarker {
  const PlanetXPublicTokenMarker({
    required this.sectorIndex,
    required this.meetingIndex,
    required this.userIndex,
    this.revealedType,
  });

  final int sectorIndex;
  final int meetingIndex;
  final int userIndex;
  final String? revealedType;
}

class PlanetXStarMap extends StatelessWidget {
  const PlanetXStarMap({
    super.key,
    required this.sectors,
    required this.showMeetingView,
    required this.onToggleView,
    required this.recommendCount,
    required this.canLocate,
    required this.onRecommendCount,
    required this.onRecommendCanLocate,
    required this.busy,
    required this.fallbackSectorCount,
    required this.visibleStart,
    required this.visibleEnd,
    required this.playerMarkers,
    required this.markModeConfirm,
    required this.onMarkModeChanged,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.historyText,
    required this.onMarkTap,
    required this.sectorMarks,
    required this.tokensCount,
    required this.othersCount,
    required this.ownTokenCounts,
    required this.publicTokenMarkers,
    required this.rotationDegrees,
    required this.onRotateCenter,
  });

  final List<String> sectors;
  final bool showMeetingView;
  final VoidCallback onToggleView;
  final int recommendCount;
  final bool canLocate;
  final VoidCallback onRecommendCount;
  final VoidCallback onRecommendCanLocate;
  final bool busy;
  final int fallbackSectorCount;
  final int visibleStart;
  final int visibleEnd;
  final List<PlanetXPlayerMarker> playerMarkers;

  final bool markModeConfirm;
  final ValueChanged<bool> onMarkModeChanged;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final String historyText;
  final void Function(int sectorIndex, int slotIndex) onMarkTap;
  final List<List<int>> sectorMarks;

  final int tokensCount;
  final int othersCount;
  final Map<String, int> ownTokenCounts;
  final List<PlanetXPublicTokenMarker> publicTokenMarkers;
  final double rotationDegrees;
  final VoidCallback onRotateCenter;

  @override
  Widget build(BuildContext context) {
    final displaySectors = sectors.isEmpty
        ? List<String>.filled(fallbackSectorCount.clamp(1, 18), 'space')
        : sectors.map(_normalizeSectorType).toList();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 42),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeInBack,
                    switchOutCurve: Curves.easeInBack.flipped,
                    transitionBuilder: (child, animation) {
                      final rotateAnim = Tween(begin: math.pi, end: 0.0).animate(animation);
                      return AnimatedBuilder(
                        animation: rotateAnim,
                        child: child,
                        builder: (context, c) {
                          final tiltSign = showMeetingView ? 1.0 : -1.0;
                          final tilt = ((animation.value - 0.5).abs() - 0.5) * 0.003 * tiltSign;
                          final value = math.min(rotateAnim.value, math.pi / 2);
                          return Transform(
                            transform: (Matrix4.rotationY(value)..setEntry(3, 0, tilt)),
                            alignment: Alignment.center,
                            child: c,
                          );
                        },
                      );
                    },
                    child: showMeetingView
                        ? _buildMeetingMapView(displaySectors)
                        : _buildStarMapView(displaySectors),
                  ),
                ),
              ),
            ],
          ),
          if (showMeetingView)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _counterChip(context, 'Tokens', tokensCount),
              ),
            ),
          if (showMeetingView)
            Positioned(
              left: 8,
              top: 10,
              child: _counterChip(context, 'Others', othersCount),
            ),
          if (showMeetingView)
            Positioned(
              right: 8,
              top: 10,
              child: _tokenCountChip(context),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            child: _recommendBar(),
          ),
          if (!showMeetingView)
            Positioned(
              right: 42,
              bottom: 6,
              child: _legend(context),
            ),
          if (!showMeetingView)
            Positioned(
              left: 6,
              top: 4,
              child: _toolbar(),
            ),
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              onPressed: onToggleView,
              icon: Icon(
                showMeetingView ? Icons.switch_left_rounded : Icons.switch_right_rounded,
                size: 30,
              ),
              tooltip: 'Flip View',
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Row(
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: true,
              label: Text('Confirm'),
              icon: SizedBox(width: 12, child: Icon(Icons.check, size: 14)),
            ),
            ButtonSegment<bool>(
              value: false,
              label: Text('Exclude'),
              icon: SizedBox(width: 12, child: Icon(Icons.swap_horiz, size: 14)),
            ),
          ],
          selected: {markModeConfirm},
          showSelectedIcon: false,
          onSelectionChanged: (v) => onMarkModeChanged(v.first),
          style: const ButtonStyle(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity(horizontal: -2, vertical: -2),
          ),
        ),
        SizedBox(
          width: 24,
          child: IconButton(
            onPressed: canUndo ? onUndo : null,
            icon: const Icon(Icons.undo, size: 20),
            tooltip: 'starmap_button_undo',
          ),
        ),
        SizedBox(
          width: 24,
          child: IconButton(
            onPressed: canRedo ? onRedo : null,
            icon: const Icon(Icons.redo, size: 20),
            tooltip: 'starmap_button_redo',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Tooltip(
            message: 'starmap_button_history_desc',
            child: Text(historyText, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _recommendBar() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 32,
          child: IconButton(
            onPressed: busy ? null : onRecommendCanLocate,
            icon: Icon(canLocate ? Icons.check : Icons.question_mark, size: 16),
            tooltip: 'Can Locate',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        TextButton(
          onPressed: busy ? null : onRecommendCount,
          style: TextButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text('#$recommendCount'),
        ),
      ],
    );
  }

  Widget _buildStarMapView(List<String> displaySectors) {
    final count = displaySectors.length;
    final season = _seasonForRotation(rotationDegrees);

    return LayoutBuilder(
      key: const ValueKey('star_view'),
      builder: (context, constraints) {
        final size = math.max(300.0, math.min(constraints.maxWidth, constraints.maxHeight));
        final radius = (size - 26) / 2;
        final baseRadius = 42.0;
        final each = 360.0 / count;

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white,
                          Colors.blueGrey.withAlpha(18),
                        ],
                        stops: const [0.18, 1.0],
                      ),
                    ),
                  ),
                  for (int ring = 1; ring <= 6; ring++)
                    CustomPaint(
                      size: Size(size, size),
                      painter: _CircleBorderPainter(
                        radius: baseRadius + (radius - baseRadius) * ring / 6.4,
                        color: Colors.grey.withAlpha(70),
                      ),
                    ),
                CustomPaint(
                  size: Size(size, size),
                  painter: _SectorBorderPainter(
                    sectorCount: count,
                    radius: radius,
                    visibleStart: visibleStart,
                    visibleEnd: visibleEnd,
                    rotationDegrees: rotationDegrees,
                  ),
                ),
                ..._buildOuterSpecialPoints(
                  size: size,
                  radius: radius,
                  count: count,
                ),
                for (int s = 0; s < count; s++)
                  ...List.generate(6, (slot) {
                    final centerDegree = each * s + each / 2 + rotationDegrees;
                    final radians = centerDegree * math.pi / 180;
                    final rotation = -(radians + math.pi);
                    final buttonRadius = baseRadius + (radius - baseRadius) * (slot + 1) / 6.6;
                    final x = buttonRadius * math.cos(radians);
                    final y = buttonRadius * math.sin(radians);
                    final showSlot = slot != 0 || _isPrime(s + 1);

                    final row = (s < sectorMarks.length) ? sectorMarks[s] : const <int>[];
                    final mark = (slot < row.length) ? row[slot] : 0;

                    return Positioned(
                      left: size / 2 + x - 14,
                      top: size / 2 + y - 14,
                      child: Transform.rotate(
                        angle: rotation,
                        child: GestureDetector(
                          onTap: showSlot ? () => onMarkTap(s, slot) : null,
                          onSecondaryTap: showSlot ? () => onMarkTap(s, slot) : null,
                          child: showSlot
                              ? Transform.rotate(
                                  angle: -rotation,
                                  child: _markSlot(
                                    sectorType: _sectorTypeForSlot(slot),
                                    mark: mark,
                                    showType: true,
                                    emphasized: slot == 0,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    );
                  }),
                for (int s = 0; s < count; s++)
                  () {
                    final centerDegree = each * s + each / 2 + rotationDegrees;
                    final radians = centerDegree * math.pi / 180;
                    final x = (radius + 10) * math.cos(radians);
                    final y = (radius + 10) * math.sin(radians);
                    final innerX = (baseRadius + 4) * math.cos(radians);
                    final innerY = (baseRadius + 4) * math.sin(radians);
                    final isVisible = _visibleSector(s + 1, visibleStart, visibleEnd, count);
                    return Positioned(
                      child: Stack(
                        children: [
                          Positioned(
                            left: size / 2 + x - 8,
                            top: size / 2 + y - 8,
                            child: Text('${s + 1}', style: const TextStyle(fontSize: 11)),
                          ),
                          Positioned(
                            left: size / 2 + innerX - 8,
                            top: size / 2 + innerY - 8,
                            child: Text(
                              '${s + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isVisible ? Colors.black : Colors.grey,
                                fontWeight: isVisible ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }(),
                ..._buildPlayerMarkers(
                  size: size,
                  count: count,
                  radius: radius,
                ),
                GestureDetector(
                  onTap: onRotateCenter,
                  child: Tooltip(
                    message: 'Spin Season',
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0xFF607D8B),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        season.label,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMeetingMapView(List<String> displaySectors) {
    final season = _seasonForRotation(rotationDegrees);
    return LayoutBuilder(
      key: const ValueKey('meeting_view'),
      builder: (context, constraints) {
        final size = math.max(300.0, math.min(constraints.maxWidth, constraints.maxHeight));
        final radius = (size - 30) / 2;
        final each = 360.0 / displaySectors.length;

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white,
                        Colors.blueGrey.withAlpha(15),
                      ],
                      stops: const [0.2, 1.0],
                    ),
                  ),
                ),
                for (int ring = 1; ring <= 4; ring++)
                  CustomPaint(
                    size: Size(size, size),
                    painter: _CircleBorderPainter(
                      radius: 36 + (radius - 36) * ring / 4.6,
                      color: Colors.grey.withAlpha(80),
                    ),
                  ),
                CustomPaint(
                  size: Size(size, size),
                  painter: _SectorBorderPainter(
                    sectorCount: displaySectors.length,
                    radius: radius,
                    visibleStart: visibleStart,
                    visibleEnd: visibleEnd,
                    rotationDegrees: rotationDegrees,
                  ),
                ),
                ..._buildMeetingBackgroundMarkers(
                  size: size,
                  sectorCount: displaySectors.length,
                  radius: radius,
                  baseRadius: 36,
                ),
                ..._buildMeetingPublicTokenMarkers(
                  size: size,
                  sectorCount: displaySectors.length,
                  radius: radius,
                  baseRadius: 36,
                ),
                ..._buildMeetingTokenDots(
                  size: size,
                  count: tokensCount,
                  ringRadius: radius * 0.38,
                  color: Colors.teal,
                ),
                ..._buildMeetingTokenDots(
                  size: size,
                  count: othersCount,
                  ringRadius: radius * 0.52,
                  color: Colors.indigo,
                ),
                for (int s = 0; s < displaySectors.length; s++)
                  Builder(builder: (context) {
                    final centerDegree = each * s + each / 2 + rotationDegrees;
                    final radians = centerDegree * math.pi / 180;
                    final x = radius * math.cos(radians);
                    final y = radius * math.sin(radians);
                    return Positioned(
                      left: size / 2 + x - 12,
                      top: size / 2 + y - 12,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                            color: _sectorColor(displaySectors[s]).withAlpha(190),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${s + 1}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    );
                  }),
                GestureDetector(
                  onTap: onRotateCenter,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: Color(0xFF455A64),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      season.label,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildMeetingTokenDots({
    required double size,
    required int count,
    required double ringRadius,
    required Color color,
  }) {
    if (count <= 0) {
      return const <Widget>[];
    }

    const cardinalDegrees = <double>[-90, 0, 90, 180];
    final visibleCount = math.min(count, cardinalDegrees.length);
    return List<Widget>.generate(visibleCount, (i) {
      final degree = cardinalDegrees[i] + rotationDegrees;
      final rad = degree * math.pi / 180;
      final x = ringRadius * math.cos(rad);
      final y = ringRadius * math.sin(rad);
      return Positioned(
        left: size / 2 + x - 5,
        top: size / 2 + y - 5,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withAlpha(190),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
      );
    });
  }

  List<Widget> _buildPlayerMarkers({
    required double size,
    required int count,
    required double radius,
  }) {
    if (playerMarkers.isEmpty || count <= 0) {
      return const <Widget>[];
    }

    const colors = <Color>[
      Color(0xFF1E88E5),
      Color(0xFFE53935),
      Color(0xFF43A047),
      Color(0xFFFB8C00),
      Color(0xFF8E24AA),
      Color(0xFF00897B),
    ];

    final each = 360.0 / count;
    final ring = radius;
    final widgets = <Widget>[];
    for (final marker in playerMarkers) {
      final sectorIndex = (marker.step % count) + 1;
      final sequence = (marker.order % 4) + 1;
      final centerDegree =
          (rotationDegrees + 2) + each * (sectorIndex - 1) + (sequence - 0.5) * ((each - 4) / 4);
      final rad = centerDegree * math.pi / 180;
      final x = ring * math.cos(rad);
      final y = ring * math.sin(rad);
      final color = colors[marker.order % colors.length];
      widgets.add(
        Positioned(
          left: size / 2 + x - 10,
          top: size / 2 + y - 10,
          child: Tooltip(
            message: marker.name,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const Icon(Icons.person_rounded, size: 13, color: Colors.white),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildOuterSpecialPoints({
    required double size,
    required double radius,
    required int count,
  }) {
    final meeting = _meetingPointsForCount(count);
    final xClue = _xCluePointsForCount(count);
    final each = 360.0 / count;
    final widgets = <Widget>[];

    for (final p in meeting) {
      final degree = each * p + rotationDegrees - 0.1 * (each / 4);
      final rad = degree * math.pi / 180;
      final x = radius * math.cos(rad);
      final y = radius * math.sin(rad);
      widgets.add(
        Positioned(
          left: size / 2 + x - 9,
          top: size / 2 + y - 9,
          child: Tooltip(
            message: 'Conference Point',
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(color: Colors.lightGreen, shape: BoxShape.circle),
              child: const Icon(Icons.bookmark, color: Colors.white, size: 12),
            ),
          ),
        ),
      );
    }

    for (final p in xClue) {
      final degree = each * p + rotationDegrees - 0.1 * (each / 4);
      final rad = degree * math.pi / 180;
      final x = radius * math.cos(rad);
      final y = radius * math.sin(rad);
      widgets.add(
        Positioned(
          left: size / 2 + x - 8,
          top: size / 2 + y - 8,
          child: Tooltip(
            message: 'X Clue Point',
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(color: Colors.blueGrey, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 10),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  List<int> _meetingPointsForCount(int count) {
    if (count == 18) {
      return const [3, 6, 9, 12, 15, 18];
    }
    return const [3, 6, 9, 12];
  }

  List<int> _xCluePointsForCount(int count) {
    if (count == 18) {
      return const [7, 16];
    }
    return const [10];
  }

  List<Widget> _buildMeetingBackgroundMarkers({
    required double size,
    required int sectorCount,
    required double radius,
    required double baseRadius,
  }) {
    if (sectorCount <= 0) {
      return const <Widget>[];
    }

    const ringIconDefs = <(IconData, Color)>[
      (Icons.autorenew_rounded, Colors.black87),
      (Icons.crop_free, Colors.grey),
      (Icons.crop_free, Colors.grey),
      (Icons.add_box_outlined, Colors.blueGrey),
    ];

    final each = 360.0 / sectorCount;
    final iconSize = math.max(12.0, size / 24);
    final widgets = <Widget>[];

    for (int sector = 0; sector < sectorCount; sector++) {
      final centerDegree = each * sector + each / 2 + rotationDegrees;
      final radians = centerDegree * math.pi / 180;

      for (int ring = 0; ring < ringIconDefs.length; ring++) {
        final ringRadius = baseRadius + (radius - baseRadius) * (ring + 1) / 4.6;
        final x = ringRadius * math.cos(radians);
        final y = ringRadius * math.sin(radians);
        final (iconData, iconColor) = ringIconDefs[ring];

        widgets.add(
          Positioned(
            left: size / 2 + x - iconSize / 2,
            top: size / 2 + y - iconSize / 2,
            child: Icon(iconData, size: iconSize, color: iconColor.withAlpha(180)),
          ),
        );
      }
    }

    return widgets;
  }

  List<Widget> _buildMeetingPublicTokenMarkers({
    required double size,
    required int sectorCount,
    required double radius,
    required double baseRadius,
  }) {
    if (publicTokenMarkers.isEmpty || sectorCount <= 0) {
      return const <Widget>[];
    }

    final each = 360.0 / sectorCount;
    final widgets = <Widget>[];
    final ownerPalette = <Color>[
      const Color(0xFF1E88E5),
      const Color(0xFFE53935),
      const Color(0xFF43A047),
      const Color(0xFFFB8C00),
      const Color(0xFF8E24AA),
      const Color(0xFF00897B),
    ];

    for (final token in publicTokenMarkers) {
      if (token.sectorIndex <= 0 || token.sectorIndex > sectorCount) {
        continue;
      }
      if (token.meetingIndex >= 4) {
        continue;
      }

      final ringRadius = switch (token.meetingIndex) {
        0 => baseRadius - 6,
        1 => baseRadius + (radius - baseRadius) * 1 / 4.6,
        2 => baseRadius + (radius - baseRadius) * 2 / 4.6,
        _ => baseRadius + (radius - baseRadius) * 3 / 4.6,
      };

      final ownerOffset = ((token.userIndex % 5) - 2) * (each / 22.0);
      final centerDegree = each * (token.sectorIndex - 1) + each / 2 + rotationDegrees + ownerOffset;
      final radians = centerDegree * math.pi / 180;
      final x = ringRadius * math.cos(radians);
      final y = ringRadius * math.sin(radians);
      final color = ownerPalette[(token.userIndex - 1).abs() % ownerPalette.length];

      final revealed = token.revealedType != null && token.revealedType!.isNotEmpty;
      widgets.add(
        Positioned(
          left: size / 2 + x - 8,
          top: size / 2 + y - 8,
          child: Tooltip(
            message: revealed
                ? 'Revealed ${_sectorShortLabel(token.revealedType!)}'
                : 'Hidden token',
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withAlpha(210),
                border: Border.all(color: Colors.white, width: 1),
              ),
              alignment: Alignment.center,
              child: revealed
                  ? Padding(
                      padding: const EdgeInsets.all(2),
                      child: Image.asset(
                        _sectorAssetPath(_normalizeSectorType(token.revealedType!)),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _counterChip(BuildContext context, String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _tokenCountChip(BuildContext context) {
    const order = <String>['comet', 'asteroid', 'dwarf_planet', 'nebula'];
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My Tokens', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          SizedBox(
            width: 180,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final ty in order)
                  _tokenCountCell(
                    type: ty,
                    count: ownTokenCounts[ty] ?? 0,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tokenCountCell({required String type, required int count}) {
    return SizedBox(
      width: 80,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: Image.asset(
              _sectorAssetPath(type),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 4),
          Text('x$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _markSlot({
    required String sectorType,
    required int mark,
    required bool showType,
    required bool emphasized,
  }) {
    final confirmed = mark != 2;
    final border = confirmed ? Border.all(color: Colors.grey, width: 1) : Border.all(color: Colors.transparent);
    final bg = _sectorColor(sectorType).withAlpha(emphasized ? 160 : 85);

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: border,
      ),
      alignment: Alignment.center,
      child: showType
          ? Padding(
              padding: const EdgeInsets.all(4),
              child: Image.asset(
                _sectorAssetPath(sectorType),
                fit: BoxFit.contain,
                color: confirmed ? null : Colors.black.withAlpha(28),
                colorBlendMode: confirmed ? BlendMode.srcOver : BlendMode.srcIn,
                errorBuilder: (context, error, stackTrace) => Text(
                  _sectorShortLabel(sectorType).substring(0, 1),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _legend(BuildContext context) {
    final items = const ['comet', 'asteroid', 'dwarf_planet', 'nebula', 'x'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(220),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 6,
        children: [
          for (final item in items)
            Tooltip(
              message: _sectorShortLabel(item),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black26, width: 0.5),
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(2),
                child: Image.asset(
                  _sectorAssetPath(item),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Text(
                      _sectorShortLabel(item).substring(0, 1),
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _sectorColor(String sector) {
    switch (_normalizeSectorType(sector)) {
      case 'comet':
        return const Color(0xFFE3F2FD);
      case 'asteroid':
        return const Color(0xFFE8EAF6);
      case 'dwarf_planet':
        return const Color(0xFFE0F2F1);
      case 'nebula':
        return const Color(0xFFF3E5F5);
      case 'x':
        return const Color(0xFFFFF3E0);
      case 'space':
      default:
        return const Color(0xFFF5F5F5);
    }
  }

  String _sectorShortLabel(String sector) {
    switch (_normalizeSectorType(sector)) {
      case 'comet':
        return 'Comet';
      case 'asteroid':
        return 'Asteroid';
      case 'dwarf_planet':
        return 'Dwarf';
      case 'nebula':
        return 'Nebula';
      case 'x':
        return 'X';
      case 'space':
      default:
        return 'Space';
    }
  }

  String _sectorAssetPath(String sector) {
    switch (_normalizeSectorType(sector)) {
      case 'comet':
        return 'assets/icons/comet.png';
      case 'asteroid':
        return 'assets/icons/asteroid.png';
      case 'dwarf_planet':
        return 'assets/icons/dwarf_planet.png';
      case 'nebula':
        return 'assets/icons/nebula.png';
      case 'x':
        return 'assets/icons/x.png';
      case 'space':
      default:
        return 'assets/icons/bracket.png';
    }
  }

  String _sectorTypeForSlot(int slotIndex) {
    switch (slotIndex) {
      case 0:
        return 'comet';
      case 1:
        return 'asteroid';
      case 2:
        return 'dwarf_planet';
      case 3:
        return 'nebula';
      case 4:
        return 'space';
      case 5:
      default:
        return 'x';
    }
  }

  String _normalizeSectorType(String raw) {
    final compact = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    switch (compact) {
      case '0':
        return 'comet';
      case '1':
        return 'asteroid';
      case '2':
        return 'dwarf_planet';
      case '3':
        return 'nebula';
      case '4':
        return 'space';
      case '5':
        return 'x';
    }
    if (compact == 'x' || compact == 'planetx' || compact.endsWith('x')) {
      return 'x';
    }
    if (compact.contains('dwarf') && compact.contains('planet')) {
      return 'dwarf_planet';
    }
    if (compact.contains('asteroid')) {
      return 'asteroid';
    }
    if (compact.contains('comet')) {
      return 'comet';
    }
    if (compact.contains('nebula')) {
      return 'nebula';
    }
    if (compact.contains('space') || compact.contains('empty')) {
      return 'space';
    }
    return 'space';
  }

  bool _isPrime(int n) {
    if (n <= 1) {
      return false;
    }
    if (n <= 3) {
      return true;
    }
    if (n % 2 == 0 || n % 3 == 0) {
      return false;
    }
    var i = 5;
    while (i * i <= n) {
      if (n % i == 0 || n % (i + 2) == 0) {
        return false;
      }
      i += 6;
    }
    return true;
  }
}

class _SeasonInfo {
  const _SeasonInfo(this.label);

  final String label;
}

_SeasonInfo _seasonForRotation(double degrees) {
  final n = _normalizedRightAngle(degrees);
  switch (n) {
    case 180:
      return const _SeasonInfo('春');
    case 270:
      return const _SeasonInfo('夏');
    case 0:
      return const _SeasonInfo('秋');
    case 90:
    default:
      return const _SeasonInfo('冬');
  }
}

int _normalizedRightAngle(double degrees) {
  final n = ((degrees % 360) + 360) % 360;
  final quarter = (n / 90).round() % 4;
  return quarter * 90;
}

class _CircleBorderPainter extends CustomPainter {
  const _CircleBorderPainter({
    required this.radius,
    required this.color,
  });

  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(Offset(size.width / 2, size.height / 2), radius, paint);
  }

  @override
  bool shouldRepaint(covariant _CircleBorderPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.color != color;
  }
}

class _SectorBorderPainter extends CustomPainter {
  const _SectorBorderPainter({
    required this.sectorCount,
    required this.radius,
    required this.visibleStart,
    required this.visibleEnd,
    required this.rotationDegrees,
  });

  final int sectorCount;
  final double radius;
  final int visibleStart;
  final int visibleEnd;
  final double rotationDegrees;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final borderPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < sectorCount; i++) {
      final angle = math.pi * 2 * i / sectorCount + rotationDegrees * math.pi / 180;
      final p2 = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      final edgeIndex = i + 1;
      // Legacy semantics: start_index marks the leading boundary, end_index marks the
      // inclusive end sector, so bold boundary is the next edge after end_index.
      final endBoundary = visibleEnd % sectorCount;
      final boldEdge = edgeIndex == visibleStart || i == endBoundary;
      canvas.drawLine(
        center,
        p2,
        borderPaint
          ..color = boldEdge ? Colors.black : Colors.blueGrey
          ..strokeWidth = boldEdge ? 2 : 1,
      );
    }
    canvas.drawCircle(center, radius, borderPaint..color = Colors.black87);
  }

  @override
  bool shouldRepaint(covariant _SectorBorderPainter oldDelegate) {
    return oldDelegate.sectorCount != sectorCount ||
        oldDelegate.radius != radius ||
        oldDelegate.visibleStart != visibleStart ||
        oldDelegate.visibleEnd != visibleEnd ||
        oldDelegate.rotationDegrees != rotationDegrees;
  }
}

bool _visibleSector(int sectorIndex, int visibleStart, int visibleEnd, int max) {
  if (visibleStart <= 0 || visibleEnd <= 0 || visibleStart > max || visibleEnd > max) {
    return true;
  }
  if (visibleStart > visibleEnd) {
    return sectorIndex >= visibleStart || sectorIndex <= visibleEnd;
  }
  return sectorIndex >= visibleStart && sectorIndex <= visibleEnd;
}
