# Meowydom

Living Room Wars, iteration 1. This is a Godot proof of concept for the two-player battle: one person against an AI, on a phone held sideways. It is a playable foundation, not a finished release.

The other rooms in the Meowydom source pack are expansions and are not in this project. Online matches are planned later through a Laravel server. The battle state can already be saved and restored as JSON (`to_data()` / `apply_data()` in the rules script, version key `"v": 1`). That snapshot is the seam for the server. The server itself is not here.

Art and the playtest rules are © 2026 Tinkree Maker Labs ([meowydom.com](https://www.meowydom.com)).

## Godot version

**Godot 4.7.2 stable**, GL Compatibility.

`project.godot` requires feature `4.7`. Open this folder (the one that contains `project.godot`) in that editor. The first open imports the art. Press F5 to play. The window is 1280×720, stretch mode `canvas_items`, and the phone orientation is landscape. Android back is handled in game code (`quit_on_go_back` is off).

There is no Android export preset yet. Install the Android export template in the editor when you want a package. Export presets are gitignored because Godot can store script-encryption keys in them.

## How a match plays

Play vs AI, pick one of the four armies (Black, Calico, Cream, Orange), then deploy. The boss stays on the floor. You can place pieces yourself or use Quick defense. Roll initiative, then on your turn roll one die and choose one legal action. The AI plays the other army.

## Layout

| Path | What it is |
| --- | --- |
| `scenes/main.tscn` | Main scene. The screens are built in code. |
| `scripts/ui/main.gd` | Menu, army select, deploy, initiative, battle, result. |
| `scripts/rules/battle_rules.gd` | Living Room Wars rules. |
| `scripts/rules/battle_ai.gd` | Greedy AI for deploy and turns. |
| `tests/run_tests.gd` | Headless test runner. |
| `tests/test_rules.gd` | Rules checks. |
| `assets/armies/` | Black, Calico, Cream, and Orange sprites. |
| `assets/ui/` | Board, logo, hearts, shields, and die faces. |

Army PNGs are transparent and about 480px on the long side. One box image is reused for every Box Fort in that color. `.import` files and `.uid` files are committed so import settings and script identities stay stable. The `.godot/` folder is not.

## Tests

From this folder, with the Godot 4.7.2 console binary:

```text
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/run_tests.gd
```

A passing run prints `ALL CHECKS PASSED` and `RESULT 0`. The tests call the rules scripts directly. They do not need the editor class cache, so the test files preload scripts instead of using `class_name`.

## Rules this build is using

The engine follows the 2026 playtest booklet. Where that booklet is silent, the code assumes:

- One heart is 2 HP. A roll of 2, 4, or 6 damage removes 1, 2, or 3 hearts. Extra damage does not spill onto another piece.
- A shield cancels the whole attack. On a multi-cat capture, removing one shield spends one capture.
- A fortified group is one Alley Cat or one Yarn Cannon plus one Box Fort. The group has 2 hearts. A cannon loses those before its own hearts. The box is captured only when the group is destroyed.
- Capture and cannon fire cannot pull a piece out of a fortified group.
- Only one Yarn Cannon per army can sit on the sofa or the rug, and it needs two side-by-side slots. The boss cannot use either.
- Capturing either boss ends the battle. Equal jail VP is a draw. An initiative tie is rerolled.

## Not in iteration 1

Hotseat, AI difficulty settings, sound, mid-battle save, an Android package name, and the Laravel game server. Only this living-room battle exists.
