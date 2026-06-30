# Lucky Town — Scene Trees

The node layout of each `.tscn`, and the runtime tree once a game is running.

---

## Autoload tree (always present)

Loaded from `project.godot` in dependency order, parented to `/root`:

```
/root
├── Log
├── EventBus
├── RngService
├── DataRegistry
├── GameClock
├── Economy
├── SaveManager
├── GameState
├── QuestSystem
├── WorldDirector
└── <current main scene>
```

---

## boot.tscn

```
Boot (Node)            [boot.gd]
```

Waits for `DataRegistry.data_loaded`, then changes scene to the main menu.

---

## main_menu.tscn

```
MainMenu (Control)     [main_menu.gd]
├── Background (ColorRect)
└── Center (CenterContainer)
    └── VBox (VBoxContainer)
        ├── Title (Label)
        ├── Subtitle (Label)
        ├── NewGameButton (Button)   → _on_new_game_pressed
        ├── ContinueButton (Button)  → _on_continue_pressed   (disabled w/o auto-save)
        └── QuitButton (Button)      → _on_quit_pressed
```

---

## world.tscn (the playable city)

```
World (Node3D)         [world.gd]
├── Environment (WorldEnvironment)
├── Sun (DirectionalLight3D)
├── Ground (StaticBody3D)
│   ├── GroundMesh (MeshInstance3D)        — 80×80 plane
│   └── GroundShape (CollisionShape3D)     — box floor
├── Player (instance: player.tscn)
├── Agents (Node3D)    — visible CitizenAgent instances spawned at runtime
├── Props (Node3D)     — SlotMachine instances spawned from data at runtime
├── UiLayer (CanvasLayer)  — hosts the SlotUi when opened
└── Hud (instance: hud.tscn)
```

At `_ready()` the world spawns one slot machine per `slot_machines` entry (in a
ring) and gives the first N AI citizens a visible avatar. The rest of the
population is simulated headlessly by `WorldDirector`.

---

## player.tscn

```
Player (CharacterBody3D)   [player_controller.gd]
├── CollisionShape3D        — capsule
├── Mesh (MeshInstance3D)   — capsule (green)
└── CameraPivot (Node3D)
    └── Camera3D            — angled third-person view
```

The `CameraPivot` exists so camera yaw can be rotated independently of the body
(used to make movement camera-relative; mouse-look rotation is a Phase-2 add).

---

## citizen_agent.tscn

```
CitizenAgent (CharacterBody3D)   [citizen_agent.gd]
├── CollisionShape3D             — capsule
└── Mesh (MeshInstance3D)        — capsule (orange)
```

Bound to a `Citizen` model by id via `bind(id)`; wanders between random points.

---

## slot_machine.tscn (a prop / interactable)

```
SlotMachine (Area3D)        [slot_machine_interactable.gd]
├── CollisionShape3D         — trigger box (proximity)
└── Mesh (MeshInstance3D)    — gold cabinet
```

The `Area3D` detects the player body entering its trigger and tells the player
"Press E". On interact it emits `open_slot_ui` on the `EventBus`; the world
scene catches it and shows `SlotUi`.

---

## hud.tscn

```
Hud (CanvasLayer)           [hud.gd]
└── Root (Control)
    ├── TopBar (HBoxContainer)
    │   ├── MoneyLabel (Label)
    │   └── TimeLabel (Label)
    ├── PromptLabel (Label)   — "Press E: Play Slots"
    └── ToastLabel (Label)    — transient notifications
```

---

## slot_ui.tscn (modal, instanced on demand)

```
SlotUi (Control)            [slot_ui.gd]
├── Dim (ColorRect)         — darkens the world behind
└── Panel (PanelContainer)
    └── VBox (VBoxContainer)
        ├── Title (Label)
        ├── JackpotLabel (Label)
        ├── Grid (GridContainer)   — reels × rows cells
        ├── ResultLabel (Label)
        ├── BetRow (HBoxContainer)
        │   ├── BetDownButton  → _on_bet_down_pressed
        │   ├── BetLabel
        │   └── BetUpButton    → _on_bet_up_pressed
        └── ButtonRow (HBoxContainer)
            ├── SpinButton     → _on_spin_pressed
            └── CloseButton    → _on_close_pressed
```

Opening pauses `GameClock`; closing unpauses and unlocks player input.

---

## Runtime tree while playing

```
/root
├── (autoloads …)
└── World
    ├── Sun, Ground, Player, Hud
    ├── Agents
    │   ├── CitizenAgent (Aria)
    │   ├── CitizenAgent (Bram)
    │   └── … (visible slice)
    ├── Sun, Atmosphere (day/night + weather driver)
    ├── Props
    │   ├── SlotMachine (slot_fantasy / ghost / cyberpunk / ancient / scifi / cute / magic)
    │   └── … (one per slot_machines entry, in a ring)
    ├── UiLayer (CanvasLayer)
    │   └── SlotUi (only while a machine is open)
    ├── Hud (CanvasLayer)
    ├── TownBoard (CanvasLayer, toggle B)
    ├── AuctionUi (CanvasLayer, toggle V)
    ├── StatsUi (CanvasLayer, toggle G)
    └── PauseMenu (CanvasLayer, toggle Esc — save/load slots)
```
