import 'package:flutter/material.dart';

class PlanetXLogEntry {
  const PlanetXLogEntry({
    required this.time,
    required this.type,
    required this.actor,
    required this.summary,
    required this.raw,
  });

  final DateTime time;
  final String type;
  final String actor;
  final String summary;
  final String raw;
}

class PlanetXLogsPanel extends StatelessWidget {
  const PlanetXLogsPanel({
    super.key,
    required this.opLog,
    required this.clueLog,
    required this.meetingLog,
  });

  final List<PlanetXLogEntry> opLog;
  final List<PlanetXLogEntry> clueLog;
  final List<PlanetXLogEntry> meetingLog;

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
  final List<PlanetXLogEntry> rows;

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
            columnWidths: const {
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.2),
              3: FlexColumnWidth(4),
            },
            children: [
              TableRow(
                children: [
                  _tableCell(const Text('time', style: TextStyle(fontWeight: FontWeight.bold))),
                  _tableCell(const Text('type', style: TextStyle(fontWeight: FontWeight.bold))),
                  _tableCell(const Text('actor', style: TextStyle(fontWeight: FontWeight.bold))),
                  _tableCell(const Text('summary', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              for (final row in rows.take(12)) _entryRow(context, row),
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  TableRow _entryRow(BuildContext context, PlanetXLogEntry row) {
    return TableRow(
      children: [
        _tableCell(Text(_formatTime(row.time))),
        _tableCell(Text(row.type)),
        _tableCell(Text(row.actor.isEmpty ? '-' : row.actor)),
        InkWell(
          onTap: () => _showRaw(context, row),
          child: _tableCell(
            Text(
              row.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  void _showRaw(BuildContext context, PlanetXLogEntry row) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${row.type} raw'),
          content: SingleChildScrollView(child: Text(row.raw)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
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
