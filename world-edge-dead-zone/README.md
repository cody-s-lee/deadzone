# World Edge Dead Zone (0.1.0)

Factorio 2.0 mod. On finite-size maps (e.g. ribbon worlds) it keeps a band of tiles along the map edges
completely plain: only the fill tile, no resources, water/lava/other liquid, cliffs, trees/plants, rocks,
fish, decoratives or enemy spawners/worms. Space Age is supported but not required.

## Settings (startup)
| Setting | Default | Meaning |
|---|---|---|
| `world-edge-dead-zone-width` | 32 (0-512) | Zone width in tiles, inward from each finite edge. 0 disables the mod. |
| `world-edge-dead-zone-tile` | `grass-1` | Fill tile: `grass-1`, `dirt-1`, `sand-1`, `concrete`. |
| `world-edge-dead-zone-apply-to-width` | false | Also apply to left/right edges when map width is finite. Top/bottom is always used when height is finite. |
| `world-edge-dead-zone-all-surfaces` | true | Apply to every surface; if false, Nauvis only. Space platforms are always skipped. |

The map is centred on 0,0; edges are at ±`map_gen_settings.height/2` (and `.width/2`). An axis with size 0 (infinite) is ignored.
If a map is smaller than `2 * width + 32`, the zone is shrunk so at least 32 tiles remain in the middle
(disabled on that axis if even that is impossible) and a warning is printed to chat on first load.

## How it works
Everything is done at runtime:
* `on_chunk_generated`: tiles in the zone are set to the fill tile (`correct_tiles = false`), then entities are
  destroyed by *type* (`resource`, `cliff`, `tree`, `plant`, `simple-entity`, `fish`, plus enemy-force
  `unit-spawner` and `turret`), and decoratives via `destroy_decoratives`. Tiles outside the map are never touched.
* `on_init` / `on_configuration_changed`: already generated chunks overlapping the zone are processed once per
  version/settings change (player-placed tiles are preserved; only natural tiles are replaced).
* `on_surface_created`: new surfaces are handled; `on_biter_base_built`: enemy expansion inside the zone is destroyed.
* No randomness is used; everything is deterministic and multiplayer-safe.

### Why not data-stage noise expressions?
The plan was to multiply a distance-to-edge mask into every autoplace expression. That is not possible cleanly:
map width/height live in `map_gen_settings`, which is not readable in the data stage, and I found no noise
variable exposing it in the vanilla data. Edge position can't be baked into the expressions, so the mod uses the
runtime path for everything. Consequence: the engine still *generates* the content, and the mod removes it the same tick.

## Limitations
* Enemy units already walking around in the zone are not removed (only bases/worms).
* Retroactive processing covers chunks that exist when the mod is added/changed; it replaces natural tiles in the
  zone (e.g. a lake touching the edge) and deletes the listed entity types there, but never player-force entities.
* Odd map sizes: edges are rounded inward so void tiles are never modified.
* Other mods' content that does not use the listed entity types (e.g. custom `unit` nests) isn't removed.
* Large widths on small maps are clamped (see above).
* Not yet tested in the real Factorio engine (see `tests/`).

## Tests (`tests/`)
* `run.py` / `harness.lua`: mock-engine tests of `control.lua` (`pip install lupa; python3 -I run.py`).
* `map-gen-settings.json`: height 128, width 0, high resource/water/tree/enemy frequency. Create with
  `factorio --create test --map-gen-settings tests/map-gen-settings.json`.
* `verify-in-game.lua`: console script that force-generates the map and counts forbidden things in the zone (expect all zeros).
