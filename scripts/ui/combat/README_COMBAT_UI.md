# Combat UI Refactored Architecture

## File Structure
```
scripts/ui/combat/
├── CombatUIController.gd     # Root coordinator (attach to scene root)
├── TerminalView.gd           # Typewriter + message log
├── InputController.gd        # LineEdit, suggestions, tab-complete
├── HUDView.gd                # Player/Enemy HP bars
├── CombatFX.gd               # Shake + flash animations
└── CommandSuggestions.gd     # Wrapper around CommandParser
```

## Signal Flow Diagram
```
┌─────────────────────────────────────────────────────────────────┐
│                    USER INPUT                                    │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
              ┌─────────────────────┐
              │   InputController   │
              │   (LineEdit owner)  │
              └──────────┬──────────┘
                         │ command_submitted(text)
                         ▼
              ┌─────────────────────┐
              │ CombatUIController  │◄────────────────────────────┐
              │   (Coordinator)     │                              │
              └──────────┬──────────┘                              │
                         │ process_input(text)                     │
                         ▼                                         │
              ┌─────────────────────┐                              │
              │  TurnCombatManager  │──────────────────────────────┤
              │   (Game Logic)      │  signals:                    │
              └─────────────────────┘  - message_logged            │
                                       - turn_changed              │
                                       - player_turn_started       │
                                       - enemy_turn_started        │
                                       - damage_dealt              │
                                       - awaiting_input            │
                                                                   │
              ┌─────────────────────────────────────────────────────┘
              │ Routes signals to appropriate view controllers
              ▼
    ┌─────────┴─────────┬──────────────────┬───────────────────┐
    ▼                   ▼                  ▼                   ▼
┌──────────┐     ┌──────────┐       ┌──────────┐        ┌──────────┐
│ Terminal │     │   HUD    │       │ CombatFX │        │  Input   │
│   View   │     │   View   │       │          │        │Controller│
└──────────┘     └──────────┘       └──────────┘        └──────────┘
 print_message()  update_player()   hit_player()        set_turn_text()
 clear()          update_enemy()    hit_enemy()         set_enabled()
```

## Scene Hierarchy Example
```
CombatUI (Control) ← CombatUIController.gd
├── TerminalPanel (Control) ← TerminalView.gd
│   ├── Terminal (RichTextLabel)
│   └── InputRow (HBoxContainer) ← InputController.gd
│       ├── TurnIndicator (Label)
│       ├── CommandInput (LineEdit)
│       └── SuggestionLabel (Label)
├── RightPanel (Control) ← HUDView.gd
│   └── SideUI (VBoxContainer)
│       ├── PlayerHP (ProgressBar)
│       ├── EnemyHP (ProgressBar)
│       └── CommandsList (RichTextLabel)
├── Layout (Control)
│   └── Stage (Control)
│       ├── Characters (Control)
│       │   ├── PlayerSprite (ColorRect)
│       │   └── EnemySprite (ColorRect)
│       └── Anim (AnimationPlayer)
└── CombatFX (Node) ← CombatFX.gd
```

## NodePath Wiring (Inspector Setup)

### CombatUIController.gd
```gdscript
# Export paths to configure in Inspector:
@export var combat_manager_path: NodePath      # → /root/Main/TurnCombatManager
@export var enemy_node_path: NodePath          # → (optional enemy reference)
@export var terminal_view_path: NodePath       # → TerminalPanel
@export var input_controller_path: NodePath    # → TerminalPanel/InputRow
@export var hud_view_path: NodePath            # → RightPanel
@export var combat_fx_path: NodePath           # → CombatFX
```

### TerminalView.gd
```gdscript
@export var terminal_path: NodePath            # → Terminal (RichTextLabel)
@export var typing_speed: float = 0.01
```

### InputController.gd
```gdscript
@export var input_path: NodePath               # → CommandInput (LineEdit)
@export var turn_label_path: NodePath          # → TurnIndicator (Label)
@export var suggestion_label_path: NodePath    # → SuggestionLabel (Label)
```

### HUDView.gd
```gdscript
@export var player_bar_path: NodePath          # → PlayerHP (ProgressBar)
@export var enemy_bar_path: NodePath           # → EnemyHP (ProgressBar)
@export var commands_list_path: NodePath       # → CommandsList (RichTextLabel)
```

### CombatFX.gd
```gdscript
@export var animation_player_path: NodePath    # → ../Layout/Stage/Anim
@export var player_sprite_path: NodePath       # → ../Layout/Stage/Characters/PlayerSprite
@export var enemy_sprite_path: NodePath        # → ../Layout/Stage/Characters/EnemySprite
```

## Migration from combat_ui.gd

### Before (Monolithic)
```gdscript
# Single script handles EVERYTHING:
# - Signal connections
# - Input handling
# - Typewriter animation
# - HUD updates
# - Shake/flash effects
# - Autocomplete logic
```

### After (Separated Concerns)
| Responsibility | Old Location | New Location |
|----------------|--------------|--------------|
| Signal routing | combat_ui._ready() | CombatUIController._connect_combat_signals() |
| Message display | combat_ui._typewriter_append() | TerminalView.print_message() |
| Input handling | combat_ui._on_command_entered() | InputController.command_submitted signal |
| Tab complete | combat_ui._unhandled_input() | InputController._handle_tab_complete() |
| HP bars | combat_ui._update_hud() | HUDView.update_player/enemy() |
| Hit effects | combat_ui._shake/_flash() | CombatFX.hit_player/enemy() |
| Suggestions | Direct CommandParser call | CommandSuggestions.suggest() |

## Debug Rules Implemented

1. **No hard node paths**: All dependencies use @export NodePath
2. **Graceful degradation**: Each controller prints warnings instead of crashing
3. **Testable isolation**: Each script can run without others
4. **Clear ownership**: Each view owns its specific UI nodes

## Testing Individual Controllers

### TerminalView (Standalone Test)
```gdscript
# Add to scene with just a RichTextLabel child
var terminal = TerminalView.new()
terminal.print_message("Test message", Color.GREEN)
```

### InputController (Standalone Test)
```gdscript
# Connect to command_submitted and verify signals
var input = InputController.new()
input.command_submitted.connect(func(t): print("Got: ", t))
```

### HUDView (Standalone Test)
```gdscript
# Just needs ProgressBar children
var hud = HUDView.new()
hud.update_player(50, 100)
hud.update_enemy(75, 150)
```

## Notes

- **CommandSuggestions.gd** is a `RefCounted` class with static methods - no scene node needed
- The old `combat_ui.gd` can be archived or deleted after migration
- All color mappings preserved exactly from original
- Typewriter skip-on-keypress behavior preserved
