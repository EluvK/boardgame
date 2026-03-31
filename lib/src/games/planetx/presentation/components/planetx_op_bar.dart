import 'package:flutter/material.dart';

class PlanetXOpBar extends StatelessWidget {
  const PlanetXOpBar({
    super.key,
    required this.busy,
    required this.onSync,
    required this.onSurvey,
    required this.onTarget,
    required this.onResearch,
  });

  final bool busy;
  final VoidCallback onSync;
  final VoidCallback onSurvey;
  final VoidCallback onTarget;
  final VoidCallback onResearch;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: busy ? null : onSync,
          child: const Text('Sync'),
        ),
        OutlinedButton(
          onPressed: busy ? null : onSurvey,
          child: const Text('Survey'),
        ),
        OutlinedButton(
          onPressed: busy ? null : onTarget,
          child: const Text('Target'),
        ),
        OutlinedButton(
          onPressed: busy ? null : onResearch,
          child: const Text('Research A'),
        ),
      ],
    );
  }
}
