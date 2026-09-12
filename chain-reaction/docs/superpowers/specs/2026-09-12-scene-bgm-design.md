# Scene BGM playlists

Date: 2026-09-12

## Goal

Replace folder-scan sequential BGM with scene-owned, editor-editable playlists.

- Main menu: loop the first usable track.
- Game: shuffle a copy of the list on enter, then cycle that order until the player leaves.
- Menu ↔ game: fade the current track out, wait, then start the new playlist.
- Fade length and post-fade silence are inspector fields, not code constants.
- Track lists are inspector arrays on the scenes, not hardcoded paths.

## Non-goals

- Crossfade (old and new overlapping).
- Per-map BGM.
- Changing collapse SE.
- Committing copyrighted BGM files.

## Architecture

`AudioService` stays an Autoload, but loads from `res://scenes/audio_service.tscn` (Node + existing script) so `fade_seconds` and `gap_seconds` are editable in the inspector.

It does not scan `res://assets/audio/bgm/` and does not start playback in `_ready`.

`main_menu.tscn` and `game.tscn` each export `bgm_tracks: Array[AudioStream]`. Their `_ready` requests playback:

- Menu: `AudioService.play_playlist(bgm_tracks, false)`
- Game: `AudioService.play_playlist(bgm_tracks, true)`

In-game Restart does not change scene and must not touch BGM.

Mute still drives the Master bus. Fade drives the BGM `AudioStreamPlayer.volume_db` only.

## Request API

```gdscript
play_playlist(tracks: Array[AudioStream], shuffle: bool) -> void
```

Normalize `tracks` by dropping nulls. Empty result: fade out if anything is playing, then stay silent (no gap wait for a next track).

`shuffle == false`: keep only the first remaining stream; when it ends, play it again.

`shuffle == true`: copy the remaining streams, shuffle with `AudioService.rng` (a `RandomNumberGenerator` the tests can seed). Play index 0, 1, …, wrap to 0. Do not reshuffle until the next `play_playlist(..., true)`.

Every `play_playlist` is a new request (no “same list, skip transition” shortcut).

## Transition timing

States: `idle`, `playing`, `fading`, `waiting`.

Advance `fading` and `waiting` in `_process(dt)` (no Tween).

| Situation | Behavior |
|-----------|----------|
| First request this session, nothing playing | Start immediately. No fade, no gap. |
| Request while `playing` | Fade from current `volume_db` to silence over `fade_seconds`, stop, wait `gap_seconds`, start the new playlist. |
| Request while `fading` or `waiting` | Keep fading from the current volume (do not restart the fade). Replace the pending playlist. After fade, wait `gap_seconds`, then start the latest pending playlist. |
| `fade_seconds <= 0` and something was playing | Stop immediately, then wait `gap_seconds`. |
| `gap_seconds <= 0` | Start the new playlist as soon as fade (or immediate stop) finishes. |

Silence is `volume_db <= -80`. After fade, stop the player and restore `volume_db` to `0` before the next `play()`.

Track end (finished while `playing`): next item in the active order, or the same track in single-loop mode. Do not use the file’s import-loop flag.

## Editor fields

On `audio_service.tscn`:

- `fade_seconds` default `1.0`
- `gap_seconds` default `2.0`

On `main_menu.tscn` and `game.tscn`:

- `bgm_tracks` default empty. Empty is valid (no music). Assign streams in the inspector when files exist.

## Tests (Phase E)

Use a fresh `audio_service.gd` instance, not the live Autoload. Drive time with `_process(dt)`. Use short `AudioStreamWAV` fixtures.

Must cover:

1. Existing mute Master-bus behavior still passes.
2. Autoload path in `project.godot` points at the scene, not the raw script.
3. Empty playlist → no playback.
4. `shuffle == false` with two streams → only the first plays; after finish it is the first again.
5. `shuffle == true` with a seeded RNG → order is a permutation of the input; wrapping repeats that permutation, not a new shuffle.
6. Playing then `play_playlist` again → volume falls over `fade_seconds`, player stops, still silent through `gap_seconds`, then the new stream starts.
7. First `play_playlist` with nothing playing starts without waiting `gap_seconds`.
8. Scripts under `res://scripts` still must not `preload("res://assets/...")` paths (existing Phase C check). No new folder-scan of BGM.

Tests must not sleep real wall-clock 2 seconds.

## File changes

- `scripts/app/audio_service.gd` — playlist request, fade/wait state machine, remove directory scan and auto-start.
- `scenes/audio_service.tscn` — new Autoload scene.
- `project.godot` — Autoload `AudioService` → the scene.
- `scripts/main_menu.gd` / `scripts/game.gd` — export `bgm_tracks`, call `play_playlist` in `_ready`.
- `scenes/main_menu.tscn` / `scenes/game.tscn` — persist the export.
- `tests/run_phase_e.gd` — cases above.

## Out of scope unless already true

Do not add BGM files in this change. Playback with empty inspector arrays is silent until the user assigns streams.
