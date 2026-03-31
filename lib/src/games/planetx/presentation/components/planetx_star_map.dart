import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  });

  final List<String> sectors;
  final bool showMeetingView;
  final VoidCallback onToggleView;
  final int recommendCount;
  final bool canLocate;
  final VoidCallback onRecommendCount;
  final VoidCallback onRecommendCanLocate;
  final bool busy;

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

  @override
  Widget build(BuildContext context) {
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
                    child: showMeetingView ? _buildMeetingMapView() : _buildStarMapView(),
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
          Positioned(
            left: 8,
            bottom: 8,
            child: _recommendBar(),
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
              label: Text('Switch'),
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
            tooltip: 'Undo',
          ),
        ),
        SizedBox(
          width: 24,
          child: IconButton(
            onPressed: canRedo ? onRedo : null,
            icon: const Icon(Icons.redo, size: 20),
            tooltip: 'Redo',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(historyText, style: const TextStyle(fontSize: 12)),
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

  Widget _buildStarMapView() {
    final count = sectors.length;
    if (count == 0) {
      return const Center(child: Text('Waiting map data...'));
    }

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
                CustomPaint(
                  size: Size(size, size),
                  painter: _SectorBorderPainter(
                    sectorCount: count,
                    radius: radius,
                  ),
                ),
                for (int s = 0; s < count; s++)
                  ...List.generate(6, (slot) {
                    final centerDegree = each * s + each / 2;
                    final radians = centerDegree * math.pi / 180;
                    final buttonRadius = baseRadius + (radius - baseRadius) * (slot + 1) / 6.6;
                    final x = buttonRadius * math.cos(radians);
                    final y = buttonRadius * math.sin(radians);

                    final row = (s < sectorMarks.length) ? sectorMarks[s] : const <int>[];
                    final mark = (slot < row.length) ? row[slot] : 0;

                    return Positioned(
                      left: size / 2 + x - 14,
                      top: size / 2 + y - 14,
                      child: GestureDetector(
                        onTap: () => onMarkTap(s, slot),
                        child: _markSlot(
                          sectorType: sectors[s],
                          mark: mark,
                          showType: slot == 0,
                        ),
                      ),
                    );
                  }),
                for (int s = 0; s < count; s++)
                  Builder(builder: (context) {
                    final centerDegree = each * s + each / 2;
                    final radians = centerDegree * math.pi / 180;
                    final x = (radius + 10) * math.cos(radians);
                    final y = (radius + 10) * math.sin(radians);
                    return Positioned(
                      left: size / 2 + x - 8,
                      top: size / 2 + y - 8,
                      child: Text('${s + 1}', style: const TextStyle(fontSize: 11)),
                    );
                  }),
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xFF607D8B),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${count}S',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMeetingMapView() {
    if (sectors.isEmpty) {
      return const Center(child: Text('Waiting map data...'));
    }

    return LayoutBuilder(
      key: const ValueKey('meeting_view'),
      builder: (context, constraints) {
        final size = math.max(300.0, math.min(constraints.maxWidth, constraints.maxHeight));
        final radius = (size - 30) / 2;
        final each = 360.0 / sectors.length;

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (int ring = 1; ring <= 4; ring++)
                  CustomPaint(
                    size: Size(size, size),
                    painter: _CircleBorderPainter(
                      radius: 36 + (radius - 36) * ring / 4.6,
                      color: Colors.grey.withAlpha(80),
                    ),
                  ),
                for (int s = 0; s < sectors.length; s++)
                  Builder(builder: (context) {
                    final centerDegree = each * s + each / 2;
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
                          color: _sectorColor(sectors[s]).withAlpha(190),
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
                Container(
                  width: 70,
                  height: 70,
                  decoration: const BoxDecoration(
                    color: Color(0xFF455A64),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Meeting',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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

  Widget _markSlot({
    required String sectorType,
    required int mark,
    required bool showType,
  }) {
    final borderColor = switch (mark) {
      1 => Colors.green,
      2 => Colors.blue,
      _ => Colors.transparent,
    };
    final tint = switch (mark) {
      2 => Colors.black.withAlpha(35),
      _ => Colors.transparent,
    };

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: tint,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.4),
      ),
      alignment: Alignment.center,
      child: showType
          ? Text(
              _sectorShortLabel(sectorType).substring(0, 1),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            )
          : const SizedBox.shrink(),
    );
  }

  Color _sectorColor(String sector) {
    switch (sector) {
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
    switch (sector) {
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
  });

  final int sectorCount;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final borderPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < sectorCount; i++) {
      final angle = math.pi * 2 * i / sectorCount;
      final p2 = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(center, p2, borderPaint..color = Colors.blueGrey);
    }
    canvas.drawCircle(center, radius, borderPaint..color = Colors.black87);
  }

  @override
  bool shouldRepaint(covariant _SectorBorderPainter oldDelegate) {
    return oldDelegate.sectorCount != sectorCount || oldDelegate.radius != radius;
  }
}
