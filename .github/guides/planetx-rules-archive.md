# Planet X Rules Archive

This document archives the rules text from the legacy client (`ref/planetx_client`) for easier reference during UI alignment.

## Source

- `ref/planetx_client/lib/utils/translation.dart`
- `ref/planetx_client/lib/utils/rules.dart`

## Sector Rules

- Comet: 2, only in prime-index sectors.
- Asteroid: 4, adjacent to another asteroid.
- Dwarf Planet (standard): 1, not adjacent to Planet X.
- Dwarf Planet (expert): 4 in a contiguous band of 6, with first and last being dwarf planets, not adjacent to Planet X.
- Nebula: 2, adjacent to true space.
- Planet X: 1, not adjacent to dwarf planet, appears as space in some operations.
- Space (standard): 2 (remember Planet X appears as space).
- Space (expert): 5 (remember Planet X appears as space).

## Operation Rules

- Survey: Survey a visible segment and reveal count of a target sector type.
- Target: Scan one sector and reveal its type.
- Research: Research a clue relationship between one or two sector types.
- Locate X: Provide two adjacent sector types to locate Planet X.
- Ready Publish: Prepare theories to publish (expert: up to two).
- Do Publish: Publish prepared theories; revealed sectors cannot be published again.

## Gameplay Rules (from `gameplay_rules_desc`)

### 3 Phases

1. Operation phase: players take turns, perform one operation, then advance by operation cost.
2. Conference phase: triggered at conference markers. Players prepare publication count, then publish in order.
3. Endgame phase: triggered when someone locates Planet X. Earlier-order players get one last action.

### Conference Details

- Conference progress advances by one for each round of publication.
- On third advancement, Planet X location is revealed.
- Wrongly published theories are removed and penalized by one-step advancement.
- Correct publication reveals all theories for that sector; incorrect related items may still advance progress.

### Additional Constraints

- At most two locate operations per game.
- No player may do research in two consecutive turns.
- Visible sectors rotate with progress and remain a half-circle from the last player.
- Survey and target must operate within visible sectors.
- Encountering X marker reveals an X-related clue.

### Scoring

- First correct publication for a sector: +1
- Correct comet: +3
- Correct asteroid: +2
- Correct dwarf planet: +2 (standard mode mentions +4)
- Correct nebula: +4
- First correct Planet X locate: +10
- Later correct locate: +2 * distance from first locator (10/8/6/4/2)

## Legacy UI Mapping Notes

- Legacy conference log (`title_conference_log`) only records conference-related publish events, not generic state or ready-state messages.
- Rules dialog in legacy client is composed of three sections: sector rules, operation rules, and gameplay rules.
