# Scenes Guide (Researcher Notes)

This guide explains how scene assets are organized in `Scenes/` and how they are typically loaded during runtime.

## What This Covers

- The startup scene and high-level scene flow.
- Purpose of each scene subfolder.
- Important scene files to inspect first.
- Quick trace paths for understanding gameplay progression.

## Runtime Entry and Loading Flow

### Initial startup scene

Project startup is configured to:

- `res://Scenes/ui/title_menu.tscn`

### Main world composition

`res://Scenes/world_main.tscn` is a composition scene that instances:

- Player scene (`res://Scenes/Player/player.tscn`)
- A level scene under a `Levels` node (currently fallback hamlet)
- Core UI layers (`QuestList`, `MainHUD`)

### Common scene transitions

Runtime transitions are mainly coordinated through `SceneManager` in `scripts/SceneManager.gd`, with known level targets such as:

- `res://Scenes/Levels/tutorial - Copy.tscn`
- `res://Scenes/Levels/fallback_hamlet.tscn`
- `res://Scenes/Levels/file_system_forest.tscn`
- `res://Scenes/Levels/deamon_depths.tscn`
- `res://Scenes/Levels/bios_vault.tscn`
- `res://Scenes/Levels/proprietary_citadel.tscn`
- `res://Scenes/Levels/evilTuxBoss.tscn`

## Folder Map

### `Scenes/`

- `world_main.tscn`: world composition root (player + level + primary HUD).
- `tutorial_sequence.tscn`: tutorial flow UI/controller scene.
- `dialogue_balloon.tscn`: Dialogue Manager balloon runtime scene.
- `dialogue_balloon.gd`: balloon script override/behavior.

### `Scenes/Levels/`

World/level maps and progression spaces.

- `fallback_hamlet.tscn`: early/main hub area.
- `file_system_forest.tscn`: filesystem-themed level.
- `deamon_depths.tscn`: dungeon/depths area.
- `bios_vault.tscn` and `bios_vault_.tscn`: bios vault variants.
- `proprietary_citadel.tscn`: late-game citadel area.
- `evilTuxBoss.tscn`: boss encounter map.
- `tutorial.tscn`, `tutorial - Copy.tscn`: tutorial maps (the copy variant is actively referenced in scene mapping).
- `forest.tscn`, `forest_no_plain.tscn`, `cone.tscn`: additional/experimental level content.

Related level visuals in this folder:

- `river.gdshader`, `sky.gdshader`

### `Scenes/Player/`

- `player.tscn`: playable character root.
- `tux.tscn`: companion/follower actor scene.

### `Scenes/ui/`

Global and in-world interface scenes.

- `title_menu.tscn`: startup/title flow.
- `MainHUD.tscn`: gameplay HUD.
- `TerminalPanel.tscn`, `TerminalShop.tscn`: terminal and shop UI.
- `QuestWindow.tscn`, `QuestList.tscn`, `QuestListItem.tscn`, `QuestSideButton.tscn`: quest interfaces.
- `pause_menu.tscn`, `controls_help.tscn`: pause and controls overlays.
- `interaction_prompt.tscn`: interact hint overlay.
- `black_text_cutscene.tscn`: cutscene text overlay.

Note: `title_menu.tscn*.tmp` files appear to be editor temp artifacts, not canonical assets.

### `Scenes/combat/`

Combat-related scenes and combat minigame UI.

- `combat_encounter.tscn`: encounter scene root.
- `combat_terminal_ui.tscn`: command terminal combat panel.
- `combat_tutorial_popup.tscn`: combat onboarding popup.
- `dependency_resolver_minigame.tscn`: puzzle minigame.
- `timing_minigame.tscn`: timing minigame.
- `tux_terminal_helper_popup.tscn`: helper hints popup.

Related combat visuals in this folder:

- `cracked_glass.gdshader`, `crt_effect.gdshader`
- `cracked_glass.tres`, `crt_terminal_theme.tres`

### `Scenes/globals/`

- `loading_screen.tscn`: global loading transition scene.

## Suggested Reading Order

1. `Scenes/ui/title_menu.tscn`
2. `Scenes/world_main.tscn`
3. `Scenes/Levels/fallback_hamlet.tscn`
4. `Scenes/Player/player.tscn`
5. `Scenes/ui/MainHUD.tscn`
6. `Scenes/combat/combat_encounter.tscn`
7. `Scenes/dialogue_balloon.tscn`

## Research Trace Recipes

- To study the first-play path:
  - Start at `Scenes/ui/title_menu.tscn` then follow transition into `Scenes/world_main.tscn`.
- To study level progression:
  - Use scene constants/mappings in `scripts/SceneManager.gd` and inspect target scenes in `Scenes/Levels/`.
- To study combat UX:
  - Start at `Scenes/combat/combat_encounter.tscn`, then inspect terminal and minigame scenes in the same folder.
- To study quest presentation:
  - Inspect `Scenes/ui/QuestList.tscn`, `Scenes/ui/QuestWindow.tscn`, and `Scenes/ui/MainHUD.tscn` together.

## Maintenance Notes

- Keep one clear canonical scene per gameplay purpose; avoid leaving duplicate variants unclear unless actively needed for compatibility.
- When adding new levels, update both:
  - scene transition references in `scripts/SceneManager.gd`
  - this guide's `Scenes/Levels/` list
- Prefer keeping dialogue content in `.dialogue` assets and using scene scripts for state/control wiring.