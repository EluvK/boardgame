# Planet X Migration Handoff

Updated: 2026-04-02

This handoff summarizes migration status against `ref/planetx_client` and points to concrete files for follow-up.

## 1. Session Scope

- Goal: reduce drift from legacy implementation and recover gameplay-correct behavior first.
- Focus completed in this round: star-map icon rendering, meeting log semantics, operation-stage gating, and rules archiving.
- Additional focus completed: local star-map marking parity (interaction reliability + legacy-like visuals + undo/redo consistency).

## 2. Completed Fixes

1. Table parent-data crash fixed (`TableCell` nesting)

- File: `lib/src/games/planetx/presentation/components/planetx_logs.dart`
- Change: removed `InkWell -> TableCell` invalid nesting pattern; `TableCell` remains direct row child.

1. Star-map icon compatibility and legacy-like slot rendering

- File: `lib/src/games/planetx/presentation/components/planetx_star_map.dart`
- Change:
  - sector type normalization (`Comet`, `SectorType.Comet`, numeric `0..5`, etc.)
  - slot-based icon mapping (`comet/asteroid/dwarf_planet/nebula/space/x`)
  - prime-sector visibility and icon orientation closer to ref
  - meeting view background marker rings and four-direction token placement

1. Rotation model aligned to four-direction expectation

- File: `lib/src/games/planetx/presentation/planetx_room_page.dart`
- Change: center rotation changed from `+30` to `+90` degrees.

1. Logs panel split into dedicated modules (Op/Clue/Meeting)

- File: `lib/src/games/planetx/presentation/components/planetx_logs.dart`
- Change: replaced generic unified table with dedicated tables.

1. Meeting log semantic correction

- File: `lib/src/games/planetx/presentation/planetx_room_page.dart`
- Change: Meeting log now records only conference publish operations (`ready_publish` / `do_publish`) and no longer mixes generic state/ready updates.

1. Operation bar stage gating (high-impact gameplay fix)

- Files:
  - `lib/src/games/planetx/presentation/components/planetx_op_bar.dart`
  - `lib/src/games/planetx/presentation/planetx_room_page.dart`
- Change:
  - pass `game_stage` from room state
  - show only legal operations per stage:
    - `user_move`: `survey/target/research/locate`
    - `meeting_proposal`: `ready_publish`
    - `meeting_publish`: `do_publish`
    - `last_move`: `locate/do_publish`

1. Rules archive added for migration reference

- File: `.github/guides/planetx-rules-archive.md`
- Source: extracted from `ref/planetx_client/lib/utils/translation.dart` and `ref/planetx_client/lib/utils/rules.dart`

1. Local star-map marking parity and undo/redo reliability fixed

- Files:
  - `lib/src/games/planetx/presentation/planetx_room_page.dart`
  - `lib/src/games/planetx/presentation/components/planetx_star_map.dart`
- Change:
  - mark buffer now initializes without waiting for `map_sectors` (fallback by `map_type` / default count), avoiding inert taps before full state payload
  - mark history snapshots now record post-mutation state so `undo/redo` restores expected steps
  - initial local mark state aligned to legacy semantics (all slots start as confirm)
  - mark slot visuals aligned closer to legacy: excluded state uses icon dimming/overlay instead of green/blue coding
  - added secondary tap parity for desktop and aligned history tooltip wording

1. Center season semantics aligned closer to legacy spin model

- Files:
  - `lib/src/games/planetx/presentation/components/planetx_star_map.dart`
  - `lib/src/games/planetx/presentation/planetx_room_page.dart`
- Change:
  - center text now reflects season (SPR/SUM/AUT/WIN) instead of generic map-size/meeting label
  - top hint now shows `season + degree`
  - default local rotation now starts at Spring-compatible angle (`180`)

## 3. Open Issues (Priority)

### P0

1. End-to-end gameplay parity not yet proven

- Missing full flow verification: start -> operation cycles -> conference cycles -> endgame/scoring.

1. Manual regression evidence incomplete

- Need side-by-side smoke tests for Acquire and PlanetX in same runtime.

### P1

1. Clue log parity improved but wording parity still partial

- Current clue table now follows `clue index: secret -> clue detail` structure, sourced from `research_clues` and `research` operation results.
- Remaining gap: detail wording/i18n is still partially hardcoded and not fully aligned with legacy translation keys.
- Files:
  - `lib/src/games/planetx/presentation/components/planetx_logs.dart`
  - `lib/src/games/planetx/presentation/planetx_room_page.dart`

1. RoomInfos/MessageBar still drifted from legacy behavior

- Missing legacy interactions (rules button, richer room controls parity).
- File: `lib/src/games/planetx/presentation/components/planetx_sections.dart`

1. Op panels still minimal in rule constraints

- Operation widgets still use simplified input constraints; visible-sector and rule-cost UI hints are not fully parity.
- File: `lib/src/games/planetx/presentation/components/planetx_op_bar.dart`

1. Star-map toolbar i18n still partial

- Toolbar labels/tooltips in current migration still use hardcoded strings/placeholders in parts of the UI.
- File: `lib/src/games/planetx/presentation/components/planetx_star_map.dart`

### P2

1. Rules dialog not integrated in current UI

- Rules are archived in guides but not exposed in room page yet.

1. i18n parity not completed

- Several hardcoded labels remain in presentation layer.

## 4. Suggested Next Session Order

1. Finish clue detail i18n wording parity and edge-case phrasing.
2. Add rules dialog entry in room info/message area using the archived rules baseline.
3. Tighten operation validation UX in OpBar (visible sector ranges and stage hints).
4. Finish star-map toolbar i18n key wiring.
5. Run full parity smoke scenario and record pass/fail matrix.

## 5. Verification Notes

- Static checks after edits:
  - `planetx_star_map.dart`: no errors
  - `planetx_logs.dart`: no errors
  - `planetx_op_bar.dart`: no errors
  - `planetx_room_page.dart`: no errors
  - `planetx_sections.dart`: no errors
  - local mark updates: no errors in `planetx_room_page.dart` / `planetx_star_map.dart`

## 6. Handoff Risks

- Current implementation is improved but not full 1:1 parity yet.
- UI/behavior drift remains in clue semantics and room tooling.
- Do not treat this as release-ready parity until P0/P1 are closed.
