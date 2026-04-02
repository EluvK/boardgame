import 'package:flutter/material.dart';

class PlanetXLogEntry {
  const PlanetXLogEntry({
    required this.time,
    required this.type,
    required this.actor,
    required this.summary,
    required this.raw,
    this.category = '',
  });

  final DateTime time;
  final String type;
  final String actor;
  final String summary;
  final String raw;
  final String category;
}

class PlanetXClueEntry {
  const PlanetXClueEntry({
    required this.index,
    required this.secret,
    required this.detail,
  });

  final String index;
  final String secret;
  final String detail;
}

class PlanetXLogsPanel extends StatelessWidget {
  const PlanetXLogsPanel({
    super.key,
    required this.currentUserId,
    required this.opLog,
    required this.clueRows,
    required this.meetingLog,
  });

  final String currentUserId;
  final List<PlanetXLogEntry> opLog;
  final List<PlanetXClueEntry> clueRows;
  final List<PlanetXLogEntry> meetingLog;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PlanetXOpLogTable(currentUserId: currentUserId, rows: opLog),
        const SizedBox(height: 2),
        PlanetXClueLogTable(rows: clueRows),
        const SizedBox(height: 2),
        PlanetXMeetingLogTable(rows: meetingLog),
      ],
    );
  }
}

class PlanetXOpLogTable extends StatelessWidget {
  const PlanetXOpLogTable({
    super.key,
    required this.currentUserId,
    required this.rows,
  });

  final String currentUserId;
  final List<PlanetXLogEntry> rows;

  @override
  Widget build(BuildContext context) {
    final selfOpRows = rows.where((e) => e.category == 'self_op').toList().reversed.toList();
    final selfResultRows = rows.where((e) => e.category == 'self_result').toList().reversed.toList();
    final otherOpRows = rows.where((e) => e.category == 'other_op').toList().reversed.toList();

    final fallbackResultRows = rows
        .where((e) => e.category.isEmpty && e.actor == currentUserId)
      .toList()
      .reversed
      .toList();
    if (selfResultRows.isEmpty && fallbackResultRows.isNotEmpty) {
      selfResultRows.addAll(fallbackResultRows);
    }

    final fallbackOtherRows = rows
      .where((e) => e.category.isEmpty && e.actor != currentUserId)
      .toList()
      .reversed
      .toList();
    if (otherOpRows.isEmpty && fallbackOtherRows.isNotEmpty) {
      otherOpRows.addAll(fallbackOtherRows);
    }

    final rowCount = [selfOpRows.length, selfResultRows.length, otherOpRows.length]
        .reduce((a, b) => a > b ? a : b);

    return _panel(
      context: context,
      title: 'OpLog',
      table: Table(
        border: TableBorder.all(),
        columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2)},
        children: [
          _headerRow(const ['Self Op', 'Self Result', 'Others Op']),
          for (int i = 0; i < rowCount && i < 12; i++)
            TableRow(
              children: [
                _tableCell(_tapText(context, i < selfOpRows.length ? selfOpRows[i] : null)),
                _tableCell(_tapText(context, i < selfResultRows.length ? selfResultRows[i] : null)),
                _tableCell(_tapText(context, i < otherOpRows.length ? otherOpRows[i] : null)),
              ],
            ),
        ],
      ),
    );
  }
}

class PlanetXClueLogTable extends StatelessWidget {
  const PlanetXClueLogTable({
    super.key,
    required this.rows,
  });

  final List<PlanetXClueEntry> rows;

  @override
  Widget build(BuildContext context) {
    return _panel(
      context: context,
      title: 'ClueLog',
      table: Table(
        border: TableBorder.all(),
        columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3)},
        children: [
          _headerRow(const ['clue', 'detail']),
          for (final row in rows.take(12))
            TableRow(
              children: [
                _tableCell(Text('${row.index}: ${row.secret}')),
                _tableCell(
                  Text(
                    row.detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class PlanetXMeetingLogTable extends StatelessWidget {
  const PlanetXMeetingLogTable({
    super.key,
    required this.rows,
  });

  final List<PlanetXLogEntry> rows;

  @override
  Widget build(BuildContext context) {
    return _panel(
      context: context,
      title: 'MeetingLog',
      table: Table(
        border: TableBorder.all(),
        children: [
          _headerRow(const ['meeting']),
          for (final row in rows.take(12))
            TableRow(
              children: [
                _tableCell(_tapText(context, row, prefixTime: true)),
              ],
            ),
        ],
      ),
    );
  }
}

Widget _panel({
  required BuildContext context,
  required String title,
  required Widget table,
}) {
  return Column(
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.primaryContainer,
        ),
        child: table,
      ),
      const SizedBox(height: 4),
    ],
  );
}

TableRow _headerRow(List<String> cells) {
  return TableRow(
    children: [
      for (final text in cells)
        _tableCell(
          Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
    ],
  );
}

Widget _tapText(BuildContext context, PlanetXLogEntry? row, {bool prefixTime = false}) {
  if (row == null) {
    return const Text('');
  }
  final body = prefixTime ? '[${_formatTime(row.time)}] ${row.summary}' : row.summary;
  return InkWell(
    onTap: () => _showRaw(context, row),
    child: Text(
      body,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
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
