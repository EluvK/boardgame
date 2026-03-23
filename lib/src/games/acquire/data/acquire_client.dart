import '../../../api/lobby_api.dart';

class AcquireClient {
  AcquireClient({required this.api});

  final LobbyApi api;

  static const List<String> companyCatalog = [
    'Worldwide',
    'Sackson',
    'American',
    'Festival',
    'Imperial',
    'Continental',
    'Tower',
  ];

  Future<void> place({
    required String room,
    required String userId,
    required String pos,
  }) {
    return _sendAction(
      room: room,
      userId: userId,
      payload: {
        'type': 'place',
        'pos': pos,
      },
    );
  }

  Future<void> buy({
    required String room,
    required String userId,
    required Map<String, int> purchases,
  }) {
    final normalizedPurchases = <String, int>{};
    for (final entry in purchases.entries) {
      if (entry.key.isEmpty || entry.value <= 0) {
        continue;
      }
      normalizedPurchases[entry.key] = entry.value;
    }
    final totalShares = normalizedPurchases.values.fold<int>(0, (sum, n) => sum + n);

    return _sendAction(
      room: room,
      userId: userId,
      payload: {
        'type': 'buy',
        'shares': totalShares,
        'purchases': normalizedPurchases,
      },
    );
  }

  Future<void> chooseCompany({
    required String room,
    required String userId,
    required String company,
  }) {
    return _sendAction(
      room: room,
      userId: userId,
      payload: {
        'type': 'choose_company',
        'company': company,
      },
    );
  }

  Future<void> resolveMerge({
    required String room,
    required String userId,
    required String survivor,
  }) {
    return _sendAction(
      room: room,
      userId: userId,
      payload: {
        'type': 'resolve_merge',
        'survivor': survivor,
      },
    );
  }

  Future<void> mergeStockDecision({
    required String room,
    required String userId,
    required String company,
    required String mode,
    int? shares,
  }) {
    return _sendAction(
      room: room,
      userId: userId,
      payload: {
        'type': 'merge_stock_decision',
        'company': company,
        'mode': mode,
        'shares': shares,
      },
    );
  }

  Future<void> declareEnd({
    required String room,
    required String userId,
  }) {
    return _sendAction(
      room: room,
      userId: userId,
      payload: {'type': 'declare_end'},
    );
  }

  Future<void> drawTile({
    required String room,
    required String userId,
  }) {
    return _sendAction(
      room: room,
      userId: userId,
      payload: {'type': 'draw_tile'},
    );
  }

  Future<void> _sendAction({
    required String room,
    required String userId,
    required Map<String, dynamic> payload,
  }) {
    return api.sendAction(
      room: room,
      action: {
        'id': _actionId(userId),
        'user_id': userId,
        'payload': payload,
        'seq': null,
        'meta': null,
      },
    );
  }

  String _actionId(String userId) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return 'a-$userId-$ts';
  }
}
