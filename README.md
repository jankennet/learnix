<p align="center">
  <h1>Learnix</h1>
  <p><b>An Educational 3D Interactive Game Experience</b></p>
</p>

## Overview

**Learnix** is a capstone project—an innovative educational game developed in **Godot 4.5** that combines interactive storytelling with knowledge assessment. Players explore a digital world populated by personified system components (NPCs), discovering how computing systems work through dialogue, quests, and strategic challenge encounters.

## Project Description

Learnix transforms technical education into an engaging narrative experience. Instead of traditional lectures, players learn about file systems, system administration, and network security by helping in-world characters and answering adaptive knowledge quizzes.

### Core Features

- **Narrative-Driven Learning**: Dialogue-based interactions with NPCs (Lost File, Broken Link, Gate Keeper, Sage, etc.) that teach computing concepts through storytelling
- **Quest System**: Multi-step missions that reward players with proficiency keys and system access, creating natural progression
- **Adaptive Difficulty**: Quiz difficulty adjusts based on player progress and quest completion (Easy, Intermediate, Hard)
- **Combat Encounters**: Real-time combat system that serves as both challenge and alternative to knowledge assessment
- **Dialogue Manager Integration**: Rich narrative flow using the Dialogic addon for complex branching conversations
- **3D Environment Exploration**: Immersive level design with player physics, camera management, and interactive NPCs

### Learning Outcomes

Players gain understanding of:
- File system organization and recovery
- System processes and daemon management
- Network access control and authentication
- Security concepts and compliance
- Problem-solving and decision-making in system administration

## Technical Stack

- **Engine**: Godot 4.5 (Forward+ renderer)
- **Language**: GDScript
- **UI**: UI framework with quest tracking and dialogue balloons
- **Architecture**: Scene-based teleportation, global state management (SceneManager), NPC interaction registry

## Gameplay Flow

1. **Exploration Phase**: Navigate the world and discover NPCs
2. **Quest Phase**: Accept missions and gather resources (proficiency keys, sudo tokens, file fragments)
3. **Assessment Phase**: Complete knowledge quizzes tailored to your progress
4. **Progression Gate**: Earn access to restricted areas by demonstrating competency
5. **Boss Challenge**: Face the Sage in the BIOS Vault with adaptive difficulty based on preparation

## Project Structure

```
learnix/
├── Scenes/              # Level layouts and scene hierarchies
│   ├── Levels/         # Game world levels (bios_vault, forest, etc.)
│   ├── combat/         # Combat encounter scenes
│   ├── Player/         # Player character and controls
│   ├── ui/             # UI components (quest panel, HUD)
│   └── globals/        # Autoload scenes (Camera3D manager, etc.)
├── scripts/            # GDScript game logic
│   ├── Quest*.gd       # Quest system
│   ├── *_script.gd    # Entity behavior (NPC, boss interactions)
│   └── SceneManager.gd # Global scene and state manager
├── dialogues/          # Dialogue resource files (.dialogue)
├── Assets/             # Sprites, animations, fonts
└── addons/            # Third-party plugins (Dialogic, Terrain3D)
```

## Current Status

**In Development** - Bios Vault assessment area with Sage NPC and adaptive 15-question knowledge quiz (randomized questions, shuffled answer options to prevent click-spam)

### Recently Completed
- ✅ Player teleportation and scene manager refactor
- ✅ Interactive NPC system with dialogue triggering
- ✅ Sage character with adaptive difficulty quiz
- ✅ Area-based intro sequence with camera effects
- ✅ 3-fail combat gate mechanic
- ✅ Quest progression tracking

### In Progress
- Combat encounter system integration
- Additional quest chains
- World expansion (additional levels and NPCs)

## Installation & Setup

1. **Prerequisites**: Godot 4.5+
2. **Clone or extract** the project
3. **Open in Godot**: File → Open Project → select project folder
4. **Install Dependencies**: 
   - Dialogic addon (included in `addons/`)
   - Terrain3D addon (included in `addons/`)
5. **Run**: Press F5 or click Play

## Gameplay Instructions

- **Movement**: WASD keys
- **Interact with NPCs**: Approach and press (interact button - TBD)
- **Complete Quests**: Follow objective markers and return to NPCs
- **Take Quiz**: Answer 15 randomized questions (3 strikes before forced combat)
- **Combat**: TBD combat controls

## Credits

**Developed as a Capstone Project**

### Team & Contributors
- Game Design & Development
- Narrative Design
- Technical Implementation

### Third-Party Assets & Tools
- [Godot Engine](https://godotengine.org/)
- [Dialogic 2](https://github.com/dialogic-godot/dialogic) - Dialogue system addon
- Terrain3D addon for environmental design
- Character sprite art by **miwabun**

---

**Learnix**: Making computer science education interactive, engaging, and fun.
