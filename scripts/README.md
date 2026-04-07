# Scripts Guide (Researcher Notes)

This document maps the `scripts/` folder so new contributors and researchers can quickly understand where behavior lives and how systems connect.

## Scope

- Engine: Godot 4.x (GDScript)
- Folder covered: `res://scripts/`
- Related script roots:
  - `res://scripts/combat/`
  - `res://scripts/combat/enemies/`
  - `res://scripts/ui/`
  - `res://scripts/ui/combat/`

## Runtime Entry Points (Autoloads)

From project settings (`[autoload]`):

- `SceneManager` -> `res://scripts/SceneManager.gd`
  - Central game-state registry and progression flags.
- `InteractionManager` -> `res://scripts/Interaction_Manager.gd`
  - Tracks interactables and interaction focus.
- `PerformanceManager` -> `res://scripts/performance_manager.gd`
  - Runtime quality and frame-time helpers.

Related autoloads (outside `scripts/` but often touched by script logic):

- `DialogueManager` -> `res://addons/dialogue_manager/dialogue_manager.gd`
- `InteractionPrompt` -> `res://Scenes/ui/interaction_prompt.tscn`
- `PauseMenu` -> `res://Scenes/ui/pause_menu.tscn`
- `LoadingScreen` -> `res://Scenes/globals/loading_screen.tscn`

## System Overview

- World progression and unlocks are mostly state-driven through `SceneManager`.
- NPC interactions are usually proximity + interaction prompt + DialogueManager conversation flow.
- Quest state is split into definitions/resources (`Quest.gd`, `QuestDefinitions.gd`) and runtime control (`QuestManager.gd`, UI bindings).
- Combat uses modular subsystems:
  - encounter/state orchestration,
  - command parsing,
  - terminal/combat UI,
  - enemy behavior scripts,
  - optional minigames for command outcomes.

## Folder Map

### Root `scripts/`

#### Core flow, world, and managers

- `SceneManager.gd`: global progression/state hub (currency, unlocks, flags, and cross-system signals).
- `Interaction_Manager.gd`: interaction registration/selection logic for world objects and NPCs.
- `performance_manager.gd`: tuning/performance support.
- `loading_screen.gd`: transition/loading animation control.
- `camera_main.gd`: main camera behavior.

#### Player and companion behavior

- `nova_controls.gd`: player character movement and controls.
- `tux_follower.gd`: follower behavior for Tux companion.
- `tux_dialogue_controller.gd`: Tux dialogue and context-triggered speech control.
- `tutorial_tux_actor.gd`: tutorial-specific Tux movement/actor behavior.

#### Quests

- `Quest.gd`: quest resource/class data model.
- `QuestDefinitions.gd`: quest catalog/definition setup.
- `QuestManager.gd`: active quest lifecycle management.
- `QuestUI.gd`: quest UI integration bridge.
- `QuestListItem.gd`: quest list item widget behavior.

#### Tutorials, gates, and progression triggers

- `tutorial_sequence_controller.gd`: tutorial sequence orchestration.
- `bios_vault_intro.gd`: Bios Vault intro sequence/controller.
- `boss_room_whyno_exit.gd`: exit gating logic for boss area.
- `sudo_boss_door.gd`: boss door interaction/gating.
- `fallbackHamlet_Area3D.gd`: area trigger fallback flow in Hamlet region.
- `proprietary_citadel.gd`: proprietary citadel progression and interactions.
- `evil_tux_boss.gd`: Evil Tux world-side boss control.

#### Interaction, movement, and utility scripts

- `npc_script.gd`: base NPC world interaction behavior.
- `teleport.gd`: area teleport trigger behavior.
- `ConfirmTeleport_Script.gd`: confirm/cancel teleport UI layer.
- `collision_builder.gd`: collision generation/build helper.
- `LostFileSpawner.gd`: Lost File enemy spawn orchestration.

### `scripts/combat/`

