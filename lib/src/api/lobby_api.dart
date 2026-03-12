import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/lobby_models.dart';

class LobbyApi {
  LobbyApi({required this.serverUrl});

  final String serverUrl;
  static const String _socketPath = '/socket.io';

  io.Socket? _socket;
  void Function(dynamic data)? _roomsUpdatedRawHandler;

  bool get isConnected => _socket?.connected ?? false;

  Future<void> connect() async {
    if (isConnected) {
      return;
    }

    final socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath(_socketPath)
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(3)
          .build(),
    );

    final connected = Completer<void>();
    final errored = Completer<Object>();

    socket.onConnect((_) {
      if (!connected.isCompleted) {
        connected.complete();
      }
    });
    socket.onConnectError((error) {
      if (!errored.isCompleted) {
        errored.complete(error ?? 'connect_error');
      }
    });
    socket.onError((error) {
      if (!errored.isCompleted) {
        errored.complete(error ?? 'socket_error');
      }
    });

    socket.connect();

    try {
      await Future.any([
        connected.future,
        errored.future.then((error) => throw Exception(error.toString())),
      ]).timeout(const Duration(seconds: 5));
    } catch (e) {
      socket.dispose();
      rethrow;
    }

    _socket = socket;
  }

  void disconnect() {
    setRoomsUpdatedListener(null);
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void setRoomsUpdatedListener(void Function(List<RoomSummary> rooms)? listener) {
    final socket = _socket;
    final old = _roomsUpdatedRawHandler;
    if (socket != null && old != null) {
      socket.off('rooms_updated', old);
    }
    _roomsUpdatedRawHandler = null;

    if (socket == null || listener == null) {
      return;
    }

    void onRoomsUpdated(dynamic data) {
      final map = _asMap(data);
      final rawRooms = (map['rooms'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      listener(rawRooms.map(RoomSummary.fromJson).toList());
    }

    _roomsUpdatedRawHandler = onRoomsUpdated;
    socket.on('rooms_updated', onRoomsUpdated);
  }

  Future<void> auth({required String userId, String? name}) async {
    await _emitAndWait(
      emitEvent: 'auth',
      payload: {'id': userId, 'name': (name?.trim().isEmpty ?? true) ? null : name},
      responseEvent: 'auth_ok',
    );
  }

  Future<List<RegisteredGame>> listGames() async {
    final res = await _emitAndWait(emitEvent: 'list_games', payload: null, responseEvent: 'list_games_result');

    final rawGames = (res['games'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();

    return rawGames.map(RegisteredGame.fromJson).toList();
  }

  Future<List<RoomSummary>> listRooms() async {
    final res = await _emitAndWait(emitEvent: 'list_rooms', payload: null, responseEvent: 'list_rooms_result');

    final rawRooms = (res['rooms'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();

    return rawRooms.map(RoomSummary.fromJson).toList();
  }

  Future<void> createRoom({required String room, required String gameId, bool autoJoin = true}) async {
    final res = await _emitAndWait(
      emitEvent: 'create_room',
      payload: {'room': room, 'game_id': gameId, 'opts': null, 'auto_join': autoJoin},
      responseEvent: 'create_room_result',
    );

    final ok = res['ok'] == true;
    if (!ok) {
      throw Exception(res['err']?.toString() ?? 'create_room_failed');
    }
  }

  Future<void> joinRoom(String roomId) async {
    await _emitAndWait(emitEvent: 'join_room', payload: {'room': roomId}, responseEvent: 'joined');
  }

  Future<void> leaveRoom(String roomId) async {
    final res = await _emitAndWait(emitEvent: 'leave_room', payload: {'room': roomId}, responseEvent: 'left');
    final ok = res['ok'] == true;
    if (!ok) {
      throw Exception(res['err']?.toString() ?? 'leave_room_failed');
    }
  }

  Future<Map<String, dynamic>> _emitAndWait({
    required String emitEvent,
    required Object? payload,
    required String responseEvent,
  }) async {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      throw Exception('not_connected');
    }

    final completer = Completer<Map<String, dynamic>>();

    void onResponse(dynamic data) {
      if (completer.isCompleted) {
        return;
      }
      completer.complete(_asMap(data));
    }

    void onError(dynamic data) {
      if (completer.isCompleted) {
        return;
      }
      final map = _asMap(data);
      completer.completeError(Exception(map['err']?.toString() ?? 'server_error'));
    }

    socket.once(responseEvent, onResponse);
    socket.once('error', onError);
    socket.emit(emitEvent, payload);

    try {
      return await completer.future.timeout(const Duration(seconds: 8));
    } finally {
      socket.off(responseEvent, onResponse);
      socket.off('error', onError);
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return {'value': data};
  }
}
