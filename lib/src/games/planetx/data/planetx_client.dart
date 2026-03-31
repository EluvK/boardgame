import '../../../api/lobby_api.dart';

class PlanetXClient {
  PlanetXClient({required this.api});

  final LobbyApi api;

  Future<void> sync({
    required String room,
    required String userId,
  }) {
    return _sendAction(
      room: room,
      userId: userId,
      payload: {
        'type': 'planetx_sync',
      },
    );
  }

  Future<void> recommendCount({
    required String room,
    required String userId,
  }) {
    return _sendAction(
      room: room,
      userId: userId,
      payload: {
        'type': 'planetx_recommend',
        'op': 'count',
      },
    );
  }

  Future<void> recommendCanLocate({
    required String room,
    required String userId,
  }) {
    return _sendAction(
      room: room,
      userId: userId,
      payload: {
        'type': 'planetx_recommend',
        'op': 'can_locate',
      },
    );
  }

  Future<void> sendSurvey({
    required String room,
    required String userId,
    required String sectorType,
    required int start,
    required int end,
  }) {
    return _sendOperation(
      room: room,
      userId: userId,
      op: {
        'survey': {
          'sector_type': sectorType,
          'start': start,
          'end': end,
        },
      },
    );
  }

  Future<void> sendTarget({
    required String room,
    required String userId,
    required int index,
  }) {
    return _sendOperation(
      room: room,
      userId: userId,
      op: {
        'target': {
          'index': index,
        },
      },
    );
  }

  Future<void> sendResearch({
    required String room,
    required String userId,
    required String clueIndex,
  }) {
    return _sendOperation(
      room: room,
      userId: userId,
      op: {
        'research': {
          'index': clueIndex,
        },
      },
    );
  }

  Future<void> sendLocate({
    required String room,
    required String userId,
    required int index,
    required String pre,
    required String next,
  }) {
    return _sendOperation(
      room: room,
      userId: userId,
      op: {
        'locate': {
          'index': index,
          'pre_sector_type': pre,
          'next_sector_type': next,
        },
      },
    );
  }

  Future<void> _sendOperation({
    required String room,
    required String userId,
    required Map<String, dynamic> op,
  }) {
    return _sendAction(
      room: room,
      userId: userId,
      payload: {
        'type': 'planetx_op',
        'op': op,
      },
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
        'id': '${DateTime.now().microsecondsSinceEpoch}_$userId',
        'user_id': userId,
        'payload': payload,
      },
    );
  }
}