#### Combat state and orchestration

- `turn_combat_manager.gd`: turn loop, command execution pipeline, and combat signals.
- `encounter_controller.gd`: higher-level encounter state transitions.
- `combat_terminal_ui.gd`: terminal-style combat panel integration.
- `command_parser.gd`: parsing/validation of command inputs.

#### Combat minigames and helper UI

- `timing_minigame.gd`: timing-based execution bonus mechanic.
- `dependency_resolver_minigame.gd`: dependency puzzle minigame.
- `puzzle_state_handler.gd`: puzzle state helper/model logic.
- `combat_tutorial_popup.gd`: tutorial popup shown during combat onboarding.
- `tux_terminal_helper_popup.gd`: assistant popup/hints in terminal combat.

### `scripts/combat/enemies/`

- `printer_beast_enemy.gd`: base/primary enemy encounter behavior.
- `driver_remnant_enemy.gd`: driver remnant enemy logic.
- `lost_file_enemy.gd`: Lost File enemy logic and mode switching.
- `broken_link_enemy.gd`: Broken Link enemy logic.
- `hardware_ghost_enemy.gd`: Hardware Ghost enemy logic.
- `evil_tux_enemy.gd`: Evil Tux enemy specialization.
- `sage_enemy.gd`: Sage enemy specialization.

### `scripts/ui/`

#### HUD, menus, and overlays

- `main_hud.gd`: primary in-game HUD logic and command event bridge.
- `pause_menu.gd`: pause menu behavior.
- `title_menu.gd`: title/start menu flow.
- `TerminalPanel.gd`: terminal panel UI logic.
- `terminal_shop.gd`: terminal shop interaction logic.
- `interaction_prompt.gd`: interaction prompt display behavior.
- `controls_help.gd`: controls help panel.
- `digital_reward_popup.gd`: rewards popup flow.
- `black_text_cutscene.gd`: text-only cutscene overlay.

#### Quest-facing UI

- `QuestWindow.gd`: quest window panel behavior.
- `QuestSideButton.gd`: side quest button/toggle behavior.
- `proficiency_key_icon.gd`: proficiency/key icon state rendering.

### `scripts/ui/combat/`

- `CombatUIController.gd`: wires combat backend signals to visual widgets.
- `TerminalView.gd`: terminal output/typing presentation.
- `InputController.gd`: command input capture and submission.
- `HUDView.gd`: combat HUD values and status display.
- `CombatFX.gd`: combat visual effects orchestration.
- `CommandSuggestions.gd`: command suggestion generation/lookup support.

## Suggested Reading Order (Fast Onboarding)

1. `SceneManager.gd`
2. `Interaction_Manager.gd`
3. `nova_controls.gd`
4. `npc_script.gd`
5. `QuestManager.gd` + `QuestDefinitions.gd`
6. `combat/turn_combat_manager.gd`
7. `combat/command_parser.gd`
8. `ui/combat/CombatUIController.gd`

## Trace Recipes (for Researchers)

- To follow quest progression:
  - Start at `QuestManager.gd`, then inspect UI consumers (`QuestUI.gd`, `ui/QuestWindow.gd`).
- To follow a world interaction:
  - Start at `Interaction_Manager.gd`, then inspect actor script (`npc_script.gd`, trigger scripts like `teleport.gd`).
- To follow combat command resolution:
  - Start at `combat/command_parser.gd` and `combat/turn_combat_manager.gd`, then inspect combat UI controller and enemy script.

## Maintenance Notes

- Prefer adding new gameplay logic in focused scripts over expanding monolithic managers.
- Keep dialogue text in `.dialogue` assets where possible, and use scripts for flow/state hooks.
- When adding a new enemy or encounter type, mirror the existing split:
  - behavior script in `scripts/combat/enemies/`
  - encounter orchestration in `scripts/combat/`
  - presentation updates in `scripts/ui/combat/`
