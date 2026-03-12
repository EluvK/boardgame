# boardgame_acquire

## E2E Smoke Flow

This checklist validates the current baseline: room lifecycle events, lobby push updates, and web routing scaffold.

### 1. Start server runtime

```bash
cargo run -p bg_runtime
```

Expected:
- server listens on `http://127.0.0.1:17980`
- socket path is `/socket.io`
- game list includes `acquire`
- demo room `acquire_demo` exists

### 2. Start Flutter web client

```bash
flutter run -d chrome
```

In Home page:
- Server URL: `http://127.0.0.1:17980`
- Display Name: any non-empty string
- Click `Connect`

Expected:
- status shows connected/authenticated
- Games list contains `Acquire (minimal)`
- Rooms list shows `acquire_demo`

### 3. Room lifecycle smoke

1. Create a room
2. Verify room appears in rooms list
3. Join the room
4. Verify Room Detail page opens
5. Leave the room (socket event path currently from API side)
6. Close room by emitting `close_room` (manual socket test for now)

Expected socket events:
- `create_room_result`
- `joined`
- `left`
- `close_room_result`
- `rooms_updated` (pushed on lifecycle changes)

### 4. Multi-tab push update smoke

1. Open two browser tabs to the web lobby
2. Connect both tabs
3. Create room in tab A

Expected:
- tab B receives lobby update without manual refresh
- room list in tab B updates from `rooms_updated`

### 5. Compile/analyze checks

```bash
cargo check --workspace
flutter analyze lib/src/home/home_page.dart lib/src/room/room_detail_page.dart lib/src/api/lobby_api.dart
```

Expected:
- no compile errors
- no dart analyze issues