import 'package:flutter/material.dart';

class PlanetXLogsPanel extends StatelessWidget {
  const PlanetXLogsPanel({
    super.key,
    required this.opLog,
    required this.clueLog,
    required this.meetingLog,
  });

  final List<String> opLog;
  final List<String> clueLog;
  final List<String> meetingLog;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PlanetXLogTable(title: 'OpLog', rows: opLog),
        const SizedBox(height: 2),
        PlanetXLogTable(title: 'ClueLog', rows: clueLog),
        const SizedBox(height: 2),
        PlanetXLogTable(title: 'MeetingLog', rows: meetingLog),
      ],
    );
  }
}

class PlanetXLogTable extends StatelessWidget {
  const PlanetXLogTable({
    super.key,
    required this.title,
    required this.rows,
  });

  final String title;
  final List<String> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
          child: Table(
            border: TableBorder.all(),
            children: [
              TableRow(children: [_tableCell(const Text('entry'))]),
              for (final row in rows.take(12)) TableRow(children: [_tableCell(Text(row))]),
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  TableCell _tableCell(Widget child) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: child,
      ),
    );
  }
}
